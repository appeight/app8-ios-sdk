# Gestures

`content.gestures` binds **continuous** interaction quantities to variables. It
sits alongside `actions` but is a different concept:

| | `actions` | `gestures` |
|---|---|---|
| Fires | a one-shot **action** (navigate, setVariable, emit…) | a continuous **variable write** |
| Trigger | discrete recognition (`tap`, `longPress`) | a dragging recognizer (`pan`) |
| Output | runs an `Action` | streams raw numbers into variables |

A gesture is a **raw primitive**: it emits geometry-free quantities (translation,
velocity, location) and writes them straight into variables. Turning those into a
meaningful value — a slider "progress", a parallax offset, a rubber-band amount —
is **your** job, expressed with an [expression](variables.md) or a
[computed variable](variables.md), not baked into the gesture. This keeps the
primitive generic: the same `pan` drives sliders, knobs, scrubbers, drag-to-set
dials, and anything else.

> The binding convention is the same one used by `scrollOffsetVariable` and
> [`bindVariable`](forms.md): each value is a **bare variable name** (no `{{ }}`),
> and the engine writes to it as the interaction updates.

## `pan`

A drag recognizer. Every field is optional — only the variables you name get
written. Values are in the gesture view's own coordinate space.

| Field | Writes | Units |
|-------|--------|-------|
| `translationX` / `translationY` | cumulative drag since it began | points |
| `velocityX` / `velocityY` | current drag velocity | points / second |
| `locationX` / `locationY` | touch position within the view's bounds | points |

```json
"content": {
  "gestures": {
    "pan": { "locationY": "dragY", "velocityY": "flingVelocity" }
  }
}
```

A `pan` that binds `locationX`/`locationY` also responds to a **tap** (a tap is a
zero-distance drag), so tap-to-set works for free. The recognizer coexists with an
`actions.tap` on the same component.

> **Where it applies:** `gestures` is recognized on `view` components (and anything
> built on the view container). It is accepted but inert on specialized components
> like `collection` and `map`, which manage their own gestures — declare the
> `gestures` block on a wrapping `view` instead.

> **Future:** `pinch`, `swipe`, and `rotate` slot in beside `pan` as additional
> recognizers under `gestures`.

## Recipe: a custom vertical slider (glass brightness capsule)

This is the canonical example of composing a bespoke control from primitives — **no
custom component needed**. A glass capsule whose fill rises from the bottom and whose
value you drag or tap to set:

```json
{
  "type": "screen",
  "id": "brightness-demo",
  "content": {
    "variables": {
      "dragY": { "type": "number", "initialValue": 100 },
      "brightness": { "type": "number", "computed": "{{ max(0, min(100, (200 - dragY) / 2)) }}" }
    },
    "children": [
      {
        "id": "capsule",
        "type": "view",
        "content": {
          "gestures": { "pan": { "locationY": "dragY" } },
          "style": {
            "material": [
              { "id": "g", "type": "visualEffect", "content": { "glass": "normal", "container": true } },
              { "id": "c", "type": "corner", "content": { "radius": "capsule" } }
            ]
          },
          "layout": {
            "constraints": [
              { "type": "centerX", "target": "superview" },
              { "type": "centerY", "target": "superview" },
              { "type": "width", "constant": 90 },
              { "type": "height", "constant": 200 }
            ]
          },
          "children": [
            {
              "id": "fill",
              "type": "view",
              "content": {
                "style": { "material": [ { "id": "f", "type": "fill", "content": { "solid": "#EAF4FFE6" } } ] },
                "layout": {
                  "height": "{{ brightness * 2 }}",
                  "constraints": [
                    { "type": "leading", "target": "superview" },
                    { "type": "trailing", "target": "superview" },
                    { "type": "bottom", "target": "superview" }
                  ]
                }
              }
            },
            {
              "id": "sun",
              "type": "icon",
              "content": {
                "properties": { "type": "symbol", "name": "sun.max.fill" },
                "style": { "symbolFontSize": 28, "color": "#FFC400" },
                "layout": { "constraints": [
                  { "type": "centerX", "target": "superview" },
                  { "type": "bottom", "target": "superview", "constant": -24 }
                ] }
              }
            }
          ]
        }
      }
    ]
  }
}
```

How the pieces fit:

1. **Drag input** — `gestures.pan` writes the raw touch Y (`dragY`, 0 at top) on the
   capsule. Dragging *or* tapping updates it.
2. **Mapping (your UX, at the component level)** — `brightness` is a
   [computed variable](variables.md): `(200 - dragY) / 2`, clamped to 0–100. The `200`
   is the capsule's known height. (For a flexibly-sized control, reference
   [`view.height`](variables.md) instead of a literal.)
3. **Fill from the bottom** — the `fill` child's `height` expression `{{ brightness * 2 }}`
   re-resolves whenever `brightness` changes, growing the fill up from the pinned bottom.
4. **Glass that morphs** — `container: true` hosts the fill + icon *inside* the glass, and
   `"radius": "capsule"` gives the true glass capsule edge.
5. **React elsewhere** — anything bound to `{{ brightness }}` (an overlay's `alpha`, a label)
   updates live as you drag.

See [styles.md](styles.md#glass-as-a-content-container) for container glass and
[variables.md](variables.md) for computed variables and `view.*` geometry.
