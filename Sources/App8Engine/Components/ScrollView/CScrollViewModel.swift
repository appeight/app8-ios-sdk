//
//  CScrollViewModel.swift
//  App8Engine
//

import UIKit

extension DSL.Model.Component {

    struct ScrollView {
        typealias C = Content<ScrollView.Properties, DSL.Model.Style.ScrollView>
        typealias Entity = ConcreteEntity<C>

        struct Properties: Decodable {
            let direction: Direction?
            let showsIndicator: Bool?
            let outputVariable: String?  // Variable name to write scroll offset to
            let scrollThreshold: CGFloat?  // Offset to fire onScrollThreshold action (with $crossed overlay)
            let contentInset: DSL.Model.EdgeInsets?
            let contentInsetAdjustment: ContentInsetAdjustment?
            /// Optional auto-scroll (marquee/ticker) behavior.
            /// When set, the engine drives `contentOffset` on every display frame
            /// using a `CADisplayLink`. With `infinite: true` the rendered content
            /// is duplicated via a snapshot so the loop wraps seamlessly.
            let autoScroll: AutoScroll?

            enum Direction: String, Decodable {
                case vertical, horizontal
            }

            /// Controls UIScrollView.contentInsetAdjustmentBehavior.
            /// Default is `automatic` — matches UIKit default, iOS adjusts insets for safe areas.
            /// Use `never` when the DSL controls all layout (e.g., full-screen scroll with hidden nav bar).
            enum ContentInsetAdjustment: String, Decodable {
                case never
                case automatic
            }

            /// Auto-scroll / marquee configuration.
            ///
            /// Example DSL:
            /// ```json
            /// "autoScroll": { "speed": 30, "infinite": true, "loopGap": 30 }
            /// ```
            ///
            /// - `speed`: points per second on the active scroll axis. Positive
            ///   values scroll towards the trailing edge (right for horizontal,
            ///   down for vertical). Negative values reverse.
            /// - `infinite`: when true (default), the engine duplicates the
            ///   rendered content once and places the duplicate adjacent to
            ///   the original so wrapping the offset modulo the cycle length
            ///   produces a seamless loop. When false, scrolling stops at the
            ///   trailing edge (one-shot).
            /// - `loopGap`: gap (in points, on the scroll axis) inserted
            ///   between the original content and the duplicate. Use this to
            ///   preserve the same inter-item spacing across the wrap point —
            ///   e.g. if your row's stack spacing is 30, set `loopGap: 30`
            ///   so the gap between the last item and the first item of the
            ///   loop matches every other gap. Defaults to 0 (touching).
            struct AutoScroll: Decodable {
                let speed: CGFloat
                let infinite: Bool?
                let loopGap: CGFloat?
            }
        }
    }
}
