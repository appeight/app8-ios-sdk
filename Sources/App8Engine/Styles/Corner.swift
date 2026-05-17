import UIKit

extension DSL.Model.Style {

    struct Corner: Decodable {
        typealias Entity = ConcreteEntity<Self>
        
        let radius: CGFloat
        let curve: Curve
        
        static var none: Corner {
            .init(radius: .zero, curve: .circular)
        }
        
        enum Curve: String, SafeEnumCodable {
            case circular, continuous
            static var unknownCase: Self { .circular }
            var ca: CALayerCornerCurve {
                switch self {
                case .circular: return .circular
                case .continuous: return .continuous
                }
            }
        }
    }
}

extension CALayer {

    func apply(cornerStyle: DSL.Model.Style.Corner) {
        masksToBounds = cornerStyle.radius > 0
        cornerRadius = cornerStyle.radius
        cornerCurve = cornerStyle.curve.ca
    }
}
