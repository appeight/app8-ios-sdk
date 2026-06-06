# Shape

Renders geometric shapes: arc progress rings, horizontal progress bars, filled/stroke circles, and divider lines. Animates `strokeEnd` when `progress` changes via CAShapeLayer.

## Content Properties

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `kind` | string | Yes | Shape kind: `arc`, `bar`, `circle`, `line`, `polyline` |
| `progress` | string | No | Variable expression `"{{var}}"` — maps 0.0–1.0 (clamped). **Must be a variable expression, not a literal string.** |
| `startAngle` | number | No | Arc start angle in degrees. `-90` = 12 o'clock (top). Default: `-90` |
| `lineWidth` | number | No | Stroke width in points. Default: `8` |
| `lineCap` | string | No | Line cap style: `round` (default), `butt`, `square` |
| `strokeColor` | string | No | Hex color for the progress stroke, e.g. `"#FF2D55"` or `"#FF2D55AA"` |
| `trackColor` | string | No | Hex color for the background track. Supports `#RRGGBBAA` for alpha. |
| `trackLineWidth` | number | No | Track stroke width. Defaults to `lineWidth` if not set |
| `fillColor` | string | No | Hex fill color for `circle` kind (solid fill inside the path) |
| `animationDuration` | number | No | Seconds to animate progress changes. Default: `0.4` |
| `animationCurve` | string | No | Timing curve: `easeOut` (default), `easeIn`, `easeInOut`, `linear` |
| `points` | Point[] | No | Vertices for `polyline` kind — see [Polyline](#polyline) |
| `smooth` | boolean | No | `polyline`: smooth the path with Catmull-Rom interpolation |
| `closed` | boolean | No | `polyline`: close the path back to the first point |
| `hidden` | boolean/expression | No | Hide component |

## Kind Reference

| Kind | Description | Key Properties |
|------|-------------|----------------|
| `arc` | Circular progress ring (donut) | `progress`, `startAngle`, `lineWidth`, `lineCap`, `strokeColor`, `trackColor`, `trackLineWidth` |
| `bar` | Horizontal progress bar | `progress`, `lineWidth`, `lineCap`, `strokeColor`, `trackColor` |
| `circle` | Solid fill or partial stroke circle | `fillColor` for solid; `strokeColor` + `progress` for partial stroke |
| `line` | Straight horizontal divider | `lineWidth`, `lineCap`, `strokeColor` |
| `polyline` | Connected path through points (sparklines, charts) | `points`, `smooth`, `closed`, `lineWidth`, `strokeColor`, `fillColor` |

## Polyline

A `polyline` draws a stroked path through `points`. Each point's `x`/`y` is `0..1` normalized to the shape's bounds, or `>1` for an absolute point value. Set `smooth` for a curved line and `closed` to close the path (with `fillColor`, makes a filled area).

| Field | Type | Description |
|-------|------|-------------|
| `x` | string | X: `0..1` normalized, or `>1` absolute. Literal or `"{{expr}}"` |
| `y` | string | Y: `0..1` normalized, or `>1` absolute. Literal or `"{{expr}}"` |

```json
{
  "type": "shape",
  "content": {
    "properties": {
      "kind": "polyline",
      "smooth": true,
      "strokeColor": "#34C759",
      "lineWidth": 2,
      "points": [
        { "x": "0", "y": "0.8" },
        { "x": "0.25", "y": "0.4" },
        { "x": "0.5", "y": "0.6" },
        { "x": "0.75", "y": "0.2" },
        { "x": "1", "y": "0.5" }
      ]
    },
    "layout": { "leading": 20, "trailing": 20, "height": 60 }
  }
}
```

## ⚠️ Progress Must Use Variables

`progress` only works with variable expressions `"{{varName}}"`. Literal number strings will not drive arc rendering. Always define a screen-level variable:

```json
{
  "type": "screen",
  "content": {
    "variables": {
      "ringProgress": { "type": "number", "initialValue": 0.75 }
    },
    "children": [
      {
        "id": "my-ring",
        "type": "shape",
        "content": {
          "properties": {
            "kind": "arc",
            "progress": "{{ringProgress}}",
            "startAngle": -90,
            "lineWidth": 14,
            "lineCap": "round",
            "strokeColor": "#FF2D55",
            "trackColor": "#FF2D5533",
            "animationDuration": 1.0,
            "animationCurve": "easeOut"
          },
          "layout": { "width": 120, "height": 120 }
        }
      }
    ]
  }
}
```

To animate the ring on load, start at `0` and use a timer event:

```json
"variables": {
  "ringProgress": { "type": "number", "initialValue": 0 }
},
"onEvent": [
  {
    "event": "timer",
    "delay": 0.3,
    "action": { "type": "updateVariable", "variableName": "ringProgress", "value": 0.75 }
  }
]
```

## Concentric Activity Rings (Apple Fitness style)

Nest three `shape` siblings inside a square `view`. The outer ring fills the container; inner rings use `centerX`/`centerY` constraints with smaller sizes:

```json
{
  "id": "rings-container",
  "type": "view",
  "content": {
    "layout": { "width": 130, "height": 130 },
    "children": [
      {
        "id": "move-ring",
        "type": "shape",
        "content": {
          "properties": { "kind": "arc", "progress": "{{moveP}}", "startAngle": -90, "lineWidth": 14, "lineCap": "round", "strokeColor": "#FF2D55", "trackColor": "#FF2D5533", "animationDuration": 1.0 },
          "layout": { "width": 130, "height": 130 }
        }
      },
      {
        "id": "exercise-ring",
        "type": "shape",
        "content": {
          "properties": { "kind": "arc", "progress": "{{exP}}", "startAngle": -90, "lineWidth": 14, "lineCap": "round", "strokeColor": "#30D158", "trackColor": "#30D15833", "animationDuration": 1.0 },
          "layout": { "width": 100, "height": 100, "constraints": [{ "type": "centerX", "target": "superview" }, { "type": "centerY", "target": "superview" }] }
        }
      },
      {
        "id": "stand-ring",
        "type": "shape",
        "content": {
          "properties": { "kind": "arc", "progress": "{{standP}}", "startAngle": -90, "lineWidth": 14, "lineCap": "round", "strokeColor": "#32ADE6", "trackColor": "#32ADE633", "animationDuration": 1.0 },
          "layout": { "width": 70, "height": 70, "constraints": [{ "type": "centerX", "target": "superview" }, { "type": "centerY", "target": "superview" }] }
        }
      }
    ]
  }
}
```

## Bar Example

```json
{
  "id": "progress-bar",
  "type": "shape",
  "content": {
    "properties": {
      "kind": "bar",
      "progress": "{{barP}}",
      "lineWidth": 20,
      "lineCap": "round",
      "strokeColor": "#FF9500",
      "trackColor": "#FF950033",
      "animationDuration": 1.0
    },
    "layout": { "width": 280, "height": 20 }
  }
}
```

## Circle Examples

Solid filled circle (`fillColor`, no progress needed):
```json
{
  "type": "shape",
  "content": {
    "properties": { "kind": "circle", "fillColor": "#30D158", "lineWidth": 0 },
    "layout": { "width": 40, "height": 40 }
  }
}
```

Partial stroke ring:
```json
{
  "type": "shape",
  "content": {
    "properties": { "kind": "circle", "strokeColor": "#30D158", "progress": "{{p}}", "lineWidth": 3 },
    "layout": { "width": 40, "height": 40 }
  }
}
```

## Line Example

```json
{
  "type": "shape",
  "content": {
    "properties": { "kind": "line", "lineWidth": 1, "lineCap": "butt", "strokeColor": "#FFFFFF33" },
    "layout": { "width": 320, "height": 1 }
  }
}
```
