import UIKit
import Combine

/// Protocol for views that can receive focus (text inputs).
@MainActor
protocol Focusable: UIView {
    var focusableId: String? { get }
    func requestFocus()
    func resignFocus()
}

/// Service for managing focus across text input components.
@MainActor
final class FocusManager {

    /// Optional logger injected by the owning context. Nil during tests that
    /// construct FocusManager directly without an App8Context.
    weak var logger: A8Log?

    private var focusables: [String: Weak<UIView>] = [:]

    /// Order of focusable component IDs, for tab navigation.
    private var focusOrder: [String] = []

    private(set) var currentFocusId: String?

    private let focusChangeSubject = PassthroughSubject<String?, Never>()
    var focusChange: AnyPublisher<String?, Never> {
        focusChangeSubject.eraseToAnyPublisher()
    }

    init() {}

    // MARK: - Registration

    func register(id: String, view: UIView) {
        focusables[id] = Weak(view)
        if !focusOrder.contains(id) {
            focusOrder.append(id)
        }
    }

    func unregister(id: String) {
        focusables.removeValue(forKey: id)
        focusOrder.removeAll { $0 == id }
        if currentFocusId == id {
            currentFocusId = nil
        }
    }

    func clearAll() {
        focusables.removeAll()
        focusOrder.removeAll()
        currentFocusId = nil
    }

    // MARK: - Focus Actions

    func focus(id: String) {
        guard let weakRef = focusables[id], let view = weakRef.value else {
            logger?.warning("View not found for id: \(id)")
            return
        }

        if let focusable = view as? Focusable {
            focusable.requestFocus()
        } else {
            view.becomeFirstResponder()
        }

        currentFocusId = id
        focusChangeSubject.send(id)
    }

    func focusNext() {
        guard let currentId = currentFocusId,
              let currentIndex = focusOrder.firstIndex(of: currentId) else {
            if let firstId = focusOrder.first {
                focus(id: firstId)
            }
            return
        }

        let nextIndex = currentIndex + 1
        if nextIndex < focusOrder.count {
            focus(id: focusOrder[nextIndex])
        } else {
            dismissKeyboard()
        }
    }

    func focusPrevious() {
        guard let currentId = currentFocusId,
              let currentIndex = focusOrder.firstIndex(of: currentId) else {
            if let lastId = focusOrder.last {
                focus(id: lastId)
            }
            return
        }

        let previousIndex = currentIndex - 1
        if previousIndex >= 0 {
            focus(id: focusOrder[previousIndex])
        }
    }

    func dismissKeyboard() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
            window.endEditing(true)
        }

        currentFocusId = nil
        focusChangeSubject.send(nil)
    }

    /// Called by views when they become/resign first responder.
    func didFocus(id: String?) {
        currentFocusId = id
        focusChangeSubject.send(id)
    }

    /// Remove dead weak references.
    func cleanUp() {
        focusables = focusables.filter { $0.value.value != nil }
        focusOrder = focusOrder.filter { focusables[$0]?.value != nil }
    }

    /// Reset manager state (for testing only).
    func reset() {
        focusables.removeAll()
        focusOrder.removeAll()
        currentFocusId = nil
    }

    /// Current focus order (for testing).
    var registeredIds: [String] {
        focusOrder
    }
}

private final class Weak<T: AnyObject> {
    weak var value: T?
    init(_ value: T) {
        self.value = value
    }
}
