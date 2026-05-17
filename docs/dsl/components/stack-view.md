# StackView

Linear layout container backed by `UIStackView`. Arranges children along a single axis without requiring position constraints on each child.

> **Layout constraint:** Position along the main axis and cross-axis alignment are managed by the stack itself — children should not declare position. The only layout fields that take effect on a direct child of a `stackView` are:
>
> - Top-level `width` / `height` shorthand.
> - `constraints[]` entries with `type: width` or `type: height` — including self-dimension clamps (omit `target`) and sibling-dimension equality (`target: "<sibling-id>"`, `attribute: "width|height"`). These enable priority-bearing flexible spacers and lockstep-equal sibling sizes inside a stack — see [Layout · Constraints in UIStackView Arranged Subviews](../layout.md#constraints-in-uistackview-arranged-subviews).

## Content Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `properties.axis` | string | `"vertical"` | Stack direction: `"vertical"` or `"horizontal"` |
| `properties.spacing` | number | `0` | Points of space between arranged subviews |
| `properties.alignment` | string | `"fill"` | Cross-axis alignment (see below) |
| `properties.distribution` | string | `"fill"` | How children fill the stack axis (see below) |
| `properties.backgroundColor` | string | transparent | Hex color behind all children, e.g. `"#1C1C1E"` |
| `properties.cornerRadius` | number | none | Corner radius in points; clips children to rounded bounds |
| `children` | Component[] | | Arranged subviews |
| `style` | ViewStyle | | Container styling (material, alpha, etc.) |
| `layout` | Layout | | Position and size of the stack itself |
| `hidden` | boolean/expression | | Hide component |

## Alignment Values

| Value | Description |
|-------|-------------|
| `fill` | Stretch children to fill the cross axis (default) |
| `center` | Center children on the cross axis |
| `top` | Align to top (horizontal stack) |
| `bottom` | Align to bottom (horizontal stack) |
| `leading` | Align to leading edge (vertical stack) |
| `trailing` | Align to trailing edge (vertical stack) |

## Distribution Values

| Value | Description |
|-------|-------------|
| `fill` | First child fills extra space (default) |
| `fillEqually` | All children get equal size |
| `fillProportionally` | Children fill proportionally to intrinsic size |
| `equalSpacing` | Equal spacing between children |
| `equalCentering` | Equal center-to-center distance |

## Example — Vertical Stack

```json
{
  "type": "stackView",
  "content": {
    "properties": {
      "axis": "vertical",
      "spacing": 12
    },
    "layout": {
      "width": 280,
      "constraints": [
        { "type": "centerX", "target": "superview" },
        { "type": "centerY", "target": "superview" }
      ]
    },
    "children": [
      {
        "id": "row1",
        "type": "label",
        "content": { "properties": { "text": "First Item" } }
      },
      {
        "id": "row2",
        "type": "label",
        "content": { "properties": { "text": "Second Item" } }
      }
    ]
  }
}
```

## Example — Horizontal Stack

```json
{
  "type": "stackView",
  "content": {
    "properties": {
      "axis": "horizontal",
      "spacing": 16,
      "alignment": "center",
      "distribution": "equalSpacing"
    },
    "layout": {
      "width": 300,
      "height": 60,
      "constraints": [
        { "type": "centerX", "target": "superview" },
        { "type": "centerY", "target": "superview" }
      ]
    },
    "children": [
      {
        "id": "icon",
        "type": "icon",
        "content": {
          "properties": { "type": "symbol", "name": "star.fill" },
          "layout": { "width": 24, "height": 24 }
        }
      },
      {
        "id": "label",
        "type": "label",
        "content": { "properties": { "text": "Horizontal Stack" } }
      }
    ]
  }
}
```
