import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
    case string(String), number(Double), bool(Bool), null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from d: any Decoder) throws {
        guard d.codingPath.count <= EngineLimits.maxJSONDepth else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: d.codingPath,
                debugDescription: "JSON nested too deeply"))
        }
        // Single values first, then arrays, then objects.
        let sv = try d.singleValueContainer()
        if sv.decodeNil() { self = .null; return }
        if let b = try? sv.decode(Bool.self) { self = .bool(b); return }
        if let n = try? sv.decode(Double.self) { self = .number(n); return }
        if let s = try? sv.decode(String.self) { self = .string(s); return }

        if var a = try? d.unkeyedContainer() {
            var arr: [JSONValue] = []
            while !a.isAtEnd { arr.append(try a.decode(JSONValue.self)) }
            self = .array(arr)
            return
        }

        let o = try d.container(keyedBy: AnyCodingKey.self)
        var dict: [String: JSONValue] = [:]
        for k in o.allKeys {
            dict[k.stringValue] = try o.decode(JSONValue.self, forKey: k)
        }
        self = .object(dict)
    }

    public func encode(to e: any Encoder) throws {
        switch self {
        case .null:
            var c = e.singleValueContainer(); try c.encodeNil()
        case .bool(let v):
            var c = e.singleValueContainer(); try c.encode(v)
        case .number(let v):
            var c = e.singleValueContainer(); try c.encode(v)
        case .string(let v):
            var c = e.singleValueContainer(); try c.encode(v)
        case .array(let arr):
            var a = e.unkeyedContainer()
            for v in arr { try a.encode(v) }
        case .object(let dict):
            var o = e.container(keyedBy: AnyCodingKey.self)
            for (k, v) in dict { try o.encode(v, forKey: AnyCodingKey(k)) }
        }
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    init(_ s: String) { self.stringValue = s }
    init?(stringValue: String) { self.init(stringValue) }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
}

/// Captures the entire subtree under the current Decoder.
struct RawJSON: Decodable {
    let value: JSONValue

    init(from decoder: any Decoder) throws {
        self.value = try JSONValue(from: decoder)
    }

    var data: Data {
        // Re-encoded tree — formatting/key order may differ from the original.
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    var string: String {
        String(data: data, encoding: .utf8) ?? ""
    }
}
