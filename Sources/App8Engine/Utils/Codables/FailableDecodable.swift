import Foundation

/// Converts a `[CodingKey]` to a dot/bracket JSON path like `content.children[2].style`.
func jsonPath(from codingPath: [CodingKey]) -> String {
    var result = ""
    for key in codingPath {
        if let index = key.intValue {
            result += "[\(index)]"
        } else {
            if !result.isEmpty { result += "." }
            result += key.stringValue
        }
    }
    return result
}

/// Collects decode errors from `FailableDecodable` when set as the active collector.
/// Used by diagnostics to capture nested failures inside `SafeArrayCodable` and similar wrappers.
final class DecodeErrorCollector {
    struct Entry {
        let typeName: String
        let codingPath: String
        let jsonPath: String
        let error: Error
    }

    nonisolated(unsafe) static var current: DecodeErrorCollector?

    private let lock = NSLock()
    private var _entries: [Entry] = []

    /// Collected entries — lock-guarded; decoding can run on multiple threads.
    var entries: [Entry] {
        lock.lock(); defer { lock.unlock() }
        return _entries
    }

    func record(error: Error, typeName: String, codingPath: [CodingKey]) {
        let path = codingPath.map(\.stringValue).joined(separator: " → ")
        let jp = jsonPath(from: codingPath)
        lock.lock()
        _entries.append(Entry(typeName: typeName, codingPath: path, jsonPath: jp, error: error))
        lock.unlock()
    }
}

protocol FailableDecodableProtocol {
    associatedtype BaseType: Decodable
    var base: BaseType? { get }
    var decodingError: Error? { get }
}

class FailableDecodable<Base: Decodable>: Decodable, FailableDecodableProtocol {

    let base: Base?
    private(set) var decodingError: Error?

    required init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            self.base = try container.decode(Base.self)
        } catch {
            // Unknown or mistyped values are ignored, never fatal: retry the
            // element without the offending value(s) before dropping it whole.
            if let recovered = Self.recover(container: container, decoder: decoder) {
                self.base = recovered
                return
            }
            self.base = nil
            self.decodingError = error
            DecodeErrorCollector.current?.record(
                error: error,
                typeName: String(describing: Base.self),
                codingPath: decoder.codingPath
            )
        }
    }

    func resolve() -> Base? {
        return base
    }

    /// Re-reads the element as raw JSON and decodes it with
    /// `LenientDocumentDecoding`, which drops the value at each failure's path
    /// (its default applies). Nil when the element itself is unusable (an
    /// unknown component type, not an object, …): then it is dropped.
    private static func recover(container: SingleValueDecodingContainer, decoder: Decoder) -> Base? {
        guard let raw = try? container.decode(JSONValue.self),
              let data = try? JSONEncoder().encode(raw) else { return nil }
        let retry = JSONDecoder()
        retry.userInfo = decoder.userInfo
        let logger = decoder.userInfo[.app8Logger] as? A8Log
        let at = jsonPath(from: decoder.codingPath)
        return try? LenientDocumentDecoding.decode(Base.self, from: data, using: retry) {
            logger?.warning("\(at): \($0)")
        }
    }
}

extension Array where Element: FailableDecodableProtocol {

    func resolve() -> [Element.BaseType] {
        // Per-element errors are recorded in DecodeErrorCollector.current; no logger here.
        return self.compactMap { $0.base }
    }

    /// Returns both successfully resolved items and per-index errors for items that failed to decode.
    func resolveWithErrors() -> (resolved: [Element.BaseType], errors: [(index: Int, error: Error)]) {
        var resolved: [Element.BaseType] = []
        var errors: [(index: Int, error: Error)] = []
        for (i, element) in self.enumerated() {
            if let base = element.base {
                resolved.append(base)
            } else if let error = element.decodingError {
                errors.append((i, error))
            }
        }
        return (resolved, errors)
    }

    /// Formats a decoding error into a human-readable string with path information.
    static func formatDecodingError(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }
        switch decodingError {
        case .keyNotFound(let key, let ctx):
            let path = ctx.codingPath.map(\.stringValue).joined(separator: " → ")
            let jp = jsonPath(from: ctx.codingPath + [key])
            return "missing key '\(key.stringValue)' at [\(path)] (jsonpath: \(jp)) — \(ctx.debugDescription)"
        case .typeMismatch(let type, let ctx):
            let path = ctx.codingPath.map(\.stringValue).joined(separator: " → ")
            let jp = jsonPath(from: ctx.codingPath)
            return "type mismatch (expected '\(type)') at [\(path)] (jsonpath: \(jp)) — \(ctx.debugDescription)"
        case .valueNotFound(let type, let ctx):
            let path = ctx.codingPath.map(\.stringValue).joined(separator: " → ")
            let jp = jsonPath(from: ctx.codingPath)
            return "value not found (expected '\(type)') at [\(path)] (jsonpath: \(jp)) — \(ctx.debugDescription)"
        case .dataCorrupted(let ctx):
            let path = ctx.codingPath.map(\.stringValue).joined(separator: " → ")
            let jp = jsonPath(from: ctx.codingPath)
            return "data corrupted at [\(path)] (jsonpath: \(jp)) — \(ctx.debugDescription)"
        @unknown default:
            return "\(error)"
        }
    }

    private static func printDecodingError(_ error: Error, targetType: Any.Type, index: Int) {
        // Errors are captured in DecodeErrorCollector.current. No logger reference here.
        _ = formatDecodingError(error)
    }
}
