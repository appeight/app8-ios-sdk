import UIKit

public protocol BaseAppearance {
    typealias Param = AppearanceParam
    var margins: UIEdgeInsets { get }
    var paddings: UIEdgeInsets { get }
    var lineSpacing: CGFloat { get }
    var inlineItemSpacing: CGFloat { get }
}

public extension BaseAppearance {
    @MainActor
    func adjustedFontSize(_ size: CGFloat) -> CGFloat {
        let fontSizeMultiplier: CGFloat = (DDFactor.none.value + DDFactor.default.value) / 2
        return size * fontSizeMultiplier
    }
}

// MARK: - SharedAppearance

protocol SharedAppearance: BaseAppearance {
    init()
}

extension SharedAppearance {
    static var shared: Self { Self() }
}

// MARK: - AppearanceParam

@propertyWrapper
public struct AppearanceParam<T: DeviceDependantFactorApplicable> {

    private(set) var value: T
    private let ddFactor: DDFactor

    @MainActor public var wrappedValue: T {
        get {
            value.applying(ddFactor: ddFactor.value)
        }
        set {
            value = newValue
        }
    }
    
    var originalValue: T { value }

    init(_ value: T, ddFactor: DDFactor = .default) {
        self.value = value
        self.ddFactor = ddFactor
    }

    init(width: CGFloat, height: CGFloat, ddFactor: DDFactor = .default) where T == CGSize {
        self.value = CGSize(width: width, height: height)
        self.ddFactor = ddFactor
    }

    init(squared: CGFloat, ddFactor: DDFactor = .default) where T == CGSize {
        self.value = CGSize(width: squared, height: squared)
        self.ddFactor = ddFactor
    }
}

// MARK: - Device Dependant factor

public enum DDFactor {
    case none
    case `default`
    case custom((DeviceModelGroup) -> CGFloat)
    
    @MainActor
    var value: CGFloat {
        switch self {
        case .none:
            return 1.0
        case .default:
            return Device.current.model <= .iPhone6_8_SE2 ? 0.7 : 1.0
        case .custom(let block):
            return block(Device.current.model)
        }
    }
}

// MARK: - DeviceDependantFactorApplicable

public protocol DeviceDependantFactorApplicable {
    func applying(ddFactor: CGFloat) -> Self
}

extension CGFloat: DeviceDependantFactorApplicable {
    public func applying(ddFactor: CGFloat) -> CGFloat {
        self * ddFactor
    }
}

extension Float: DeviceDependantFactorApplicable {
    public func applying(ddFactor: CGFloat) -> Self {
        self * Self(ddFactor)
    }
}

extension CGSize: DeviceDependantFactorApplicable {
    public func applying(ddFactor: CGFloat) -> CGSize {
        CGSize(width: width * ddFactor, height: height * ddFactor)
    }
}
