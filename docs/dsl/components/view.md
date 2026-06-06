# View

General-purpose container for grouping and layout.

## Content Properties

| Property | Type | Description |
|----------|------|-------------|
| `children` | Component[] | Child components |
| `style` | ViewStyle | View styling |
| `layout` | Layout | Position and size |
| `actions` | Actions | Tap actions |
| `states` | States | State definitions |
| `triggers` | Triggers | State triggers |
| `hidden` | boolean/expression | Hide component |

## Style: ViewStyle

| Property | Type | Description |
|----------|------|-------------|
| `material` | Material | Background material |
| `alpha` | number | Opacity (0.0-1.0) |
| `contentMode` | ContentMode | Content alignment |
| `transform` | Transform | View transform |

## ContentMode Values

| Value | Description |
|-------|-------------|
| `scaleToFill` | Stretch to fill |
| `scaleAspectFit` | Fit maintaining aspect ratio |
| `scaleAspectFill` | Fill maintaining aspect ratio |
| `center` | Center without scaling |

See [styles.md → ContentMode Values](../styles.md#contentmode-values) for the full list (edge and corner alignments).

## Example

```json
{
  "type": "view",
  "content": {
    "style": {
      "material": [
        { "fill": { "solid": "#FFFFFF" } },
        { "corner": { "radius": 12, "curve": "continuous" } }
      ],
      "alpha": 1.0
    },
    "layout": {
      "leading": 16,
      "trailing": 16,
      "height": 100
    },
    "children": [ ]
  }
}
```
