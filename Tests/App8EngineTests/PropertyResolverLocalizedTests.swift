//
//  PropertyResolverLocalizedTests.swift
//  App8EngineTests
//

import XCTest
@testable import App8Engine

@MainActor
final class PropertyResolverLocalizedTests: XCTestCase {

    private var store: TranslationStore!
    private var resolver: PropertyResolver!
    private var variableStore: VariableStore!
    private var context: VariableContext!

    override func setUp() {
        super.setUp()
        store = TranslationStore()
        resolver = PropertyResolver(translationStore: store)
        variableStore = VariableStore()
        context = VariableContext(store: variableStore)
    }

    // MARK: - Literal pass-through

    func test_literalPassesThroughUnchanged() throws {
        let result = try resolver.resolveLocalizedToString(.literal("Hello"), context: context)
        XCTAssertEqual(result, "Hello")
    }

    func test_literalStillRunsExpressionInterpolation() throws {
        // .literal values keep the existing PropertyResolver behaviour —
        // i18n is purely additive, not a replacement.
        try variableStore.defineVariable(
            name: "name",
            definition: VariableDefinition(type: .string, initialValue: "Alex")
        )
        let result = try resolver.resolveLocalizedToString(
            .literal("Hi {{name}}"),
            context: context
        )
        XCTAssertEqual(result, "Hi Alex")
    }

    // MARK: - i18n key lookup

    func test_keyLookupResolvesToTranslation() throws {
        store.load(defaultLocale: "en", locales: [
            "fr": ["home.greeting": "Bonjour"],
        ])
        store.setActive("fr")
        let result = try resolver.resolveLocalizedToString(
            .key("home.greeting"),
            context: context
        )
        XCTAssertEqual(result, "Bonjour")
    }

    func test_keyLookupInterpolatesVariablesInTranslatedString() throws {
        // The pipeline is lookup → interpolation: a translated value can
        // still contain {{var}} placeholders, which resolve against the
        // current variable scope. This is the natural way translators
        // include names, counts, etc.
        store.load(defaultLocale: "en", locales: [
            "fr": ["welcome.back": "Bon retour, {{firstName}} !"],
        ])
        store.setActive("fr")
        try variableStore.defineVariable(
            name: "firstName",
            definition: VariableDefinition(type: .string, initialValue: "Alex")
        )
        let result = try resolver.resolveLocalizedToString(
            .key("welcome.back"),
            context: context
        )
        XCTAssertEqual(result, "Bon retour, Alex !")
    }

    func test_keyMissReturnsKeyAsDebugPlaceholder() throws {
        // Missing keys are non-fatal — render the key itself so authors
        // immediately spot which key is unlocalised in the UI.
        store.load(defaultLocale: "en", locales: ["en": [:]])
        store.setActive("en")
        let result = try resolver.resolveLocalizedToString(
            .key("missing.key"),
            context: context
        )
        XCTAssertEqual(result, "missing.key")
    }

    func test_keyLookupWithoutStoreReturnsKey() throws {
        // PropertyResolver constructed without a TranslationStore (e.g. in a
        // unit test or a host that opted out) treats every key as a miss
        // rather than crashing.
        let bareResolver = PropertyResolver()
        let result = try bareResolver.resolveLocalizedToString(
            .key("home.greeting"),
            context: context
        )
        XCTAssertEqual(result, "home.greeting")
    }

    // MARK: - Locale-aware formatters (ExpressionEvaluator threading)

    // MARK: - i18n() expression function (mirrors the `$i18n` DSL marker)

    func test_i18nFunctionResolvesVariableValueAsKey() throws {
        // Template-shaped DSL: text="{{i18n(title)}}" with title="card.safe.title"
        // passed as a screen-level variable. The `i18n()` call looks up the
        // variable's *value* as a translation key — the template stays
        // generic, screens parameterise it with i18n keys.
        store.load(defaultLocale: "en", locales: [
            "en": ["card.safe.title": "It's safe"],
            "fr": ["card.safe.title": "C'est sûr"],
        ])
        store.setActive("fr")
        try variableStore.defineVariable(
            name: "title",
            definition: VariableDefinition(type: .string, initialValue: "card.safe.title")
        )

        let result = try resolver.resolveLocalizedToString(
            .literal("{{i18n(title)}}"),
            context: context
        )
        XCTAssertEqual(result, "C'est sûr")
    }

    func test_i18nFunctionMissReturnsKeyForDebugVisibility() throws {
        store.load(defaultLocale: "en", locales: ["en": [:]])
        store.setActive("en")
        try variableStore.defineVariable(
            name: "title",
            definition: VariableDefinition(type: .string, initialValue: "nonexistent.key")
        )

        let result = try resolver.resolveLocalizedToString(
            .literal("{{i18n(title)}}"),
            context: context
        )
        XCTAssertEqual(result, "nonexistent.key",
            "Missing keys must surface as the key itself so authors notice")
    }

    func test_i18nFunctionAcceptsLiteralKey() throws {
        // `i18n("home.greeting")` form — key as a string literal in the
        // expression rather than via a variable. Same lookup path.
        store.load(defaultLocale: "en", locales: [
            "de": ["home.greeting": "Hallo"],
        ])
        store.setActive("de")
        let result = try resolver.resolveLocalizedToString(
            .literal("{{i18n('home.greeting')}}"),
            context: context
        )
        XCTAssertEqual(result, "Hallo")
    }

    func test_i18nFunctionUsableInsidePlainTextField() throws {
        // Regression guard: `{{i18n(...)}}` works inside a `.literal` text
        // value, not just inside templates. This lets authors choose between
        // the declarative object form `{"$i18n": "key"}` and the inline
        // expression form `"{{i18n('key')}}"` — both resolve via the same
        // TranslationStore chain. Useful when the key needs to compose with
        // surrounding literal text in one field.
        store.load(defaultLocale: "en", locales: [
            "de": ["home.greeting": "Hallo"],
        ])
        store.setActive("de")

        let result = try resolver.resolveLocalizedToString(
            .literal("{{i18n('home.greeting')}}, world!"),
            context: context
        )
        XCTAssertEqual(result, "Hallo, world!",
            "Inline i18n(...) must work inside ordinary text — same surface as $i18n object form")
    }

    func test_i18nFunctionWithoutStoreReturnsKey() throws {
        // PropertyResolver without a store can't look up — `i18n(key)` falls
        // through to the key itself, matching the missing-key debug path.
        let bareResolver = PropertyResolver()
        try variableStore.defineVariable(
            name: "title",
            definition: VariableDefinition(type: .string, initialValue: "card.safe.title")
        )
        let result = try bareResolver.resolveLocalizedToString(
            .literal("{{i18n(title)}}"),
            context: context
        )
        XCTAssertEqual(result, "card.safe.title")
    }

    func test_setLocaleAffectsCurrencyFormattingInTranslatedString() throws {
        // formatCurrency() inside ExpressionEvaluator reads `self.locale`,
        // which PropertyResolver syncs from the store before each evaluate.
        // Switching the active locale should change the formatted output
        // even if the translation string itself is identical.
        store.load(defaultLocale: "en", locales: [
            "en": ["price.total": "Total: {{formatCurrency(amount, 'USD')}}"],
            "de": ["price.total": "Total: {{formatCurrency(amount, 'USD')}}"],
        ])
        try variableStore.defineVariable(
            name: "amount",
            definition: VariableDefinition(type: .number, initialValue: 1234.5)
        )

        store.setActive("en-US")
        let usResult = try resolver.resolveLocalizedToString(.key("price.total"), context: context)

        store.setActive("de-DE")
        let deResult = try resolver.resolveLocalizedToString(.key("price.total"), context: context)

        XCTAssertNotEqual(usResult, deResult,
            "Same template + same amount should format differently across en-US and de-DE")
    }
}
