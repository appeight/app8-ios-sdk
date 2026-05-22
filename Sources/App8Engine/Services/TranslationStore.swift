import Foundation

/// Localised string table for the running app plus the active locale. Loaded
/// once at boot via `App8DataSource.getTranslations()`; locale flips at runtime
/// via `setActive(_:)`. See `lookup(key:)` for the full fallback chain.
@MainActor
public final class TranslationStore {

    public private(set) var defaultLocale: String = "en"
    private var locales: [String: [String: String]] = [:]
    private var activeLocaleOverride: String?

    /// Per-key fallback consulted on an in-memory miss. Default looks up against
    /// the host app's `Bundle.main` `.lproj` so customers can ship strings via
    /// `Localizable.xcstrings` with no glue. Set to nil to opt out.
    public var bundleResolver: ((_ key: String, _ locale: String) -> String?)? = TranslationStore.defaultBundleResolver

    /// Tries exact `<locale>.lproj`, then language-only `<lang>.lproj`. Uses a
    /// sentinel because `Bundle.localizedString` returns the key on a miss —
    /// indistinguishable from a key-shaped translation otherwise.
    private static let defaultBundleResolver: @Sendable (String, String) -> String? = { key, locale in
        let sentinel = "\u{0}__app8_translation_missing__\u{0}"
        let tryBundle: (String) -> String? = { tag in
            guard let path = Foundation.Bundle.main.path(forResource: tag, ofType: "lproj"),
                  let bundle = Foundation.Bundle(path: path) else { return nil }
            let v = bundle.localizedString(forKey: key, value: sentinel, table: nil)
            return v == sentinel ? nil : v
        }
        if let exact = tryBundle(locale) { return exact }
        let lang = languageOnly(locale)
        if lang != locale, let langMatch = tryBundle(lang) { return langMatch }
        return nil
    }

    public init() {}

    /// Replace the loaded translation bundle. A later call fully overrides the
    /// prior one (e.g. cloud SDK refreshing from disk cache → network).
    public func load(defaultLocale: String, locales: [String: [String: String]]) {
        self.defaultLocale = canonicalise(defaultLocale)
        var canonical: [String: [String: String]] = [:]
        for (k, v) in locales {
            canonical[canonicalise(k)] = v
        }
        self.locales = canonical
    }

    /// Override the active locale. Passing nil reverts to the device's first
    /// preferred language. Visible on the next render only.
    public func setActive(_ locale: String?) {
        activeLocaleOverride = locale.flatMap { canonicalise($0) }
    }

    /// Override → device default → app default. Always non-nil.
    public var activeLocale: String {
        if let o = activeLocaleOverride { return o }
        if let device = Locale.preferredLanguages.first.flatMap({ canonicalise($0) }) {
            return device
        }
        return defaultLocale
    }

    /// `Locale` form of `activeLocale` for `ExpressionEvaluator` formatters.
    public var activeLocaleObject: Locale {
        Locale(identifier: activeLocale)
    }

    /// Resolution order: active → language-only → sibling region → bundle →
    /// defaultLocale. Bundle runs BEFORE defaultLocale so a host-shipped
    /// German `.xcstrings` wins over the server's English defaultLocale rows
    /// when the user picks German — otherwise the bundle layer would never
    /// fire. Returns nil if every layer misses.
    public func lookup(key: String) -> String? {
        let active = activeLocale
        if let s = locales[active]?[key] { return s }

        let activeLang = languageOnly(active)
        if active != activeLang, let s = locales[activeLang]?[key] {
            return s
        }
        // Match any `<lang>-<REGION>` that shares the same language subtag.
        for (k, v) in locales where k != active && languageOnly(k) == activeLang {
            if let s = v[key] { return s }
        }

        if let resolver = bundleResolver, let s = resolver(key, active) {
            return s
        }

        if active != defaultLocale, let s = locales[defaultLocale]?[key] {
            return s
        }

        return nil
    }

    /// Wire-shape returned by `App8DataSource.getTranslations()`.
    public struct Bundle: Decodable, Sendable {
        public let defaultLocale: String
        public let locales: [String: [String: String]]
    }
}

private func languageOnly(_ locale: String) -> String {
    if let dash = locale.firstIndex(of: "-") {
        return String(locale[..<dash]).lowercased()
    }
    return locale.lowercased()
}

private func canonicalise(_ raw: String) -> String {
    // fr_CA, fr-ca, FR-CA → fr-CA. Mirrors backend lib/locale-negotiate.ts.
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    let normalised = trimmed.replacingOccurrences(of: "_", with: "-")
    let parts = normalised.split(separator: "-")
    guard let lang = parts.first.map({ $0.lowercased() }) else { return trimmed }
    if parts.count >= 2 {
        return "\(lang)-\(parts[1].uppercased())"
    }
    return lang
}
