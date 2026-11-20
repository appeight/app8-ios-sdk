import UIKit

extension DSL.Model {

    public struct App: Decodable {
        /// App id. Names persisted-variable storage (`app8.<id>`).
        let id: String?
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
        /// App-scope variables, visible from every screen (`component → screen →
        /// app` lookup). They live as long as the app instance: a cart, a session.
        let variables: [String: VariableDefinition]?

        /// Storage namespace for `persist: true` variables and stored photos:
        /// the host's id (`App8DataSource.persistenceId`), else `id`, else
        /// `bundleId`, else `title`, else the host app's bundle identifier.
        /// The title keeps two apps without ids in one host apart.
        var persistenceId: String { persistenceId(hostId: nil) }

        func persistenceId(hostId: String?) -> String {
            for candidate in [hostId, id, bundleId, title, Bundle.main.bundleIdentifier] {
                if let c = candidate?.trimmingCharacters(in: .whitespaces), !c.isEmpty { return c }
            }
            return "default"
        }

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
