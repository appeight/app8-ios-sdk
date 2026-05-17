# Button

Interactive tappable component.

## Content Properties

| Property | Type | Description |
|----------|------|-------------|
| `properties.text` | string | Button label |
| `properties.icon` | string | SF Symbol name `[Planned]` |
| `properties.isEnabled` | boolean/expression | Enable state `[Planned]` |
| `style` | ButtonStyle | Button styling |
| `layout` | Layout | Position and size |
| `actions` | Actions | Tap action |
| `states` | States | State definitions |
| `triggers` | Triggers | State triggers |
| `hidden` | boolean/expression | Hide component |

## Style: ButtonStyle

| Property | Type | Description |
|----------|------|-------------|
| `text` | TextModel | Text styling |
| `material` | Material | Background material |
| `alpha` | number | Opacity |

## Example

<!-- @dsl-type: Component -->
```json
{
  "type": "button",
  "content": {
    "properties": {
      "text": "Sign In",
      "isEnabled": "{{email.length > 0 && password.length > 0}}"
    },
    "style": {
      "material": [
        { "fill": { "solid": "#007AFF" } },
        { "corner": { "radius": 12, "curve": "continuous" } }
      ],
      "text": {
        "fontSize": 17,
        "fontWeight": "semibold",
        "color": "#FFFFFF"
      }
    },
    "layout": {
      "leading": 20,
      "trailing": 20,
      "height": 50
    },
    "actions": {
      "tap": { "type": "executeFunction", "function": "signIn" }
    }
  }
}
```

## Button with Icon [Planned]

<!-- @dsl-type: Component -->
```json
{
  "type": "button",
  "content": {
    "properties": {
      "icon": "heart.fill",
      "text": "Like"
    }
  }
}
```
