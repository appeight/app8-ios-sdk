extension ClosedRange {

    static func just(_ value: Bound) -> ClosedRange<Bound> {
        return value...value
    }
}

extension ClosedRange where Bound: BinaryInteger {
    /// Middle point using integer arithmetic.
    /// `3...7` → `5`
    var middle: Bound {
        lowerBound + (upperBound - lowerBound) / 2
    }
}

extension ClosedRange where Bound: BinaryFloatingPoint {
    /// Exact midpoint of the range.
    /// `0.0...1.0` → `0.5`
    var middle: Bound {
        (lowerBound + upperBound) / 2
    }
}
