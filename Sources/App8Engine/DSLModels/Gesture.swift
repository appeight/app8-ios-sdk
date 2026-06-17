import Foundation

extension DSL.Model {

    /// Continuous interaction → variable bindings, declared per component under
    /// `content.gestures`. This is deliberately separate from `content.actions`:
    /// `actions` map a *discrete* recognition (a tap) to an imperative `Action`;
    /// `gestures` stream a *continuous* recognizer's raw quantities into screen
    /// variables, the same way `scrollOffsetVariable` streams a scroll offset.
    ///
    /// Each binding value is a **bare variable name** (no `{{ }}`) — the engine
    /// writes to it as the gesture updates. The gesture emits only raw,
    /// geometry-free quantities; turning them into a "progress" / mapped value
    /// is an author concern, expressed with an expression at the component level
    /// (e.g. a fill `height` of `{{ locY / view.height * 100 }}`).
    ///
    /// Future recognizers (pinch / swipe / rotate) slot in here as additional
    /// optional members alongside `pan`.
    struct Gestures: Decodable, Sendable {
        let pan: Pan?

        /// A pan (drag) recognizer. Every field is optional; only the named
        /// bindings are written. Values are written in the gesture view's own
        /// coordinate space.
        struct Pan: Decodable, Sendable {
            /// Cumulative translation since the drag began, in points.
            let translationX: String?
            let translationY: String?
            /// Current drag velocity, in points / second.
            let velocityX: String?
            let velocityY: String?
            /// Touch location within the view's bounds, in points.
            let locationX: String?
            let locationY: String?

            /// True when at least one binding is declared (else there's no
            /// reason to install a recognizer).
            var hasBindings: Bool {
                translationX != nil || translationY != nil
                    || velocityX != nil || velocityY != nil
                    || locationX != nil || locationY != nil
            }
        }
    }
}
