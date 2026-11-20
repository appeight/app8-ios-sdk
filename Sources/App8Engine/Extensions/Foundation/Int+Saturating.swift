import Foundation

extension Int {
    /// `Int(d)` traps on NaN, ±infinity and values outside `Int`'s range, and DSL
    /// numbers and expressions can produce all of them (`1e300`, `{{ 1 / 0 }}`,
    /// `round("1e309")`). This clamps to `Int.min...Int.max` instead; NaN is 0.
    init(saturating d: Double) {
        if d.isNaN {
            self = 0
        } else if d >= Double(Int.max) {   // Double(Int.max) rounds up to 2^63
            self = .max
        } else if d <= Double(Int.min) {
            self = .min
        } else {
            self = Int(d)
        }
    }

    init(saturating d: CGFloat) { self.init(saturating: Double(d)) }
}

extension Double {
    /// A whole number small enough to be exact as an `Int` (|d| < 2^53) comes
    /// back as `Int`, anything else (fractions, huge values, ±infinity, NaN)
    /// stays `Double`. Expression results use this so `1e300 + 1` can't trap.
    var wholeIntOrSelf: Any {
        if isFinite, truncatingRemainder(dividingBy: 1) == 0, Swift.abs(self) < 9e15 { return Int(self) }
        return self
    }
}
