import Foundation

protocol CustomDecodable: Decodable {
    static func decode<CodingKeys: CodingKey>(fromContainer container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Self
}
