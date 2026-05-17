import Combine

/// Protocol for styles that can be merged with a base style
/// Uses Any to allow protocol-based dispatch without Self requirement issues
protocol MergeableStyle {
    /// Merge with base style, returning merged result or nil if types don't match
    func merging(withBase base: Any) -> Self?
}

/// Delegate protocol for state manager events
@MainActor
protocol ComponentStateManagerDelegate: AnyObject {
    func stateManagerDidRequestChildStates(
        _ childStates: [String: String],
        animated: Bool
    )
}

/// Manages component state transitions
@MainActor
final class ComponentStateManager<Content: DSL.Model.StatefulContent> {

    typealias State = Content.StateType

    // MARK: - State

    private let baseContent: Content
    private var currentStateName: String?

    // MARK: - Publishers

    private let currentStateSubject: CurrentValueSubject<String?, Never>
    private let effectiveStyleSubject: CurrentValueSubject<Content.Style?, Never>
    private let effectivePropertiesSubject: CurrentValueSubject<Content.Properties, Never>
    private let effectiveLayoutSubject: CurrentValueSubject<DSL.Model.Layout?, Never>
    private let animationSubject: CurrentValueSubject<DSL.Model.Animation?, Never>

    var currentState: AnyPublisher<String?, Never> {
        currentStateSubject.eraseToAnyPublisher()
    }

    var effectiveStyle: AnyPublisher<Content.Style?, Never> {
        effectiveStyleSubject.eraseToAnyPublisher()
    }

    var effectiveProperties: AnyPublisher<Content.Properties, Never> {
        effectivePropertiesSubject.eraseToAnyPublisher()
    }

    var effectiveLayout: AnyPublisher<DSL.Model.Layout?, Never> {
        effectiveLayoutSubject.eraseToAnyPublisher()
    }

    var animation: AnyPublisher<DSL.Model.Animation?, Never> {
        animationSubject.eraseToAnyPublisher()
    }

    // MARK: - Delegate

    weak var delegate: ComponentStateManagerDelegate?

    // MARK: - Init

    init(content: Content) {
        self.baseContent = content

        let initialState = content.defaultStateName
        self.currentStateName = initialState
        self.currentStateSubject = .init(initialState)
        self.effectiveStyleSubject = .init(content.style)
        self.effectivePropertiesSubject = .init(content.properties)
        self.effectiveLayoutSubject = .init(content.layout)
        self.animationSubject = .init(nil)

        if let initialState {
            applyState(named: initialState, animated: false)
        }
    }

    // MARK: - Public API

    /// Transition to a named state
    /// - Parameters:
    ///   - stateName: The state to transition to
    ///   - animated: Whether to animate the transition
    ///   - force: If true, re-applies the state even if it's the current state (needed for childStates propagation)
    func setState(_ stateName: String?, animated: Bool = true, force: Bool = false) {
        guard force || stateName != currentStateName else { return }
        currentStateName = stateName
        currentStateSubject.send(stateName)

        if let stateName {
            applyState(named: stateName, animated: animated)
        } else {
            resetToBase(animated: animated)
        }
    }

    /// Get current state name
    var currentStateNameValue: String? {
        currentStateName
    }

    /// Get current effective style
    var currentEffectiveStyle: Content.Style? {
        effectiveStyleSubject.value
    }

    /// Get current effective properties
    var currentEffectiveProperties: Content.Properties {
        effectivePropertiesSubject.value
    }

    /// Get current effective layout
    var currentEffectiveLayout: DSL.Model.Layout? {
        effectiveLayoutSubject.value
    }

    // MARK: - Private

    private func applyState(named stateName: String, animated: Bool) {
        guard let states = baseContent.states,
              let state = states[stateName] else {
            resetToBase(animated: animated)
            return
        }

        // Publish animation config first so views can use it.
        if animated {
            animationSubject.send(state.animation)
        } else {
            animationSubject.send(nil)
        }

        let effectiveStyle = mergeStyles(state: state.style, base: baseContent.style)
        effectiveStyleSubject.send(effectiveStyle)

        // When nil (missing from JSON or explicitly null), base properties persist.
        if let stateProperties = state.properties {
            effectivePropertiesSubject.send(stateProperties)
        }

        if let layout = state.layout {
            effectiveLayoutSubject.send(layout)
        }

        if let childStates = state.childStates {
            delegate?.stateManagerDidRequestChildStates(childStates, animated: animated)
        }
    }

    private func resetToBase(animated: Bool) {
        if animated {
            animationSubject.send(.default)
        } else {
            animationSubject.send(nil)
        }
        effectiveStyleSubject.send(baseContent.style)
        effectivePropertiesSubject.send(baseContent.properties)
        effectiveLayoutSubject.send(baseContent.layout)
    }

    /// Merge state style with base style if the style type supports merging
    private func mergeStyles(state: Content.Style?, base: Content.Style?) -> Content.Style? {
        guard let state else { return base }
        guard let base else { return state }
        if let mergeableState = state as? any MergeableStyle,
           let merged = mergeableState.merging(withBase: base) as? Content.Style {
            return merged
        }
        return state
    }
}
