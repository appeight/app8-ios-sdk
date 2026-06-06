# Shimmer

A skeleton-loading container that sweeps a shimmering gradient across its children while content is loading. Wrap placeholder shapes in a shimmer to show the *shape* of upcoming content instead of a bare spinner.

## Content Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `properties.isAnimating` | boolean/expression | `false` | Whether the shimmer sweep is active. Accepts an expression, e.g. `"{{isLoading}}"` |
| `properties.duration` | number | `1.5` | Seconds for one shimmer pass |
| `properties.direction` | Direction | `leftToRight` | Sweep direction |
| `children` | Component[] | | Placeholder components the shimmer is applied over |
| `hidden` | boolean/expression | | Hide component |

## Direction Values

| Value | Sweep |
|-------|-------|
| `leftToRight` | Left → right (default) |
| `rightToLeft` | Right → left |
| `topToBottom` | Top → bottom |

## How to Use It

Build a placeholder that mirrors the real layout — same box sizes and corner radii — give those boxes a neutral fill, and toggle the whole shimmer with your loading flag. Swap it for the real content once loaded (e.g. with a `hidden` expression on each).

## Example

A skeleton card shown while a profile loads:

```json
{
  "type": "shimmer",
  "id": "profileSkeleton",
  "content": {
    "properties": {
      "isAnimating": "{{isLoading}}",
      "direction": "leftToRight"
    },
    "hidden": "{{!isLoading}}",
    "children": [
      {
        "type": "view",
        "content": {
          "style": {
            "material": {
              "id": "avatarSkeleton", "type": "material",
              "content": [
                { "id": "f", "type": "fill", "content": { "solid": "#E5E5EA" } },
                { "id": "c", "type": "corner", "content": { "radius": "50%" } }
              ]
            }
          },
          "layout": { "leading": 20, "top": 20, "width": 56, "height": 56 }
        }
      },
      {
        "type": "view",
        "content": {
          "style": {
            "material": {
              "id": "lineSkeleton", "type": "material",
              "content": [
                { "id": "f2", "type": "fill", "content": { "solid": "#E5E5EA" } },
                { "id": "c2", "type": "corner", "content": { "radius": 6 } }
              ]
            }
          },
          "layout": { "leading": 88, "top": 28, "width": 160, "height": 14 }
        }
      }
    ]
  }
}
```

## See Also

- [ActivityIndicator](activity-indicator.md) — a simple spinner for indeterminate waits
- [Forms & Inputs → Loading states](../forms.md#loading-states)
- [styles.md → Material](../styles.md#material) — building the neutral placeholder boxes
