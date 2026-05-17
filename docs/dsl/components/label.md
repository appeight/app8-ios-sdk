# Label

Text display component.

## Content Properties

| Property | Type | Description |
|----------|------|-------------|
| `properties.text` | string | Text content (supports expressions) |
| `style` | LabelStyle | Text styling |
| `layout` | Layout | Position and size |
| `states` | States | State definitions |
| `hidden` | boolean/expression | Hide component |

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
