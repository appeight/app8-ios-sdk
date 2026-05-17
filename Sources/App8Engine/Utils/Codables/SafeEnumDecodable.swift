import Foundation

/// For safe enum decoding if failed to decode returns unknown case
protocol SafeEnumCodable: Codable, RawRepresentable where RawValue: Decodable {

    /// Provide case for failed decoding here
    ///
    /// ```
    ///  enum DayTime: String, Codable, SafeEnum {
    ///     case day
    ///     case night
    ///
    ///     case unknown
    ///
    ///     static var unknownCase: Self {
    ///         .unknown
    ///     }
    ///  }
    ///  ```
    static var unknownCase: Self { get }
}

extension SafeEnumCodable {

    init(from decoder: Decoder) throws {
        let unknownCaseRawValue = Self.unknownCase

        if let rawValue = try? FailableDecodable<RawValue>(from: decoder).resolve() {
            self = Self(rawValue: rawValue) ?? unknownCaseRawValue
        } else {
            self = unknownCaseRawValue
        }
    }
}
