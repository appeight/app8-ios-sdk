# Label

Text display component.

## Content Properties

| Property | Type | Description |
|----------|------|-------------|
| `properties.text` | string \| LocalizedString | Text content. A plain string (supports `{{expressions}}`) or the `{"$i18n": "key"}` localization marker — see [localization.md](../localization.md) |
| `properties.numberOfLines` | number | Max lines (`0` = unlimited). Also settable via the text style |
| `properties.backgroundColor` | color/expression | Background color. Accepts an expression or the wrapped `{ value, animation }` form |
| `properties.isHidden` | boolean/expression | Hide via expression, e.g. `"{{!isChecked}}"` |
| `properties.spans` | Span[] | Inline rich-text overrides on character ranges — see [Spans](#spans) |
| `style` | LabelStyle | Text styling |
| `layout` | Layout | Position and size |
| `states` | States | State definitions |
| `hidden` | boolean/expression | Hide component |

## Spans

`spans` apply per-character-range style overrides on top of the base text style — for a colored keyword or a different font on one word, without splitting into sibling labels.

| Field | Type | Description |
|-------|------|-------------|
| `from` | number | Start index (inclusive, UTF-16 offset) |
| `to` | number | End index (exclusive) |
| `fontFamily` | string | Font family override for the range |
| `color` | string | Hex color override for the range |

Out-of-range indices are clamped silently. For ASCII/BMP text the offsets match character positions.

```json
{
  "type": "label",
  "content": {
    "properties": {
      "text": "Total: $42.00",
      "spans": [
        { "from": 7, "to": 13, "color": "#34C759", "fontFamily": "Menlo" }
      ]
    }
  }
}
```

## Style: LabelStyle

| Property | Type | Description |
|----------|------|-------------|
| `text` | TextModel | Typography styling |
| `material` | Material | Background material |
| `alpha` | number | Opacity (0.0-1.0) |

## Example

<!-- @dsl-type: Component -->
```json
{
  "type": "label",
  "content": {
    "properties": {
      "text": "Hello, {{userName}}!"
    },
    "style": {
      "text": {
        "fontSize": 24,
        "fontWeight": "bold",
        "color": "#333333",
        "alignment": "center"
      }
    },
    "layout": {
      "leading": 20,
      "trailing": 20,
      "top": 50
    }
  }
}
```
