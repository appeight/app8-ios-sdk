import Combine
import Foundation

class CDatePickerViewModel: CBaseViewModel<DSL.Model.Component.DatePicker.C> {

    /// Publisher for date changes from the view
    let dateChanged = PassthroughSubject<Date, Never>()

    /// Publisher for external updates (from variable changes)
    let externalDateUpdate = PassthroughSubject<Date, Never>()

    /// Current date value
    private(set) var currentDate: Date = Date()

    /// Flag to prevent feedback loops
    private var isUpdatingFromVariable = false

    private var cancellables = Set<AnyCancellable>()

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Local wall-clock time with the device's UTC offset, e.g.
    /// `2026-03-04T14:30:00+01:00`. Used for `time` / `dateAndTime` so the
    /// picked time survives the round-trip (and `formatTime` can read it).
    private static let localDateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return f
    }()

    // MARK: - Setup

    override func setup() {
        super.setup()
        setupTwoWayBinding()
        initializeValue()
    }

    /// Parse a date string (ISO8601 or yyyy-MM-dd)
    func parseDate(_ string: String) -> Date? {
        Self.iso8601.date(from: string) ?? Self.shortDate.date(from: string)
    }

    /// Format a date for storage in the bound variable.
    /// - `date` mode: `yyyy-MM-dd` (local calendar date).
    /// - `time` / `dateAndTime` / `countdownTimer`: ISO8601 local date-time with
    ///   offset (`yyyy-MM-dd'T'HH:mm:ssXXXXX`) so the time is not lost.
    func formatDate(_ date: Date) -> String {
        switch currentProperties.datePickerMode ?? .date {
        case .date:
            return Self.shortDate.string(from: date)
        case .time, .dateAndTime, .countdownTimer:
            return Self.localDateTime.string(from: date)
        }
    }

    private func initializeValue() {
        if let bindVar = currentProperties.bindVariable,
           let value = variableStore.getValue(name: bindVar) {
            if let str = value as? String, let date = parseDate(str) {
                currentDate = date
            }
        } else if let expr = currentProperties.selectedDate {
            let resolved = resolvePropertyToString(expr)
            if let date = parseDate(resolved) {
                currentDate = date
            }
        }
    }

    private func setupTwoWayBinding() {
        guard let bindVar = currentProperties.bindVariable else { return }

        // View -> Variable
        dateChanged
            .filter { [weak self] _ in !(self?.isUpdatingFromVariable ?? false) }
            .sink { [weak self] newDate in
                guard let self = self else { return }
                self.currentDate = newDate
                let dateStr = self.formatDate(newDate)
                try? self.variableStore.setValue(name: bindVar, value: dateStr)
            }
            .store(in: &cancellables)

        // Variable -> View
        variableStore.anyVariableChanged
            .filter { $0 == bindVar }
            .compactMap { [weak self] _ -> Date? in
                guard let self = self else { return nil }
                let value = self.variableStore.getValue(name: bindVar)
                if let str = value as? String { return self.parseDate(str) }
                return nil
            }
            .filter { [weak self] newDate in
                guard let self = self else { return false }
                return abs(newDate.timeIntervalSince(self.currentDate)) > 1
            }
            .sink { [weak self] date in
                guard let self = self else { return }
                self.isUpdatingFromVariable = true
                self.currentDate = date
                self.externalDateUpdate.send(date)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.isUpdatingFromVariable = false
                }
            }
            .store(in: &cancellables)
    }
}
