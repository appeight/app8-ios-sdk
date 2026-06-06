# ScrollView

Scrollable container.

## Content Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `properties.direction` | Direction | `vertical` | Scroll direction |
| `properties.showsIndicator` | boolean | true | Show scroll indicator |
| `properties.outputVariable` | string | | Variable to write scroll offset to (0 at rest, positive when scrolled) |
| `properties.contentInsetAdjustment` | ContentInsetAdjustment | `automatic` | How iOS adjusts content insets for safe areas |
| `properties.contentInset` | EdgeInsets | | Explicit padding around the scroll content |
| `properties.autoScroll` | AutoScroll | | Continuous auto-scroll / marquee — see [Auto-scroll](#auto-scroll) |
| `children` | Component[] | | Content components |
| `style` | ScrollViewStyle | | Styling |
| `layout` | Layout | | Position and size |
| `hidden` | boolean/expression | | Hide component |

## Direction Values

`vertical`, `horizontal`

## ContentInsetAdjustment Values

| Value | Description |
|-------|-------------|
| `automatic` | Default. iOS adjusts content insets for safe areas (nav bar, tab bar, etc.). Matches UIKit default. |
| `never` | No automatic inset adjustment. Use when the DSL fully controls layout — e.g., full-screen scroll views with a hidden or transparent nav bar. |

> **Note:** Use `never` for screens with `navigationBar.hidden: true` and `ignoresSafeArea: true` where the content is intended to fill the full screen (e.g., a photo/hero scroll).
> Without `never`, the second-visit nav bar transition can cause a visible content jump.

## outputVariable

When set, the variable receives the current scroll offset as a number:
- `0` at the natural resting position (top for vertical, left for horizontal)
- Positive when scrolled — e.g., `120` means 120pt scrolled from the top

Use this to drive animations (parallax, sticky headers, fading nav bars, etc.) via expressions.

## Auto-scroll

`autoScroll` drives the content offset every frame for marquee/ticker effects (scrolling banners, "now playing" strips, logo reels). Pair it with `direction: "horizontal"` for a classic marquee.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `speed` | number | | Points per second along the scroll axis. Positive scrolls toward the trailing edge (right/down); negative reverses |
| `infinite` | boolean | `true` | Duplicate the content so the loop wraps seamlessly. `false` = one-shot, stops at the trailing edge |
| `loopGap` | number | `0` | Gap (points) inserted between the original content and its duplicate — match your item spacing so the wrap looks even |

```json
{
  "type": "scrollView",
  "content": {
    "properties": {
      "direction": "horizontal",
      "showsIndicator": false,
      "autoScroll": { "speed": 30, "infinite": true, "loopGap": 30 }
    },
    "children": []
  }
}
```

## Style: ScrollViewStyle

| Property | Type | Description |
|----------|------|-------------|
| `material` | Material | Background material |
| `alpha` | number | Opacity (0.0–1.0) |

## Example — basic vertical scroll

```json
{
  "type": "scrollView",
  "content": {
    "properties": {
      "direction": "vertical",
      "showsIndicator": true
    },
    "layout": {
      "constraints": [
        { "type": "top", "target": "superview" },
        { "type": "leading", "target": "superview" },
        { "type": "trailing", "target": "superview" },
        { "type": "bottom", "target": "superview" }
      ]
    },
    "children": []
  }
}
```

## Example — scroll with outputVariable (parallax / sticky header)

```json
{
  "variables": {
    "scrollOffset": { "type": "number", "initialValue": 0 }
  },
  "children": [
    {
      "type": "scrollView",
      "content": {
        "properties": {
          "direction": "vertical",
          "outputVariable": "scrollOffset"
        },
        "layout": { ... },
        "children": [...]
      }
    },
    {
      "type": "view",
      "content": {
        "style": { "alpha": "{{1 - scrollOffset / 100}}" }
      }
    }
  ]
}
```

## Example — scroll under opaque navigation bar

```json
{
  "type": "scrollView",
  "content": {
    "properties": {
      "direction": "vertical",
      "contentInsetAdjustment": "automatic"
    },
    "layout": { ... },
    "children": [...]
  }
}
```
