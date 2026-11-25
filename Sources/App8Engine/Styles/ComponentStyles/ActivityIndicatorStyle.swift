import UIKit

extension DSL.Model.Style {

    struct ActivityIndicator: Decodable, BaseStyleProtocol, StylePointerResolvable {
        let contentMode: View.ContentMode?
        @Wrapped var material: Material?
        @Alpha var alpha: CGFloat?
        let transform: View.Transform?

        /// "medium" or "large". Default: "medium"
        let indicatorStyle: IndicatorStyle?
        /// Tint color for the spinner
        let color: String?

        enum IndicatorStyle: String, Decodable, Sendable {
            case medium, large

            var ui: UIActivityIndicatorView.Style {
                switch self {
                case .medium: return .medium
                case .large: return .large
                }
            }
        }

        mutating func resolveStylePointers(resolver: (String) -> (any Entity)?) {
            _material.resolvePointer(type: .key(.material), resolver: resolver)
        }

        func isResolved() -> Bool {
            material?.isResolved() ?? true
        }
    }
}

extension DSL.Model.Style.ActivityIndicator: DSL.Model.Style.AlphaExpressionHolder {
    var alphaSlot: DSL.Model.Style.Alpha {
        get { _alpha }
        set { _alpha = newValue }
    }
}
