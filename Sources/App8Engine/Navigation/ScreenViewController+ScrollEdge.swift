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

    /// `navigationBar.topEdgeEffect`, with `automatic` (and no value) as
    /// `soft` on iOS 26+: the progressive blur of the system bars. Left to
    /// UIKit, a DSL page resolves to the hard style, a solid band with a
    /// sharp lower edge across the top of the screen.
    static func resolvedTopEdgeEffect(_ authored: DSL.Model.NavigationBar.EdgeEffect?) -> DSL.Model.NavigationBar.EdgeEffect {
        let effect = authored ?? .automatic
        guard effect == .automatic else { return effect }
        if #available(iOS 26.0, *) { return .soft }
        return .automatic
    }
}
