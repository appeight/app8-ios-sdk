import UIKit

extension ScreenViewController {
    /// iOS 26+: the navigation bar has no background of its own. Content
    /// scrolls under it and the scroll view draws the scroll-edge effect for
    /// the bar, but only for the scroll view the bar tracks. UIKit finds it
    /// by itself only near the top of the view hierarchy, and a DSL page sits
    /// several containers deep, so name the screen's main vertical scroll
    /// view explicitly, as large titles already need.
    var tracksScrollEdgeForBar: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    /// The system style for `navigationBar.topEdgeEffect`, one to one; nil
    /// for `hidden`, which hides the effect instead.
    @available(iOS 26.0, *)
    static func systemTopEdgeStyle(_ effect: DSL.Model.NavigationBar.EdgeEffect) -> UIScrollEdgeEffect.Style? {
        switch effect {
        case .automatic: return .automatic
        case .soft: return .soft
        case .hard: return .hard
        case .hidden: return nil
        }
    }
}
