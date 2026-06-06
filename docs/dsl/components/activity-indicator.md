# ActivityIndicator

A native spinning loading indicator (`UIActivityIndicatorView`). Display-only — it has no actions.

Use it for indeterminate waits (a network call in flight). For content-shaped placeholders, prefer a [Shimmer](shimmer.md) skeleton.

## Content Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `properties.isAnimating` | boolean/expression | `false` | Whether the spinner spins. Accepts an expression, e.g. `"{{isLoading}}"` |
| `properties.hidesWhenStopped` | boolean | `true` | Hide the view entirely while not animating |
| `hidden` | boolean/expression | | Hide component |

> **Driving it**: bind `isAnimating` to a loading flag. With `hidesWhenStopped: true` (the default) the indicator both stops and disappears when the flag goes false, so you rarely need a separate `hidden`.

## Style: ActivityIndicatorStyle

| Property | Type | Description |
|----------|------|-------------|
| `indicatorStyle` | `medium` \| `large` | Spinner size (default `medium`) |
| `color` | Color (hex string) | Spinner tint color |
| `material` | Material | Background |
| `alpha` | number | Opacity (0.0–1.0) |
| `contentMode` | ContentMode | Content alignment |

## Example

```json
{
  "type": "activityIndicator",
  "id": "spinner",
  "content": {
    "properties": {
      "isAnimating": "{{isLoading}}"
    },
    "style": {
      "indicatorStyle": "large",
      "color": "#8E8E93"
    },
    "layout": { "centerX": 0, "centerY": 0 }
  }
}
```

## See Also

- [Shimmer](shimmer.md) — skeleton placeholders for content-shaped loading
- [Forms & Inputs → Loading states](../forms.md#loading-states)
