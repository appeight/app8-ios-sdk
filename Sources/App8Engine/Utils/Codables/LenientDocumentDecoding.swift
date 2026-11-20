import Foundation

/// Decodes a whole DSL document (a screen, `app.json`, a template) so one bad
/// value does not reject it: unknown or mistyped values are ignored, never
/// fatal (DSL spec, "Unknown and mistyped values").
///
/// Elements inside lenient containers (children, material layers, …) are
/// already dropped by their own decoders. A bad value on any other field
/// (`navigationBar.title: 5`, `hidesTabBar: "no"`, a malformed `onEvent`)
/// used to fail the whole screen. Here the value at the failure's coding path
/// is removed (so its default applies) and decoding is retried, up to
/// `maxDrops` times; each drop is reported to `warn`. The document still
/// fails when its root is unusable (no `type`, not an object). The first
/// attempt decodes the original bytes, so valid documents cost nothing extra.
/// Android: `DegradingDecode`.
enum LenientDocumentDecoding {
    static let maxDrops = 32

    static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        using decoder: JSONDecoder,
        warn: (String) -> Void
    ) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch let firstError as DecodingError {
            // Not JSON at all: nothing to drop.
            guard var root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                throw firstError
            }
            var error = firstError
            for _ in 0..<maxDrops {
                guard let path = Self.path(of: error), !path.isEmpty,
                      let reduced = Self.removing(path, from: root) else {
                    throw error
                }
                warn("value.ignored: '\(jsonPath(from: path))' in \(T.self) — \(Self.reason(error)); using the default")
                root = reduced
                guard let next = try? JSONSerialization.data(withJSONObject: root, options: [.fragmentsAllowed]) else {
                    throw error
                }
                do {
                    return try decoder.decode(type, from: next)
                } catch let again as DecodingError {
                    error = again
                }
            }
            throw error
        }
    }

    /// The coding path of the offending value. For a missing required key the
    /// path is its container: dropping the container lets an optional parent
    /// fall back to its default.
    static func path(of error: DecodingError) -> [CodingKey]? {
        switch error {
        case .typeMismatch(_, let c), .valueNotFound(_, let c), .dataCorrupted(let c):
            return c.codingPath
        case .keyNotFound(_, let c):
            return c.codingPath
        @unknown default:
            return nil
        }
    }

    private static func reason(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let t, _): return "expected \(t)"
        case .valueNotFound(let t, _): return "missing \(t)"
        case .keyNotFound(let k, _): return "missing required '\(k.stringValue)'"
        case .dataCorrupted(let c): return c.debugDescription
        @unknown default: return "\(error)"
        }
    }

    /// `root` without the value at `path`; nil when the path does not exist.
    static func removing(_ path: [CodingKey], from root: Any) -> Any? {
        guard let head = path.first else { return nil }
        let rest = Array(path.dropFirst())
        if var object = root as? [String: Any], head.intValue == nil || object[head.stringValue] != nil {
            guard let child = object[head.stringValue] else { return nil }
            if rest.isEmpty {
                object[head.stringValue] = nil
            } else {
                guard let reduced = removing(rest, from: child) else { return nil }
                object[head.stringValue] = reduced
            }
            return object
        }
        if var array = root as? [Any], let index = head.intValue, array.indices.contains(index) {
            if rest.isEmpty {
                array.remove(at: index)
            } else {
                guard let reduced = removing(rest, from: array[index]) else { return nil }
                array[index] = reduced
            }
            return array
        }
        return nil
    }
}
