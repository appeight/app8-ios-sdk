# TextView

Multi-line text input.

## Content Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `properties.text` | string | | Initial text value |
| `properties.placeholder` | string | | Placeholder text |
| `properties.bindVariable` | string | | Variable for two-way binding |
| `properties.keyboardType` | KeyboardType | `default` | Keyboard type |
| `properties.textContentType` | TextContentType | | Autofill hint |
| `properties.returnKeyType` | ReturnKeyType | `default` | Return key label |
| `properties.autocapitalization` | Autocap | `sentences` | Auto-capitalization |
| `properties.autocorrection` | boolean | true | Auto-correction |
| `properties.maxLength` | number | | Max character count |
| `properties.isEnabled` | boolean | true | Enable input |
| `properties.scrollEnabled` | boolean | true | Enable scrolling |
| `properties.autoGrow` | boolean | false | Auto-expand height |
| `properties.minHeight` | number | | Minimum height when autoGrow |
| `properties.maxHeight` | number | | Maximum height when autoGrow |
| `hidden` | boolean/expression | | Hide component |

## Triggers

| Trigger | When |
|---------|------|
| `focus` | Field gains focus |
| `blur` | Field loses focus |

## Style: TextViewStyle

| Property | Type | Description |
|----------|------|-------------|
| `text` | TextModel | Input text styling |
| `placeholder` | TextModel | Placeholder styling |
| `tintColor` | Color | Cursor/selection color |
| `padding` | EdgeInsets | Content padding |
| `material` | Material | Background |

## Example

<!-- @dsl-type: Component -->
```json
{
  "type": "textView",
  "content": {
    "properties": {
      "placeholder": "Enter your notes...",
      "bindVariable": "notes",
      "autoGrow": true,
      "maxHeight": 200
    },
    "style": {
      "material": [
        { "fill": { "solid": "#F5F5F5" } },
        { "corner": { "radius": 8 } }
      ],
      "text": { "fontSize": 16, "color": "#333333" },
      "placeholder": { "fontSize": 16, "color": "#999999" },
      "padding": { "top": 12, "left": 12, "bottom": 12, "right": 12 }
    },
    "layout": {
      "leading": 20,
      "trailing": 20,
      "height": 120
    }
  }
}
```
