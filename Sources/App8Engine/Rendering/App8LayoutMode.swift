import UIKit

/// Toggle layout inspection mode. When enabled, all components render as
/// semi-transparent black boxes — content, text, and styling are suppressed.
/// Useful for verifying layout structure before filling in real content.
@MainActor
public final class App8LayoutMode {
    public init() {}

    public var isEnabled: Bool = false

    public var showLabels: Bool = true {
        didSet {
            guard oldValue != showLabels, isEnabled else { return }
            let visible = showLabels
            let roots = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .compactMap { $0.rootViewController?.view }
            roots.forEach { updateCornerLabels(in: $0, visible: visible) }
        }
    }

    private func updateCornerLabels(in view: UIView, visible: Bool) {
        for tag in [8_001_001, 8_001_002] {
            view.viewWithTag(tag)?.isHidden = !visible
        }
        for subview in view.subviews {
            updateCornerLabels(in: subview, visible: visible)
        }
    }
}
