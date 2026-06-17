import UIKit

extension DSL.Model.Style {

    /// Native `UIButton.Configuration` styling for a `button` component.
    ///
    /// When a button's `style` carries a `system` block, the button is rendered
    /// via `UIButton.Configuration` instead of the Material path: the system owns
    /// the background, corner shape, content insets, image+title layout, and the
    /// highlighted/disabled/selected appearance. This gives builders the real
    /// system look (filled / tinted / bordered, the iOS 26 glassy capsule, …)
    /// without rebuilding system chrome out of primitives.
    struct SystemButton: Decodable, StylePointerResolvable {
        typealias Entity = ConcreteEntity<Self>

        let variant: Variant?
        let cornerStyle: CornerStyle?
        let size: Size?
        let role: Role?

        /// Overall tint — drives `baseBackgroundColor` (and the button's `tintColor`).
        @Wrapped var tint: Color.Themed?
        /// Title/image colour — drives `baseForegroundColor`.
        @Wrapped var foreground: Color.Themed?

        let image: Image?
        let imagePlacement: ImagePlacement?
        let imagePadding: CGFloat?

        /// Optional secondary line. Resolved for `{{expressions}}` at the view layer.
        let subtitle: String?
        /// Expression resolving to a Bool. Resolved at the view layer.
        let showsActivityIndicator: String?

        // MARK: Enums

        enum Variant: String, SafeEnumCodable {
            case plain, gray, tinted, filled, bordered, borderedTinted, borderedProminent
            // iOS 26 — degrade gracefully below 26 (see `baseConfiguration`).
            case glass, prominentGlass
            static var unknownCase: Self { .filled }
        }

        enum CornerStyle: String, SafeEnumCodable {
            case dynamic, fixed, capsule, large, medium, small
            static var unknownCase: Self { .dynamic }
            var ui: UIButton.Configuration.CornerStyle {
                switch self {
                case .dynamic: return .dynamic
                case .fixed:   return .fixed
                case .capsule: return .capsule
                case .large:   return .large
                case .medium:  return .medium
                case .small:   return .small
                }
            }
        }

        enum Size: String, SafeEnumCodable {
            case mini, small, medium, large
            static var unknownCase: Self { .medium }
            var ui: UIButton.Configuration.Size {
                switch self {
                case .mini:   return .mini
                case .small:  return .small
                case .medium: return .medium
                case .large:  return .large
                }
            }
        }

        enum Role: String, SafeEnumCodable {
            case normal, primary, cancel, destructive
            static var unknownCase: Self { .normal }
        }

        enum ImagePlacement: String, SafeEnumCodable {
            case leading, trailing, top, bottom
            static var unknownCase: Self { .leading }
            var ui: NSDirectionalRectEdge {
                switch self {
                case .leading:  return .leading
                case .trailing: return .trailing
                case .top:      return .top
                case .bottom:   return .bottom
                }
            }
        }

        /// SF Symbol or asset-catalog image, decoded like the `icon` component's source.
        struct Image: Decodable {
            enum Kind: String, SafeEnumCodable {
                case symbol, asset
                static var unknownCase: Self { .symbol }
            }
            let type: Kind
            let name: String

            /// Builds the `UIImage` (SF Symbol or asset). SF Symbols use the
            /// monochrome/template default so the button's foreground tint applies.
            func resolved() -> UIImage? {
                switch type {
                case .symbol: return UIImage(systemName: name)
                case .asset:  return UIImage(named: name)
                }
            }
        }

        // MARK: Configuration

        /// Builds the base `UIButton.Configuration` from `variant`/`cornerStyle`/
        /// `size`/colours/image placement. Title, subtitle, the resolved image, and
        /// the activity-indicator flag are applied at the view layer (they depend on
        /// runtime property/expression resolution).
        func makeConfiguration() -> UIButton.Configuration {
            var config = baseConfiguration()
            if let cornerStyle { config.cornerStyle = cornerStyle.ui }
            if let size { config.buttonSize = size.ui }
            if let bg = tint?.ui { config.baseBackgroundColor = bg }
            if let fg = foreground?.ui { config.baseForegroundColor = fg }
            if let imagePlacement { config.imagePlacement = imagePlacement.ui }
            if let imagePadding { config.imagePadding = imagePadding }
            return config
        }

        private func baseConfiguration() -> UIButton.Configuration {
            switch variant ?? .filled {
            case .plain:             return .plain()
            case .gray:              return .gray()
            case .tinted:            return .tinted()
            case .filled:            return .filled()
            case .bordered:          return .bordered()
            case .borderedTinted:    return .borderedTinted()
            case .borderedProminent: return .borderedProminent()
            case .glass:
                if #available(iOS 26.0, *) { return .glass() }
                return .filled()
            case .prominentGlass:
                if #available(iOS 26.0, *) { return .prominentGlass() }
                return .borderedProminent()
            }
        }

        /// `UIButton.role`, gated to iOS 26 where the API is available.
        @available(iOS 26.0, *)
        var uiRole: UIButton.Role? {
            switch role {
            case .none, .some(.normal): return UIButton.Role.normal
            case .some(.primary):       return .primary
            case .some(.cancel):        return .cancel
            case .some(.destructive):   return .destructive
            }
        }

        // MARK: StylePointerResolvable

        mutating func resolveStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {
            _tint.resolvePointer(type: .key(.color), resolver: resolver)
            _foreground.resolvePointer(type: .key(.color), resolver: resolver)
        }

        func isResolved() -> Bool {
            // An unresolved `@Wrapped` pointer yields a nil `wrappedValue`, so check the
            // pending pointer ids directly rather than the unwrapped optionals.
            unresolvedPointerIds().isEmpty
        }

        func unresolvedPointerIds() -> [String] {
            _tint.unresolvedPointerIds() + _foreground.unresolvedPointerIds()
        }
    }
}
