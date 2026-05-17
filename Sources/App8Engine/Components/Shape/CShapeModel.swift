//
//  CShapeModel.swift
//  App8Engine
//

import Foundation

extension DSL.Model.Component {

    struct Shape {

        typealias Entity = ConcreteEntity<C>
        typealias C = Content<Shape.Properties, DSL.Model.Style.View>

        enum Kind: String, Decodable, Sendable {
            case arc, bar, circle, line, polyline
        }

        /// A point for polyline shapes. Coordinates can be literal or expressions.
        struct Point: Decodable, Sendable {
            /// X coordinate: 0..1 normalized to bounds, or >1 for absolute points
            let x: String
            /// Y coordinate: 0..1 normalized to bounds, or >1 for absolute points
            let y: String
        }

        enum LineCap: String, Decodable, Sendable {
            case round, butt, square
        }
    }
}

// MARK: - Properties

extension DSL.Model.Component.Shape {

    struct Properties: Decodable, Sendable {
        let kind: Kind

        /// Progress value: literal "0.75" or expression "{{progressVar}}", maps 0.0–1.0.
        /// Accepts the bare expression form or the wrapped `{ value, animation }`
        /// form. When wrapped with an `animation`, the descriptor takes precedence
        /// over the legacy `animationDuration` / `animationCurve` siblings below.
        let progress: DSL.Model.AnimatedValue<String>?

        /// Arc start angle in degrees. -90 = 12 o'clock (top). Default: -90
        let startAngle: Double?

        /// Stroke width in points. Default: 8
        let lineWidth: Double?

        /// Line cap style. Default: .round
        let lineCap: LineCap?

        /// Hex color string for the progress arc, e.g. "#FF2D55"
        let strokeColor: String?

        /// Hex color string for the background track ring, e.g. "#FF2D5533"
        let trackColor: String?

        /// Track stroke width. Defaults to lineWidth if not set
        let trackLineWidth: Double?

        /// Animation duration in seconds for progress changes. Default: 0.4
        let animationDuration: Double?

        /// Timing curve: "linear" | "easeIn" | "easeOut" | "easeInOut". Default: "easeOut"
        let animationCurve: String?

        /// Hex fill color for circle kind (solid fill inside the circle path)
        let fillColor: String?

        // MARK: - Polyline properties

        /// Array of points for polyline kind
        let points: [DSL.Model.Component.Shape.Point]?
        /// Whether to use smooth Catmull-Rom interpolation between points
        let smooth: Bool?
        /// Whether to close the polyline path
        let closed: Bool?
    }
}
