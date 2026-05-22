import Foundation

/// Holds the full localised string table for the running app, plus the currently
/// active locale. Populated once at app boot from `App8DataSource.getTranslations()`;
/// the active locale can be flipped at any time via `setActive(_:)` — typically
/// by the cloud SDK's `instance.setLocale(...)` API.
///
/// Lookups walk a small fallback chain (active → language-only → defaultLocale)
/// so a missing `fr-CA` row still resolves to `fr` or finally `en`.
@MainActor
public final class TranslationStore {

    public private(set) var defaultLocale: String = "en"
    private var locales: [String: [String: String]] = [:]
    private var activeLocaleOverride: String?

    /// Per-key fallback consulted after the in-memory chain (active →
    /// language-only → defaultLocale) returns no value. Default
    /// implementation looks up against the host app's `Bundle.main` via
    /// standard `.lproj/Localizable.strings` lookup, so customers can ship
    /// strings via `Localizable.xcstrings` (or hand-authored `.lproj`
    /// directories) and have them resolve automatically with no glue code.
    ///
    /// Set to nil to opt out — useful for tests, or hosts that don't want
    /// the engine reading from `Bundle.main` implicitly.
    public var bundleResolver: ((_ key: String, _ locale: String) -> String?)? = TranslationStore.defaultBundleResolver

    /// Default `bundleResolver` implementation. Tries the exact locale's
    /// `<locale>.lproj/Localizable.strings`, then the language-only
    /// `<lang>.lproj` if the exact tag missed. Uses a NUL-padded sentinel
    /// to detect misses because `Bundle.localizedString` returns the key
    /// itself on a miss — which is a legal translation in degenerate cases.
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

    /// Replace the loaded translation bundle. Safe to call multiple times — a
    /// later call fully overrides the prior one (e.g. when the cloud SDK
    /// refreshes from disk cache → network).
    public func load(defaultLocale: String, locales: [String: [String: String]]) {
        self.defaultLocale = canonicalise(defaultLocale)
        var canonical: [String: [String: String]] = [:]
        for (k, v) in locales {
            canonical[canonicalise(k)] = v
        }
        self.locales = canonical
    }

    /// Override the active locale (e.g. `setActive("fr-CA")`). Passing nil
    /// reverts to the device's first preferred language. Visible only on the
    /// next render — already-rendered text is not re-resolved in v1.
    public func setActive(_ locale: String?) {
        activeLocaleOverride = locale.flatMap { canonicalise($0) }
    }

    /// The locale the engine will render strings in: override → device default
    /// → app default. Always non-nil so render-time code can rely on it.
    public var activeLocale: String {
        if let o = activeLocaleOverride { return o }
        if let device = Locale.preferredLanguages.first.flatMap({ canonicalise($0) }) {
            return device
        }
        return defaultLocale
    }

    /// `Locale` form of `activeLocale`, used by formatters (number, currency,
    /// date) inside `ExpressionEvaluator`. The override flows through here so
    /// `setLocale("fr")` on an `en` device formats numbers in French too.
    public var activeLocaleObject: Locale {
        Locale(identifier: activeLocale)
    }

    /// Lookup a translation key. Resolution order:
    /// 1. active locale (server-loaded)
    /// 2. language-only fallback (`fr-CA` → first `fr-*`) in server-loaded data
    /// 3. `bundleResolver` (default: `Bundle.main` `.lproj` lookup) — lets
    ///    customers ship host-app translations via `Localizable.xcstrings`
    ///    for locales the server didn't publish. Honors the engine's active
    ///    locale (not `Locale.preferredLanguages`), so `setLocale("de")` on
    ///    an English device still picks up `de.lproj` strings.
    /// 4. app `defaultLocale` (server-loaded, last resort)
    ///
    /// Order rationale: the bundle is a "fallback for locales the server
    /// didn't ship" — it must run BEFORE `defaultLocale`, otherwise on a
    /// store with English server data and a German bundle, picking German
    /// would just return English from the defaultLocale layer and the
    /// bundle would never get a chance.
    ///
    /// Returns nil if no layer contains the key — caller surfaces the key
    /// itself as a debug placeholder.
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

        // Host iOS bundle for the active locale — runs BEFORE defaultLocale
        // so customers can ship host-bundle translations that win over the
        // server's default-locale strings when the user picks that locale.
        if let resolver = bundleResolver, let s = resolver(key, active) {
            return s
        }

        if active != defaultLocale, let s = locales[defaultLocale]?[key] {
            return s
        }

        return nil
    }

    /// Wire-shape used by `App8DataSource.getTranslations()` — decoded from
    /// the JSON returned by `GET /sdk/v1/apps/{appId}/translations`.
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
    // Accept fr_CA, fr-ca, FR-CA, fr-CA → fr-CA. Mirrors the backend
    // lib/locale-negotiate.ts normaliser so both ends use the same keys.
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    let normalised = trimmed.replacingOccurrences(of: "_", with: "-")
    let parts = normalised.split(separator: "-")
    guard let lang = parts.first.map({ $0.lowercased() }) else { return trimmed }
    if parts.count >= 2 {
        return "\(lang)-\(parts[1].uppercased())"
    }
    return lang
}
