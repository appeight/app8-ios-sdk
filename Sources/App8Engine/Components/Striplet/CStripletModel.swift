import UIKit

extension DSL.Model.Component {

    struct Striplet {

        struct Properties: Decodable {
            /// Order of elements by ids: "prefixIcon", "text", "suffixIcon".
            let order: [String]
            let spacing: Spacing
        }

        struct Spacing: Decodable {
            let type: `Type`
            let value: CGFloat
            
            enum `Type`: String, Decodable {
                case fixed, flexible
            }
        }
    }
}
