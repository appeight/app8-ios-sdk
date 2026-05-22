import Foundation

/// A DSL text value that can be either a plain literal or a translation key.
///
/// Decoding rules:
///   - A bare JSON string decodes to `.literal(string)`. Backward compatible —
///     every existing DSL text field keeps working with no schema change.
///   - A JSON object with shape `{"$i18n": "key"}` decodes to `.key("key")` and
///     is looked up against the active locale in `TranslationStore` at render time.
///
/// Plain strings are **never** treated as keys. The `$i18n` marker is required
/// to opt a value into the lookup path.
public enum LocalizedString: Sendable, Decodable {
    case literal(String)
    case key(String)

    private enum CodingKeys: String, CodingKey {
        case i18n = "$i18n"
    }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let s = try? single.decode(String.self) {
            self = .literal(s)
            return
        }
        // Object form must be `{ "$i18n": "key" }` — anything else throws so
        // schema typos surface at decode time, not as silent empty strings.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let key = try c.decode(String.self, forKey: .i18n)
        self = .key(key)
    }

    /// Raw string for debug / non-localised paths. For `.key`, returns the key
    /// itself — used as the visible placeholder on a missing translation.
    public var rawValue: String {
        switch self {
        case .literal(let s): return s
        case .key(let k):     return k
        }
    }
}
