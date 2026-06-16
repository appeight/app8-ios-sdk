import UIKit

extension DSL.Model {

    public struct App: Decodable {
        let title: String?
        let bundleId: String?
        let defaultUserInterfaceStyle: UserInterfaceStyle?
        let navigation: Navigation?
        /// Reusable animation registry. Each entry is a wrapped or flat
        /// `Animation` (no pointer-only entries here — those would self-reference).
        let animations: [Animation]?
        /// Reusable screen-transition registry. Mirrors `animations`: each entry
        /// is a wrapped or flat `ScreenTransition`, referenced elsewhere by
        /// `{ "id": "..." }` pointer.
        let transitions: [ScreenTransition]?
        /// App-wide default transition. Lowest-priority fallback when neither the
        /// navigation action nor the target screen declares one.
        let defaultTransition: ScreenTransition?

        var initialScreenId: String? {
            guard let navigation else { return nil }
            return navigation.flows.first(where: { $0.id == navigation.startFlow })?.startScreen
        }

        enum UserInterfaceStyle: String, Decodable, SafeEnumCodable {
            case light, dark
            static var unknownCase: Self { .light }
            var ui: UIUserInterfaceStyle {
                switch self {
                case .light:
                    return .light
                case .dark:
                    return .dark
                }
            }
        }
    }
}

extension DSL.Model.App {

    struct Navigation: Decodable {
        let startFlow: String
        @SafeArrayDecodable
        var flows: [Flow]

        struct Flow: Decodable {
            let id: String
            let startScreen: String
        }
    }
}
