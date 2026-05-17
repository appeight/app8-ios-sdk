import UIKit

extension DSL.Model.Style.Color {

    private typealias Style = DSL.Model.Style

    struct Themed: Decodable, MappedCodableBridge, Equatable, Style.StylePointerResolvable {
        typealias MappedValue = UIColor
        struct Ref: Decodable { let id: String }
        static var mappedKeyPath: KeyPath<Self, MappedValue> { \.ui }

        var ui: UIColor {
            if let dark {
                return UIColor { tc in
                    (tc.userInterfaceStyle == .dark ? dark.ui : light?.ui) ?? .clear
                }
            }
            return light?.ui ?? .clear
        }
        
        let source: Source
        
        /// Refs
        private var lightRef: Ref?
        private var darkRef: Ref?
        
        /// Actual resolved hexes
        private(set) var light: Hex?
        private(set) var dark: Hex?
        
        enum Source {
            case singleHex, themed
        }
        
        enum CodingKeys: CodingKey {
            case light, dark
        }
        
        init(from decoder: any Decoder) throws {
            if let singleValueContainer = try? decoder.singleValueContainer(),
               let hexString = try? singleValueContainer.decode(String.self) {
                let hex = Hex(hexString)
                self.light = hex
                self.source = .singleHex
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            source = .themed
            if let lightRef = try? container.decode(Ref.self, forKey: .light) {
                self.lightRef = lightRef
            } else {
                light = try container.decode(Hex.self, forKey: .light)
            }
            if let darkRef = try? container.decode(Ref.self, forKey: .dark) {
                self.darkRef = darkRef
            } else {
                dark = try container.decode(Hex.self, forKey: .dark)
            }
        }
        
        init(_ mappedValue: MappedValue) {
            let lightColor = mappedValue.resolvedColor(with: .init(userInterfaceStyle: .light))
            let darkColor = mappedValue.resolvedColor(with: .init(userInterfaceStyle: .dark))
            self.light = Hex(lightColor)
            if lightColor != darkColor {
                self.dark = Hex(darkColor)
            }
            self.source = .themed
        }
        
        /// Equatable conformance: compare only by `light` and `dark` if present
        static func == (lhs: Themed, rhs: Themed) -> Bool {
            return lhs.light == rhs.light && lhs.dark == rhs.dark
        }
        
        mutating func resolveStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {
            if let lightRef, let light = resolver(lightRef.id) as? DSL.Model.Style.ConcreteEntity<Themed> {
                self.light = light.content.light ?? light.content.dark
            }
            if let darkRef, let dark = resolver(darkRef.id) as? DSL.Model.Style.ConcreteEntity<Themed> {
                self.dark = dark.content.dark ?? dark.content.light
            }
        }
        
        func isResolved() -> Bool {
            return light.isNotNil || dark.isNotNil
        }

        func unresolvedPointerIds() -> [String] {
            var ids: [String] = []
            if light == nil, let ref = lightRef { ids.append(ref.id) }
            if dark == nil, let ref = darkRef { ids.append(ref.id) }
            return ids
        }
    }
    
    struct Hex: Decodable, Hashable, Sendable, MappedCodableBridge {
        
        typealias MappedValue = UIColor
        static var mappedKeyPath: KeyPath<Self, MappedValue> { \.ui }
        
        // w/o #
        let value: String
        let r, g, b, a: Float
        
        static let clear = Hex("00000000", r: 0, g: 0, b: 0, a: 0)
        
        /// Accepts an optional leading `#` followed by 3, 6, or 8 hex digits.
        static func isValidHexString(_ hex: String) -> Bool {
            let pattern = "^#?([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"
            return hex.range(of: pattern, options: .regularExpression) != nil
        }
        
        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            self = try .init(string)
        }
        
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode("#\(self.value)")
        }
        
        init(_ value: String, fallback: Hex = .clear) {
            do {
                try self.init(value)
            } catch {
                // No logger context in this non-throwing convenience init. The fallback
                // color is visible in the rendered UI, which is the actionable signal.
                self = fallback
            }
        }
        
        init(_ mappedValue: UIColor) {
            var rF: CGFloat = 0, gF: CGFloat = 0, bF: CGFloat = 0, aF: CGFloat = 0

            // Preferred: sRGB components
            if !mappedValue.getRed(&rF, green: &gF, blue: &bF, alpha: &aF) {
                // Fallback 1: grayscale
                var w: CGFloat = 0
                if mappedValue.getWhite(&w, alpha: &aF) {
                    rF = w; gF = w; bF = w
                } else {
                    // Fallback 2: read from CGColor components
                    let cg = mappedValue.cgColor
                    if let comps = cg.components {
                        switch comps.count {
                        case 4: // RGBA
                            rF = comps[0]; gF = comps[1]; bF = comps[2]; aF = comps[3]
                        case 2: // Gray + Alpha
                            rF = comps[0]; gF = comps[0]; bF = comps[0]; aF = comps[1]
                        default:
                            break
                        }
                    }
                }
            }

            // Clamp to [0,1]
            rF = max(0, min(1, rF))
            gF = max(0, min(1, gF))
            bF = max(0, min(1, bF))
            aF = max(0, min(1, aF))

            // Convert to 0...255 and format as RRGGBBAA (uppercase, no '#')
            let R = Int(round(rF * 255))
            let G = Int(round(gF * 255))
            let B = Int(round(bF * 255))
            let A = Int(round(aF * 255))
            let hex = String(format: "%02X%02X%02X%02X", R, G, B, A)

            self = .init(hex, r: Float(rF), g: Float(gF), b: Float(bF), a: Float(aF))
        }
        
        private init(_ hexString: String) throws {
            var cString = hexString
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()

            if cString.hasPrefix("#") { cString.removeFirst() }

            var value: UInt64 = 0
            guard Scanner(string: cString).scanHexInt64(&value) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "Invalid hex digits in \(hexString)")
                )
            }

            switch cString.count {
            case 3:         // #RGB
                self = .init(
                    cString,
                    r: Float((value & 0xF00) >> 8)  / 15.0,
                    g: Float((value & 0x0F0) >> 4)  / 15.0,
                    b: Float( value & 0x00F)        / 15.0,
                    a: 1.0
                )

            case 4:         // #RGBA  ← optional
                self = .init(
                    cString,
                    r: Float((value & 0xF000) >> 12) / 15.0,
                    g: Float((value & 0x0F00) >> 8)  / 15.0,
                    b: Float((value & 0x00F0) >> 4)  / 15.0,
                    a: Float( value & 0x000F)        / 15.0
                )

            case 6:         // #RRGGBB
                self = .init(
                    cString,
                    r: Float((value & 0xFF0000) >> 16) / 255.0,
                    g: Float((value & 0x00FF00) >>  8) / 255.0,
                    b: Float( value & 0x0000FF)        / 255.0,
                    a: 1.0
                )

            case 8:         // #RRGGBBAA  (CSS / SwiftUI order)
                self = .init(
                    cString,
                    r: Float((value & 0xFF000000) >> 24) / 255.0,
                    g: Float((value & 0x00FF0000) >> 16) / 255.0,
                    b: Float((value & 0x0000FF00) >>  8) / 255.0,
                    a: Float( value & 0x000000FF)        / 255.0
                )

            default:
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "Invalid hex color length in \(hexString)")
                )
            }
        }
        
        private init(_ value: String, r: Float, g: Float, b: Float, a: Float) {
            self.value = value
            self.r = r
            self.g = g
            self.b = b
            self.a = a
        }

        public var ui: UIColor {
            return UIColor(
                red: CGFloat(r),
                green: CGFloat(g),
                blue: CGFloat(b),
                alpha: CGFloat(a)
            )
        }
    }
}
