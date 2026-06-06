# Localization (i18n)

App8 DSL can render the same screen in multiple languages. Translatable text is stored as **keys** that resolve against the active locale at render time, so switching language re-renders the UI without touching the DSL.

There are two ways to localize text:

1. The **`$i18n` marker** on a text value (declarative).
2. The **`i18n()` expression function** inside `{{...}}` (for computed text).

Both resolve through the same lookup chain and the same translation bundle.

---

## The `$i18n` Marker

Any DSL text value that is normally a plain string can instead be an object of the shape `{ "$i18n": "key" }`. The engine looks the key up against the active locale and substitutes the translated string.

```json
{
  "type": "label",
  "content": {
    "properties": { "text": { "$i18n": "home.greeting" } }
  }
}
```

- A **plain string** is *never* treated as a key — it renders verbatim. The `$i18n` marker is required to opt into translation, so existing DSL keeps working unchanged.
- On a **missing key**, the key itself is rendered as a visible placeholder (so untranslated values are obvious, not blank).
- The looked-up text is still run through `{{...}}` interpolation, so a translation can contain variables:

```json
"home.greeting" : "Hello, {{userName}}!"
```

---

## The `i18n()` Function

Inside an expression, `i18n(key)` returns the translation for `key`. Use it when the key itself is dynamic or when translated text is part of a larger computed expression.

```json
"text": "{{i18n('cart.title')}}"
"text": "{{i18n(item.statusKey)}}"
"text": "{{count}} {{i18n(count == 1 ? 'unit.item' : 'unit.items')}}"
```

Like the marker, a missed key returns the key string itself. See [variables.md → String functions](variables.md#string-functions).

---

## Translation Bundle

Translations are supplied by the host through `App8DataSource.getTranslations()` (see [host-integration.md](host-integration.md)). The payload is a JSON object of this shape:

```json
{
  "defaultLocale": "en",
  "locales": {
    "en": {
      "home.greeting": "Hello, {{userName}}!",
      "cart.title": "Your Cart"
    },
    "fr": {
      "home.greeting": "Bonjour, {{userName}} !",
      "cart.title": "Votre panier"
    },
    "fr-CA": {
      "cart.title": "Votre panier"
    }
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `defaultLocale` | string | Locale used when no active locale or no match is found |
| `locales` | object | Map of locale code → (key → translated string) |

Locale codes are canonicalized: `fr_CA`, `fr-ca`, and `FR-CA` all normalize to `fr-CA` (lowercase language, uppercase region).

---

## Active Locale & Fallback

The host sets the active locale at runtime (e.g. `setLocale("fr-CA")`); by default it follows the device. Number, date, and currency [formatting functions](variables.md#formatting-functions) also use the active locale, so `formatCurrency` / `formatDate` localize automatically.

When resolving a key, the engine tries each layer in order and stops at the first hit:

1. **Exact active locale** — e.g. `fr-CA`
2. **Language only** — e.g. `fr`
3. **Sibling region** — any other `fr-*` that has the key
4. **Host string bundle** — the app's `.xcstrings` / `Localizable` tables (host-shipped translations win over the server's default-locale rows)
5. **Default locale** — `defaultLocale` from the bundle

If every layer misses, the key string is shown.

> **Why bundle before default**: a host that ships a German `Localizable.xcstrings` should beat the server's English `defaultLocale` rows when the user picks German — otherwise the host bundle layer would never fire.

---

## See Also

- [host-integration.md](host-integration.md) — supplying the bundle via `getTranslations()`
- [variables.md → Formatting functions](variables.md#formatting-functions) — locale-aware number/date/currency formatting
- [analytics.md](analytics.md) — every engine event carries the active `locale` for slicing
