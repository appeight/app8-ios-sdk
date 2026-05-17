import UIKit

/// All styles from UIBlurEffect.Style
enum BackgroundBlur: String, Codable {
    case extraLight
    case light
    case dark
    case regular
    case systemUltraThinMaterial
    case systemThinMaterial
    case systemMaterial
    case systemThickMaterial
    case systemChromeMaterial
    case systemUltraThinMaterialDark
    case systemThinMaterialDark
    case systemMaterialDark
    case systemThickMaterialDark
    case systemChromeMaterialDark

    var uiBlurStyle: UIBlurEffect.Style {
        switch self {
        case .extraLight: return .extraLight
        case .light: return .light
        case .dark: return .dark
        case .regular: return .regular
        case .systemUltraThinMaterial: return .systemUltraThinMaterial
        case .systemThinMaterial: return .systemThinMaterial
        case .systemMaterial: return .systemMaterial
        case .systemThickMaterial: return .systemThickMaterial
        case .systemChromeMaterial: return .systemChromeMaterial
        case .systemUltraThinMaterialDark: return .systemUltraThinMaterialDark
        case .systemThinMaterialDark: return .systemThinMaterialDark
        case .systemMaterialDark: return .systemMaterialDark
        case .systemThickMaterialDark: return .systemThickMaterialDark
        case .systemChromeMaterialDark: return .systemChromeMaterialDark
        }
    }
}
