import UIKit

extension DSL.Model.Style {

    struct Image: Decodable, BaseStyleProtocol, StylePointerResolvable {
        let contentMode: View.ContentMode?
        @Wrapped var material: Material?
        let alpha: CGFloat?
        let transform: View.Transform?
        @Wrapped var tintColor: Color.Themed?
        let renderingMode: RenderingMode?
        let corner: Corner?

        mutating func resolveStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {
            _material.resolvePointer(type: .key(.material), resolver: resolver)
            _tintColor.resolvePointer(type: .key(.color), resolver: resolver)
        }
        
        func isResolved() -> Bool {
            let colorResolved = (_tintColor.base?.asEntity() as? ConcreteEntity<Color.Themed>)?.content.isResolved() ?? false
            if let material {
                let materialResolved = (material.isResolved() ? true : false)
                return colorResolved && materialResolved
            }
            return colorResolved
        }

        func unresolvedPointerIds() -> [String] {
            _material.unresolvedPointerIds() + _tintColor.unresolvedPointerIds()
        }
        
        /// Fully mirror UIImage.RenderingMode
        enum RenderingMode: String, SafeEnumCodable {
            case automatic
            case alwaysTemplate
            case alwaysOriginal
            
            static var unknownCase: Self {
                .automatic
            }
            
            var ui: UIImage.RenderingMode {
                switch self {
                case .automatic:
                    return .automatic
                case .alwaysTemplate:
                    return .alwaysTemplate
                case .alwaysOriginal:
                    return .alwaysOriginal
                }
            }
        }
    }
}
