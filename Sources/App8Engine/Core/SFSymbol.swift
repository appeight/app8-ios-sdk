import UIKit

protocol SFSymbolProtocol {
    var systemName: String { get }
}

struct SFSymbol: Codable, Equatable, SFSymbolProtocol {
    let systemName: String
    init(systemName: String) {
        self.systemName = systemName
    }
}

extension SFSymbolProtocol {

    typealias Icon = DSL.Model.Component.Icon

    func asAttrbiutedString(tintColor: UIColor? = nil, font: UIFont? = nil, textAlignment: NSTextAlignment = .left) -> NSMutableAttributedString {
        let imageAttachment = NSTextAttachment()
        var config: UIImage.SymbolConfiguration?
        if let font {
            config = .init(font: font)
        }
        
        var image = image(config: config)
        if let color = tintColor {
            image = image?.withTintColor(color)
        }
        imageAttachment.image = image
        let string = NSMutableAttributedString(attachment: imageAttachment)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = textAlignment
        string.addAttributes([.paragraphStyle: paragraphStyle], range: .init(location: 0, length: string.length))
        return string
    }
    
    func asAttrbiutedString(textStyle: DSL.Model.Style.Text) -> NSMutableAttributedString {
        let imageAttachment = NSTextAttachment()
        let config = UIImage.SymbolConfiguration(font: textStyle.font)
        let image = image(config: config)?.withTintColor(textStyle.color)
        imageAttachment.image = image
        let string = NSMutableAttributedString(attachment: imageAttachment)
        string.addAttributes(textStyle.attributes(), range: .init(location: 0, length: string.length))
        return string
    }
    
    /*
    /**
     */
    func asAttrbiutedString(iconStyle: Icon.ViewModel.SymbolStyle, fallbackFont: UIFont) -> NSMutableAttributedString {
        let imageAttachment = NSTextAttachment()
        let config = UIImage.SymbolConfiguration(font: iconStyle.font ?? fallbackFont)
        var image = image(config: config)
        if let color = iconStyle.color {
            image = image?.withTintColor(color)
        }
        imageAttachment.image = image
        let string = NSMutableAttributedString(attachment: imageAttachment)
        
        var attributes: [NSAttributedString.Key: Any] = [:]
        if let font = iconStyle.font {
            attributes[.font] = font
        }
        if let color = iconStyle.color {
            attributes[.foregroundColor] = color
        }
        string.addAttributes(attributes, range: .init(location: 0, length: string.length))
        
        return string
    }
     */
    
    func image(config: UIImage.SymbolConfiguration? = nil) -> UIImage? {
        return UIImage(systemName: systemName, withConfiguration: config)
    }
    
    /*
    /**
     */
    func image(iconStyle: Icon.ViewModel.SymbolStyle, fallbackFont: UIFont = Style.Font.system(18, .regular)) -> UIImage? {
        let config: UIImage.SymbolConfiguration
        if #available(iOS 15, *), let hierarchicalColor = iconStyle.hierarchicalColor {
            config = .init(hierarchicalColor: hierarchicalColor)
        } else {
            config = .init(font: iconStyle.font ?? fallbackFont)
        }
        var image = image(config: config)
        if let color = iconStyle.color {
            image = image?.withRenderingMode(.alwaysTemplate).withTintColor(color)
        }
        return image
    }
     */
}

func +(_ symbol: SFSymbol, _ text: String) -> NSAttributedString {
    let imageAttachment = NSTextAttachment()
    imageAttachment.image = UIImage(systemName: symbol.systemName)
    let string = NSMutableAttributedString(attachment: imageAttachment)
    string.append(NSAttributedString(string: text))
    return string
}

func +(_ lhs: NSAttributedString, _ rhs: String) -> NSAttributedString {
    let attributedString = NSMutableAttributedString(attributedString: lhs)
    attributedString.append(NSAttributedString(string: rhs))
    return attributedString
}
