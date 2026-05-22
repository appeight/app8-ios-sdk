//
//  TranslationStoreTests.swift
//  App8EngineTests
//

import XCTest
@testable import App8Engine

@MainActor
final class TranslationStoreTests: XCTestCase {

    private func makeStore(
        defaultLocale: String = "en",
        locales: [String: [String: String]] = [:]
    ) -> TranslationStore {
        let s = TranslationStore()
        s.load(defaultLocale: defaultLocale, locales: locales)
        return s
    }

    // MARK: - Initial state

    func test_freshStoreHasEnglishDefaultAndNoLocales() {
        let s = TranslationStore()
        XCTAssertEqual(s.defaultLocale, "en")
        XCTAssertNil(s.lookup(key: "anything"))
    }

    // MARK: - Lookup chain

    func test_lookupReturnsExactMatchWhenActiveLocaleExists() {
        let s = makeStore(locales: [
            "en": ["home.greeting": "Hello"],
            "fr": ["home.greeting": "Bonjour"],
        ])
        s.setActive("fr")
        XCTAssertEqual(s.lookup(key: "home.greeting"), "Bonjour")
    }

    func test_lookupFallsBackToLanguageOnly() {
        // Active is fr-CA; only fr is loaded. Engine should serve the
        // language-only row rather than failing through to default.
        let s = makeStore(locales: [
            "en": ["home.greeting": "Hello"],
            "fr": ["home.greeting": "Bonjour"],
        ])
        s.setActive("fr-CA")
        XCTAssertEqual(s.lookup(key: "home.greeting"), "Bonjour")
    }

    func test_lookupFallsBackToSiblingRegionWithSameLanguage() {
        // Active is fr-FR; only fr-CA is loaded. Same language family — should
        // serve the Canadian translation rather than the English default.
        let s = makeStore(locales: [
            "en":    ["home.greeting": "Hello"],
            "fr-CA": ["home.greeting": "Salut"],
        ])
        s.setActive("fr-FR")
        XCTAssertEqual(s.lookup(key: "home.greeting"), "Salut")
    }

    func test_lookupFallsBackToDefaultLocaleWhenLanguageMissing() {
        let s = makeStore(
            defaultLocale: "en",
            locales: [
                "en": ["home.greeting": "Hello"],
            ]
        )
        s.setActive("ja")  // Not loaded at all.
        XCTAssertEqual(s.lookup(key: "home.greeting"), "Hello")
    }

    func test_lookupReturnsNilWhenKeyMissingEverywhere() {
        let s = makeStore(locales: [
            "en": ["home.greeting": "Hello"],
        ])
        s.setActive("en")
        XCTAssertNil(s.lookup(key: "nonexistent.key"))
    }

    // MARK: - Active locale override

    func test_setActiveOverrideTakesPrecedenceOverDeviceLocale() {
        let s = makeStore()
        s.setActive("zh-CN")
        XCTAssertEqual(s.activeLocale, "zh-CN")
    }

    func test_setActiveNilRevertsToDeviceOrDefault() {
        let s = makeStore(defaultLocale: "en")
        s.setActive("zh-CN")
        s.setActive(nil)
        // Without an override, the active locale falls back to the device's
        // first preferred language (canonicalised) or "en". We assert it's
        // no longer zh-CN rather than asserting a specific device locale, so
        // the test stays stable across CI environments.
        XCTAssertNotEqual(s.activeLocale, "zh-CN")
    }

    func test_activeLocaleObjectMatchesActiveLocaleString() {
        let s = makeStore()
        s.setActive("fr-CA")
        XCTAssertEqual(s.activeLocaleObject.identifier, "fr-CA")
    }

    // MARK: - Canonicalisation

    func test_loadCanonicalisesUnderscoreSeparators() {
        // Backend canonical form is `fr-CA`. If a publisher emits `fr_CA`
        // we still want exact-match lookup to succeed for clients that
        // request the canonical form.
        let s = TranslationStore()
        s.load(defaultLocale: "en", locales: [
            "fr_CA": ["home.greeting": "Salut"],
        ])
        s.setActive("fr-CA")
        XCTAssertEqual(s.lookup(key: "home.greeting"), "Salut")
    }

    func test_setActiveCanonicalisesCasing() {
        let s = makeStore(locales: [
            "fr-CA": ["home.greeting": "Salut"],
        ])
        s.setActive("FR-ca")
        XCTAssertEqual(s.lookup(key: "home.greeting"), "Salut")
        XCTAssertEqual(s.activeLocale, "fr-CA")
    }

    // MARK: - Reload

    func test_loadFullyReplacesPreviousLocales() {
        // Phase 2 disk-cache → network refresh path: a later load() must
        // remove keys that no longer exist server-side, not merge them.
        let s = makeStore(locales: [
            "en": ["a": "one", "b": "two"],
        ])
        s.setActive("en")
        XCTAssertEqual(s.lookup(key: "b"), "two")
        s.load(defaultLocale: "en", locales: [
            "en": ["a": "uno"],
        ])
        XCTAssertEqual(s.lookup(key: "a"), "uno")
        XCTAssertNil(s.lookup(key: "b"), "Removed keys must not linger after reload")
    }

    // MARK: - bundleResolver (host iOS bundle fallback)

    func test_bundleResolverConsultedOnInMemoryMiss() {
        // Key is missing in EVERY in-memory layer (active, language-only, and
        // defaultLocale). Resolver is invoked with the active locale.
        let s = makeStore(locales: ["en": ["other.key": "other"]])
        s.setActive("de")
        var observed: (String, String)?
        s.bundleResolver = { key, locale in
            observed = (key, locale)
            return "from-bundle"
        }
        let result = s.lookup(key: "x")
        XCTAssertEqual(result, "from-bundle",
            "Resolver result wins when the in-memory chain has no value for the key")
        XCTAssertEqual(observed?.0, "x")
        XCTAssertEqual(observed?.1, "de", "Resolver receives the active locale, not defaultLocale")
    }

    func test_bundleResolverSkippedWhenInMemoryHits() {
        // Server-loaded translations must win over the bundle layer.
        let s = makeStore(locales: [
            "en": ["x": "from-server"],
            "de": ["x": "von-server"],
        ])
        s.setActive("de")
        s.bundleResolver = { _, _ in
            XCTFail("bundleResolver must not be called when an in-memory match exists")
            return "from-bundle"
        }
        XCTAssertEqual(s.lookup(key: "x"), "von-server")
    }

    func test_bundleResolverNilOptsOut() {
        // Setting resolver to nil disables the host-bundle layer entirely.
        // The lookup returns nil (debug-placeholder path in PropertyResolver).
        let s = makeStore(locales: ["en": [:]])
        s.setActive("de")
        s.bundleResolver = nil
        XCTAssertNil(s.lookup(key: "missing"))
    }

    func test_bundleResolverReturnsNilFallsThroughToFinalNil() {
        // Resolver returning nil = "no bundle entry either"; final result
        // is nil so caller can render the key itself as a placeholder.
        let s = makeStore(locales: ["en": [:]])
        s.setActive("de")
        s.bundleResolver = { _, _ in nil }
        XCTAssertNil(s.lookup(key: "missing"))
    }

    func test_bundleResolverFiresBeforeDefaultLocaleFallback() {
        // Loaded data covers default ("en") only; active "de" misses in
        // active + language-only chain. Bundle resolver runs NEXT (before
        // defaultLocale) so a host-shipped German .xcstrings wins over the
        // server's English defaultLocale strings — which is the whole point
        // of "ship a locale the server didn't publish via the host bundle".
        let s = makeStore(
            defaultLocale: "en",
            locales: ["en": ["x": "english-from-server"]]
        )
        s.setActive("de")
        s.bundleResolver = { _, _ in "deutsch-from-bundle" }
        XCTAssertEqual(s.lookup(key: "x"), "deutsch-from-bundle",
            "Bundle must outrank the defaultLocale fallback so customer-shipped " +
            "translations actually display on locales the server didn't publish.")
    }

    func test_defaultLocaleFiresWhenBundleResolverReturnsNil() {
        // Bundle says "I don't know either" → fall through to the
        // server-loaded defaultLocale as the final last-resort layer.
        let s = makeStore(
            defaultLocale: "en",
            locales: ["en": ["x": "english-from-server"]]
        )
        s.setActive("de")
        s.bundleResolver = { _, _ in nil }
        XCTAssertEqual(s.lookup(key: "x"), "english-from-server")
    }
}
