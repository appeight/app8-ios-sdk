# Button

Interactive tappable component.

## Content Properties

| Property | Type | Description |
|----------|------|-------------|
| `properties.text` | string | Button label |
| `properties.icon` | string | SF Symbol name `[Planned]` (for system buttons use `style.system.image`) |
| `properties.isEnabled` | expression → boolean | Enable state. Drives the system disabled appearance (or a dimmed alpha on the Material path). Defaults to `true`. |
| `properties.isSelected` | expression → boolean | Selected state (`UIButton.isSelected`). Defaults to `false`. |
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
| `material` | Material | Background material (custom appearance path) |
| `alpha` | number | Opacity |
| `system` | SystemButton | Native `UIButton.Configuration` styling. **When present, the button renders via the system path** — the system owns the background, corner shape, content insets, and the highlighted/disabled/selected appearance. The `material` background is ignored in this mode (use one or the other); `alpha`/`transform`/`shadow`/`layout` still apply. See below. |

## Style: SystemButton (native)

Adding a `system` block to a button's `style` switches it from the Material path to a
native `UIButton.Configuration`. This gives the real system look — including the iOS 26
glassy capsule — with automatic state appearance, system content insets, and SF-Symbol +
title layout, without rebuilding any of it by hand.

| Property | Type | Values / Description |
|----------|------|----------------------|
| `variant` | enum | `plain`, `gray`, `tinted`, `filled`, `bordered`, `borderedTinted`, `borderedProminent`, `glass`, `prominentGlass`. Defaults to `filled`. `glass`/`prominentGlass` require iOS 26 and degrade to `filled`/`borderedProminent` below it. |
| `cornerStyle` | enum | `dynamic`, `fixed`, `capsule`, `large`, `medium`, `small`. `capsule` gives the pill shape. |
| `size` | enum | `mini`, `small`, `medium`, `large`. |
| `role` | enum | `normal`, `primary`, `cancel`, `destructive` — system semantic colouring (iOS 26). |
| `tint` | Color | Overall tint → `baseBackgroundColor` (+ `tintColor`). Accepts a hex or a themed `{ light, dark }` color. |
| `foreground` | Color | Title/image colour → `baseForegroundColor`. |
| `image` | `{ type, name }` | SF Symbol (`type: "symbol"`) or asset (`type: "asset"`). |
| `imagePlacement` | enum | `leading`, `trailing`, `top`, `bottom`. |
| `imagePadding` | number | Gap between image and title. |
| `subtitle` | string/expression | Optional secondary line. |
| `showsActivityIndicator` | expression → boolean | Replaces the title with a spinner when true (e.g. `"{{loading}}"`). |

Unknown enum values degrade gracefully to the default case rather than failing the screen.

### Glass capsule with tint

<!-- @dsl-type: Component -->
```json
{
  "type": "button",
  "content": {
    "properties": { "text": "Continue" },
    "style": {
      "system": {
        "variant": "glass",
        "cornerStyle": "capsule",
        "size": "large",
        "tint": "#007AFF"
      }
    },
    "layout": { "leading": 20, "trailing": 20, "height": 50 },
    "actions": { "tap": { "type": "executeFunction", "function": "continue" } }
  }
}
```

### Prominent primary with leading icon

<!-- @dsl-type: Component -->
```json
{
  "type": "button",
  "content": {
    "properties": { "text": "Add to cart", "isEnabled": "{{inStock}}" },
    "style": {
      "system": {
        "variant": "borderedProminent",
        "cornerStyle": "medium",
        "role": "primary",
        "image": { "type": "symbol", "name": "cart.fill" },
        "imagePlacement": "leading",
        "imagePadding": 8
      }
    }
  }
}
```

### Destructive, with loading spinner

<!-- @dsl-type: Component -->
```json
{
  "type": "button",
  "content": {
    "properties": { "text": "Delete", "isSelected": "{{confirming}}" },
    "style": {
      "system": {
        "variant": "tinted",
        "role": "destructive",
        "tint": "#FF3B30",
        "subtitle": "This cannot be undone",
        "showsActivityIndicator": "{{deleting}}"
      }
    },
    "actions": { "tap": { "type": "executeFunction", "function": "delete" } }
  }
}
```

## Example

<!-- @dsl-type: Component -->
```json
{
  "type": "button",
  "content": {
    "properties": {
      "text": "Sign In"
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
