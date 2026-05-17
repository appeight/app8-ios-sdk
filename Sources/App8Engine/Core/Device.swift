import UIKit

public struct Device {
    let model: DeviceModelGroup
    let screenSize: CGSize

    @MainActor
    public static var id: String? {
        return UIDevice.current.identifierForVendor?.uuidString
    }
    
    @MainActor
    public static var current: Device {
        let screenSize = UIScreen.main.nativeBounds.size
        let model = device(by: UIScreen.main.nativeBounds.height)
        return Device(model: model, screenSize: screenSize)
    }
    
    private static func device(by screenHeight: CGFloat) -> DeviceModelGroup {
        let orderedModelGroups = DeviceModelGroup.allCases.sorted()
        for model in orderedModelGroups {
            if model.nativeScreenHeightRange.contains(screenHeight) {
                return model
            }
        }
        return .unknownCurrent
    }
}

public enum DeviceModelGroup: Int, Comparable, CaseIterable {
    case iPhone5_SE1 = 0,
         iPhone6_8_SE2,
         iPhoneNotch,
         iPhonePlus,
         iPhone13Mini,
         iPhone14,
         iPhone13ProMax,
         iPhone16,
         iPhone14Plus,
         iPhone16Plus,
         iPhone16Pro,
         iPhone16ProMax,
         unknownCurrent

    fileprivate var nativeScreenHeightRange: ClosedRange<CGFloat> {
        switch self {
        case .iPhone5_SE1:
            return .just(1136)
        case .iPhone6_8_SE2:
            return .just(1334)
        case .iPhoneNotch:
            return .just(1792)
        case .iPhonePlus:
            return 1920 ... 2208
        case .iPhone13Mini:
            return .just(2436)
        case .iPhone14:
            return .just(2532)
        case .iPhone16:
            return .just(2556)
        case .iPhone16Pro:
            return .just(2622)
        case .iPhone13ProMax:
            return .just(2688) // 11 Pro Max, 12 Pro Max, 13 Pro Max
        case .iPhone14Plus:
            return .just(2778) // + 13 Pro Max
        case .iPhone16Plus:
            return .just(2796)
        case .iPhone16ProMax:
            return .just(2868)
        case .unknownCurrent:
            return .just(.zero)
        }
    }
    
    public static func < (lhs: DeviceModelGroup, rhs: DeviceModelGroup) -> Bool {
        let lhsHeight = lhs.nativeScreenHeightRange.middle
        let rhsHeight = rhs.nativeScreenHeightRange.middle
        return lhsHeight < rhsHeight
    }
    
    public var hasNotch: Bool {
        return self == .iPhoneNotch || self >= .iPhone13Mini
    }
}
