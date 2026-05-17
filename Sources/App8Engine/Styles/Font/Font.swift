import Foundation
import UIKit

extension DSL.Model.Style {

    struct Font: Decodable {
        let family: Family
    }
}

extension DSL.Model.Style.Font {

    struct Family: Decodable {
        let displayName: String
        /// When true (e.g. San Francisco), other font properties may be omitted.
        let isSystemFont: Bool
        let foundry: String?
        let license: String?
        let variable: Bool?
        @SafeOptionalArrayDecodable
        var faces: [Face]? = nil // nil when variable == true
//        @SafeOptionalArrayDecodable
        var axes: [Axis]? // only for variable fonts
        let asset: DSL.Model.Asset?
    }

    struct Face: Decodable {
        let postScriptName: String
        let style: Style
        let weight: Weight // 100–900
        let width: Int? // optional
        let asset: DSL.Model.Asset // every face is usually a separate font file
    }
    
    enum Weight: String, Codable, MappedCodableBridge {
        case ultraLight,
             thin,
             light,
             regular,
             medium,
             semibold,
             bold,
             heavy,
             black
        
        static var mappedKeyPath: KeyPath<Self, MappedValue> { \.uiFontWeight }
        
        var uiFontWeight: UIFont.Weight {
            switch self {
            case .ultraLight: return .ultraLight
            case .thin: return .thin
            case .light: return .light
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .heavy: return .heavy
            case .black: return .black
            }
        }
        
        init(_ mappedValue: UIFont.Weight) {
            switch mappedValue {
            case .ultraLight: self = .ultraLight
            case .thin: self = .thin
            case .light: self = .light
            case .regular: self = .regular
            case .medium: self = .medium
            case .semibold: self = .semibold
            case .bold: self = .bold
            case .heavy: self = .heavy
            case .black: self = .black
            default: self = .regular
            }
        }
    }

    enum Style: String, Codable {
        case normal, italic, oblique
    }

    struct Axis: Decodable {
        let tag: String // "wght", "ital", …
        let min: Double
        let max: Double
        let `default`: Double
    }
}
