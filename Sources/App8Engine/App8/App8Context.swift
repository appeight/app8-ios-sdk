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

    init(
        logger: A8Log = A8Log(),
        appearance: App8Appearance = App8Appearance(),
        layoutMode: App8LayoutMode = App8LayoutMode(),
        focusManager: FocusManager = FocusManager(),
        keyboardService: KeyboardHeightServiceProtocol = KeyboardHeightService(),
        translationStore: TranslationStore = TranslationStore()
    ) {
        self.logger = logger
        self.appearance = appearance
        self.layoutMode = layoutMode
        self.focusManager = focusManager
        self.keyboardService = keyboardService
        self.translationStore = translationStore
        focusManager.logger = logger
    }
}

extension CodingUserInfoKey {
    /// Inject the context's logger into a `JSONDecoder` via `userInfo` so decode-time
    /// helpers (FailableDecodable, SafeArrayCodable, ColorHex) can log without holding
    /// a context reference. Absent → no-op (safe for tests that decode raw fixtures).
    static let app8Logger = CodingUserInfoKey(rawValue: "com.app8.engine.logger")!

    /// Inject an animation pointer resolver. When a screen references a named
    /// animation by `{ "id": "..." }`, the engine sets a closure here so
    /// `DSL.Model.Animation.init(from:)` can replace the pointer with the
    /// resolved inline form during decode. Absent → pointer is preserved as
    /// `.pointer(id)` (instantaneous at runtime + warning).
    /// Stored value type: `(String) -> DSL.Model.Animation.Inline?`.
    static let app8AnimationResolver = CodingUserInfoKey(rawValue: "com.app8.engine.animationResolver")!
}
