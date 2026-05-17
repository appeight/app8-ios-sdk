import UIKit

extension DSL.Model.Style {

    struct Gradient: Decodable, StylePointerResolvable {
        /// Points are relative (0...1) to the layer bounds.
        fileprivate(set) var start: Vertex
        fileprivate(set) var end: Vertex
        @SafeArrayDecodable
        fileprivate(set) var middlePoints: [MiddlePoint]

        struct Vertex: Decodable, StylePointerResolvable {
            fileprivate(set) var x, y: CGFloat
            @Wrapped var color: Color.Themed?

            func isResolved() -> Bool {
                color?.isResolved() ?? false
            }

            mutating func resolveStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {
                _color.resolvePointer(type: .key(.color), resolver: resolver)
            }

            func unresolvedPointerIds() -> [String] {
                _color.unresolvedPointerIds()
            }
        }

        struct MiddlePoint: Decodable, StylePointerResolvable {
            fileprivate(set) var position: CGFloat
            @Wrapped var color: Color.Themed?

            func isResolved() -> Bool {
                color?.isResolved() ?? false
            }

            mutating func resolveStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {
                _color.resolvePointer(type: .key(.color), resolver: resolver)
            }

            func unresolvedPointerIds() -> [String] {
                _color.unresolvedPointerIds()
            }
        }

        func isResolved() -> Bool {
            var conditions: [Bool] = [
                start.isResolved(),
                end.isResolved()
            ]
            conditions.append(contentsOf: middlePoints.map { $0.isResolved() })
            return conditions.allSatisfy { $0 }
        }
        
        mutating func resolveStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {
            start.resolveStylePointers(resolver: resolver)
            end.resolveStylePointers(resolver: resolver)
            for i in 0 ..< middlePoints.count {
                middlePoints[i].resolveStylePointers(resolver: resolver)
            }
        }

        func unresolvedPointerIds() -> [String] {
            start.unresolvedPointerIds() + end.unresolvedPointerIds() + middlePoints.flatMap { $0.unresolvedPointerIds() }
        }
    }
}

// MARK: - Gradient

extension DSL.Model.Style.Gradient {

    var colorsList: [UIColor] {
        var allColors: [UIColor] = [ start.color?.ui ].compactMap { $0 }
        allColors.append(contentsOf: middlePoints.map { $0.color?.ui ?? .clear })
        allColors.append(end.color?.ui ?? .clear)
        return allColors
    }
    
    var locationsList: [CGFloat] {
        var locations: [CGFloat] = [0]
        locations.append(contentsOf: middlePoints.map(\.position))
        locations.append(1)
        return locations
    }
    
    init() {
        self.start = Vertex()
        self.end = Vertex()
        self.middlePoints = []
    }
    
    func start(with vertex: Vertex.RelativePoint, _ color: UIColor, alpha: CGFloat? = nil) -> Self {
        var config = self
        var color = color
        if let alpha = alpha {
            color = color.withAlphaComponent(alpha)
        }
        config.start = Vertex(relativePoint: vertex, color: color)
        return config
    }
    
    func add(_ position: MiddlePoint.RelativePosition, _ color: UIColor, alpha: CGFloat? = nil) -> Self {
        var config = self
        var color = color
        if let alpha = alpha {
            color = color.withAlphaComponent(alpha)
        }
        config.middlePoints.append(MiddlePoint(position: position.relativeValue(), color: color))
        return config
    }
    
    func end(with vertex: Vertex.RelativePoint, _ color: UIColor, alpha: CGFloat? = nil) -> Self {
        var config = self
        var color = color
        if let alpha = alpha {
            color = color.withAlphaComponent(alpha)
        }
        config.end = Vertex(relativePoint: vertex, color: color)
        return config
    }
    
    var debugDescription: String {
        let startDesc = "Start: \(start.relativePoint) - \((start.color?.ui.debugHexString) ?? "nil color")"
        let endDesc = "End: \(end.relativePoint) - \((end.color?.ui.debugHexString) ?? "nil color")"
        let middleDesc = middlePoints.map { "Middle: \($0.position) - \(($0.color?.ui.debugHexString) ?? "nil color")" }.joined(separator: ", ")
        return "Gradient Style:\n\(startDesc)\n\(middleDesc)\n\(endDesc)"
    }
}

// MARK: - Vertex

extension DSL.Model.Style.Gradient.Vertex {

    private typealias Style = DSL.Model.Style

    var relativePoint: CGPoint {
        CGPoint(x: x, y: y)
    }

    init() {
        self.x = .zero
        self.y = .zero
        self._color = .init(base: .init(Style.ConcreteEntity<Style.Color.Themed>(.init(id: "", type: .key(.color), typeSpecified: true), content: Style.Color.Themed(.clear))))
    }
    
    init(relativePoint: CGPoint, color: UIColor) {
        self.x = relativePoint.x
        self.y = relativePoint.y
        self._color = .init(base: .init(Style.ConcreteEntity<Style.Color.Themed>(.init(id: "", type: .key(.color), typeSpecified: true), content: Style.Color.Themed(color))))
    }
    
    init(relativePoint: RelativePoint, color: UIColor) {
        self.init(relativePoint: relativePoint.cgPoint, color: color)
    }
    
    /// Convenience way to setup gradient relative points
    enum RelativePoint {
        case left
        case right
        case leftTop
        case rightBottom
        case rightTop
        case leftBottom
        case relativePoint(CGFloat, CGFloat)

        var cgPoint: CGPoint {
            switch self {
            case .left, .leftTop:
                return .zero
            case .right, .rightTop:
                return CGPoint(x: 1, y: 0)
            case .rightBottom:
                return CGPoint(x: 1, y: 1)
            case .leftBottom:
                return CGPoint(x: 0, y: 1)
            case .relativePoint(let x, let y):
                return CGPoint(x: x, y: y)
            }
        }
    }
    
    func colored(_ color: UIColor) -> Self {
        var vertex = self
        vertex._color = .init(base: .init(Style.ConcreteEntity<Style.Color.Themed>(.init(id: "", type: .key(.color), typeSpecified: true), content: Style.Color.Themed(color))))
        return vertex
    }
    
    func pointed(point: CGPoint) -> Self {
        var vertex = self
        vertex.x = point.x
        vertex.y = point.y
        return vertex
    }
    
    func pointed(_ point: RelativePoint) -> Self {
        return pointed(point: point.cgPoint)
    }
}

// MARK: - MiddlePoint

extension DSL.Model.Style.Gradient.MiddlePoint {

    private typealias Style = DSL.Model.Style

    init(position: CGFloat, color: UIColor) {
        self.position = position
        _color = .init(base: .init(Style.ConcreteEntity<Style.Color.Themed>(.init(id: "", type: .key(.color), typeSpecified: true), content: Style.Color.Themed(color))))
    }

    enum RelativePosition {
        case start, middle, end
        case relativePoint(CGFloat)
        
        func relativeValue() -> CGFloat {
            switch self {
            case .start:
                return 0
            case .end:
                return 1
            case .middle:
                return 0.5
            case .relativePoint(let customValue):
                return customValue
            }
        }
    }
}

// MARK: - Application

extension CAGradientLayer {

    @MainActor
    func apply(gradient: DSL.Model.Style.Gradient?, in env: UITraitEnvironment, disableAnimation: Bool = true) {
        CATransaction.begin()
        if disableAnimation {
            CATransaction.setDisableActions(true)
        }
        if let gradient {
            colors = gradient.colorsList.map { $0.resolvedColor(with: env.traitCollection).cgColor }
            locations = gradient.locationsList.map { NSNumber(value: Float($0)) }
            startPoint = gradient.start.relativePoint
            endPoint = gradient.end.relativePoint
        } else {
            colors = nil
            locations = nil
            startPoint = .zero
            endPoint = .zero
        }
        CATransaction.commit()
    }
}
