import Foundation
import UIKit

/// Per-instance container for engine services. Owned by the `App8.Instance` impl and
/// threaded through internal types via init parameters.
@MainActor
final class App8Context {
    let logger: A8Log
    let appearance: App8Appearance
    let layoutMode: App8LayoutMode
    let focusManager: FocusManager
    let keyboardService: KeyboardHeightServiceProtocol
    let translationStore: TranslationStore

    /// In-process bus for host-facing action events (`.emit` actions).
    let eventBus: App8EventBus

    /// In-process bus for analytics events (author-declared + auto-fired).
    let analyticsBus: App8AnalyticsBus

    /// Per-instance analytics configuration. Mutating this affects
    /// subsequently-fired auto events; in-flight events are unaffected.
    var analyticsConfig: App8AnalyticsConfig = App8AnalyticsConfig()

    /// Names that have already triggered a once-per-instance warning at the
    /// analytics emit site. Covers both author-event-name collisions (an
    /// author binding whose name matches a reserved auto-event) and
    /// author-property-key collisions (a binding whose `properties` writes a
    /// key in `App8AnalyticsEvent.canonicalKeys`). Read/written from
    /// `CBaseViewModel`'s `fireTriggerAnalytics` / `fireRowTapAnalytics` —
    /// the bus stays a dumb pipe and never touches this set.
    var warnedNames: Set<String> = []

    /// App-wide default screen transition (resolved inline form). Lowest-priority
    /// fallback applied by the navigation containers. Set during app load.
    var appDefaultTransition: DSL.Model.ScreenTransition.Inline?

    /// Resolves animation pointers when expanding a transition to its concrete
    /// form at navigation time. Set during app load from the animation registry.
    var animationResolver: ((String) -> DSL.Model.Animation.Inline?)?

    init(
        logger: A8Log = A8Log(),
        appearance: App8Appearance = App8Appearance(),
        layoutMode: App8LayoutMode = App8LayoutMode(),
        focusManager: FocusManager = FocusManager(),
        keyboardService: KeyboardHeightServiceProtocol = KeyboardHeightService(),
        translationStore: TranslationStore = TranslationStore(),
        eventBus: App8EventBus = App8EventBus(),
        analyticsBus: App8AnalyticsBus = App8AnalyticsBus()
    ) {
        self.logger = logger
        self.appearance = appearance
        self.layoutMode = layoutMode
        self.focusManager = focusManager
        self.keyboardService = keyboardService
        self.translationStore = translationStore
        self.eventBus = eventBus
        self.analyticsBus = analyticsBus
        focusManager.logger = logger
    }
}

extension CodingUserInfoKey {
    /// Inject the context's logger into a `JSONDecoder` via `userInfo` so decode-time
    /// helpers (FailableDecodable, SafeArrayCodable, ColorHex) can log without holding
    /// a context reference. Absent → no-op (safe for tests that decode raw fixtures).
    static let app8Logger = CodingUserInfoKey(rawValue: "dev.app8.engine.logger")!

    /// Inject an animation pointer resolver. When a screen references a named
    /// animation by `{ "id": "..." }`, the engine sets a closure here so
    /// `DSL.Model.Animation.init(from:)` can replace the pointer with the
    /// resolved inline form during decode. Absent → pointer is preserved as
    /// `.pointer(id)` (instantaneous at runtime + warning).
    /// Stored value type: `(String) -> DSL.Model.Animation.Inline?`.
    static let app8AnimationResolver = CodingUserInfoKey(rawValue: "dev.app8.engine.animationResolver")!

    /// Inject a transition pointer resolver. When an action/screen references a
    /// named transition by `{ "id": "..." }`, the engine sets a closure here so
    /// `DSL.Model.ScreenTransition.init(from:)` can replace the pointer with the
    /// resolved inline form during decode. Absent → pointer is preserved as
    /// `.pointer(id)` (falls back to the native transition at runtime).
    /// Stored value type: `(String) -> DSL.Model.ScreenTransition.Inline?`.
    static let app8TransitionResolver = CodingUserInfoKey(rawValue: "dev.app8.engine.transitionResolver")!
}
