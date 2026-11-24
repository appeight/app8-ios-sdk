import UIKit

extension DSL.Model.Component {

    struct PageControl {
        typealias C = Content<PageControl.Properties, DSL.Model.Style.PageControl>
        typealias Entity = ConcreteEntity<C>

        struct Properties: Decodable, Sendable {
            /// Number of pages. Supports expressions: "{{totalPhotos}}"
            let numberOfPages: String?
            /// Current page index. Supports expressions: "{{currentIndex}}"
            let currentPage: String?
            /// Variable name for two-way binding
            let bindVariable: String?
            /// Whether to hide when there is only one page. Default: true
            let hidesForSinglePage: Bool?
            /// Look of the capsule and dots (`automatic`, `light`, `dark`).
            /// Missing or unknown: `automatic`. Since 0.7.16.
            let style: Look

            private enum CodingKeys: String, CodingKey {
                case numberOfPages, currentPage, bindVariable, hidesForSinglePage, style
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                numberOfPages = try c.decodeScalarOrExpressionIfPresent(forKey: .numberOfPages)
                currentPage = try c.decodeScalarOrExpressionIfPresent(forKey: .currentPage)
                bindVariable = try c.decodeIfPresent(String.self, forKey: .bindVariable)
                hidesForSinglePage = try c.decodeIfPresent(Bool.self, forKey: .hidesForSinglePage)
                style = Look(rawValue: (try? c.decodeIfPresent(String.self, forKey: .style)) ?? "") ?? .automatic
            }
        }

        /// `properties.style` (page-control.md, "Style"): the capsule and the
        /// default dot colors. `light`: a light material with dark dots;
        /// `dark`: a dark material with light dots; `automatic` (the default):
        /// light or dark by the interface style the control renders in, which
        /// is the screen's `userInterfaceStyle`, else the app's
        /// (`defaultUserInterfaceStyle` / the host override), else the device's.
        enum Look: String, Sendable, Equatable {
            case automatic, light, dark

            /// Whether the control draws dark (dark capsule, light dots) under
            /// the interface style `trait`. `.unspecified` reads as light.
            func isDark(for trait: UIUserInterfaceStyle) -> Bool {
                switch self {
                case .light: return false
                case .dark: return true
                case .automatic: return trait == .dark
                }
            }
        }
    }
}
