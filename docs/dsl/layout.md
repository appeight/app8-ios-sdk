# Layout

Layout defines component position and size using dimension properties or explicit constraints.

## Layout Structure

```json
{
  "layout": {
    "width": 200,
    "height": 50,
    "leading": 20,
    "trailing": 20,
    "top": 100,
    "bottom": null,
    "ignoresSafeArea": false,
    "constraints": [],
    "contentHuggingPriority": { "h": "defaultLow", "v": "defaultHigh" },
    "contentCompressionResistancePriority": { "h": "required", "v": "defaultHigh" }
  }
}
```

| Field | Description |
|-------|-------------|
| `width`, `height` | Dimension shorthand. See [Dimensions](#dimensions). |
| `leading`, `trailing`, `top`, `bottom` | Edge inset shorthand to parent. See [Position Properties](#position-properties). |
| `ignoresSafeArea` | When true, `top` is measured from the screen edge instead of the safe area. |
| `constraints` | Array of explicit constraints. See [Constraints](#constraints). |
| `contentHuggingPriority` | Per-axis hugging priority (resistance to growing past intrinsic). See [Hugging & Compression Resistance](#hugging--compression-resistance). |
| `contentCompressionResistancePriority` | Per-axis compression-resistance priority (resistance to shrinking below intrinsic). |

---

## Dimensions

Three types of dimension values:

| Type | Format | Example | Description |
|------|--------|---------|-------------|
| Fixed | number | `100` | Absolute value in points |
| Fraction | string | `"50%"` | Relative to parent |
| Expression | string | `"{{var}}"` | Variable-based |

### Fixed Dimensions

```json
{
  "layout": {
    "width": 200,
    "height": 50
  }
}
```

### Relative Dimensions

```json
{
  "layout": {
    "width": "80%",
    "height": "50%"
  }
}
```

### Expression Dimensions

```json
{
  "layout": {
    "width": "{{containerWidth - padding * 2}}",
    "height": "{{isExpanded ? 200 : 50}}"
  }
}
```

---

## Position Properties

Position relative to parent view.

| Property | Description |
|----------|-------------|
| `leading` | Distance from left edge |
| `trailing` | Distance from right edge |
| `top` | Distance from top edge |
| `bottom` | Distance from bottom edge |

> **Note:** For centering, use constraints with `centerX` and `centerY` attributes. See [Constraints](#constraints) section.

### Horizontal Centering

Set both `leading` and `trailing` to the same value:

```json
{
  "layout": {
    "leading": 20,
    "trailing": 20,
    "width": 200
  }
}
```

### Full Width with Margins

```json
{
  "layout": {
    "leading": 16,
    "trailing": 16
  }
}
```

### Positioned from Top

```json
{
  "layout": {
    "leading": 20,
    "trailing": 20,
    "top": 100,
    "height": 50
  }
}
```

### Positioned from Bottom

```json
{
  "layout": {
    "leading": 20,
    "trailing": 20,
    "bottom": 20,
    "height": 50
  }
}
```

---

## Size Properties

| Property | Description |
|----------|-------------|
| `width` | Component width |
| `height` | Component height |

### Intrinsic Size

Omit width/height for intrinsic sizing (label, button):

```json
{
  "type": "label",
  "content": {
    "properties": { "text": "Hello" },
    "layout": {
      "top": 100,
      "leading": 20
    }
  }
}
```

### Fixed Size

```json
{
  "layout": {
    "width": 200,
    "height": 50
  }
}
```

---

## Hugging & Compression Resistance

Auto Layout uses two per-axis priorities to decide which views grow or shrink when the parent has slack or overflow. They only have an effect on views that have an **intrinsic content size** (labels, images, icons, buttons, text fields, stack views with intrinsic-sized children, etc.).

| Property | Direction | Meaning |
|----------|-----------|---------|
| `contentHuggingPriority` | Resists growing past intrinsic | Higher = view stays close to intrinsic when there's slack |
| `contentCompressionResistancePriority` | Resists shrinking below intrinsic | Higher = view holds its intrinsic when there's overflow |

Each takes an object with `h` (horizontal axis) and/or `v` (vertical axis), values from the [Priorities table](#priorities).

```json
{
  "layout": {
    "contentHuggingPriority": { "h": "defaultLow", "v": "defaultHigh" },
    "contentCompressionResistancePriority": { "v": "required" }
  }
}
```

Either axis is optional — only specified axes are written; unspecified axes keep UIKit defaults (e.g. `UILabel`'s vertical hugging stays at 250).

### When you'd use it

When a vertical stack has slack to distribute, AL grows whichever arranged subview has the **lowest** vertical hugging. To stop a content view (label, image, etc.) from being stretched and instead push the slack into spacers, raise that content view's `contentHuggingPriority.v` above the spacers' equality priority.

```json
"headlineGroup": { "layout": { "contentHuggingPriority": { "v": "defaultHigh" } } }
```

Combined with a spacer that uses `= preferred @ defaultLow`, AL prefers stretching the spacer (cost 250) over breaking the group's hugging (cost 750). Same idea in reverse for `contentCompressionResistancePriority` under overflow.

### Wrappers and intrinsic content size

Each component wrapper in the engine forwards its `intrinsicContentSize` from its inner UIKit element (label, button, image view, stack view, etc.). That means hugging / CR priorities applied to the wrapper actually defend a real number when an ancestor stack distributes space — they aren't no-ops on the wrapper level.

Generic containers (`view`, `scrollView`, `collection`, `tableView`, `map`) intentionally have *no* intrinsic content size, so hugging / CR priorities on those have no effect unless the container's height or width is otherwise driven by constraints. Use sibling-dimension equality or self-dimension constraints when you need to pin a generic container's size.

---

## Constraints

For complex layouts, use explicit constraints.

### Constraint Structure

<!-- @dsl-skip: constraint structure placeholder -->
```json
{
  "type": "attributeName",
  "target": "targetType",
  "attribute": "targetAttribute",
  "constant": 0,
  "multiplier": 1.0,
  "op": "=",
  "priority": "required"
}
```

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `type` | Attribute | Yes | Attribute to constrain |
| `target` | Target | No | What to constrain to. **Omit** for a self-dimension constraint (only valid when `type` is `width` or `height`) |
| `attribute` | Attribute | No | Target's attribute (defaults to same as `type`) |
| `constant` | number | No | Offset value |
| `multiplier` | number | No | Multiplier for relative constraints |
| `op` | Relation | No | Relation between the two sides: `"="` (default), `"<="`, `">="` |
| `priority` | Priority | No | Constraint priority (default: required). See [Priorities](#priorities) |

### Attributes

| Value | Description |
|-------|-------------|
| `leading` | Left edge |
| `trailing` | Right edge |
| `top` | Top edge |
| `bottom` | Bottom edge |
| `centerX` | Horizontal center |
| `centerY` | Vertical center |
| `width` | Width dimension |
| `height` | Height dimension |

### Targets

| Value | Description |
|-------|-------------|
| `superview` | Parent view |
| `safeArea` | Screen safe area layout guide |
| `sibling(id)` | Another component by ID |
| `keyboard` | Keyboard frame |

### Relations (`op`)

Default is `"="` (equality). The two inequality operators turn a constraint into a one-sided bound, which AL must respect but is free to satisfy with any value on the allowed side. Combine equality at low priority with an inequality at required priority to express "prefer X, but at least/at most Y."

| `op` | Meaning |
|------|---------|
| `"="` (default) | Equality — `a == b + constant` |
| `">="` | Greater-than-or-equal — `a >= b + constant` |
| `"<="` | Less-than-or-equal — `a <= b + constant` |

```json
{ "type": "height", "constant": 16, "op": ">=" }
{ "type": "height", "constant": 50, "priority": "defaultLow" }
```

The first installs `self.height >= 16 @ required` (a non-negotiable floor). The second installs `self.height = 50 @ defaultLow` (a preferred height that AL can break under pressure). Together they describe a flexible spacer.

### Priorities

Constraint priorities decide which constraints AL keeps satisfied first when there's a conflict. Lower-priority constraints break before higher-priority ones.

A priority value is either a **named** string or a **raw number**:

| Named | Numeric | Use for |
|-------|---------|---------|
| `"required"` | `1000` | Must be satisfied (default if `priority` is omitted) |
| `"defaultHigh"` | `750` | Strong preference — used by default UILabel CR and similar |
| `"defaultLow"` | `250` | Weak preference — default UIView hugging |
| `"fittingSizeLevel"` | `50` | Used for `systemLayoutSizeFitting` direction |
| `"dragThatCanResizeScene"` | `510` | macOS resize-while-dragging |
| `"dragThatCannotResizeScene"` | `490` | macOS drag without resize |
| `"sceneSizeStayPut"` | `500` | macOS scene size lock |
| any number | `e.g. 500` | Custom priority in `1…1000` |

```json
{ "type": "height", "constant": 50, "priority": "defaultHigh" }
{ "type": "height", "constant": 50, "priority": 500 }
```

### Self-Dimension Constraints

Omit `target` to constrain `width` or `height` of the view to a constant — useful for min/max clamps and priority-bearing preferred sizes.

```json
{
  "layout": {
    "constraints": [
      { "type": "height", "constant": 16, "op": ">=" },
      { "type": "height", "constant": 50, "priority": "defaultLow" }
    ]
  }
}
```

This view's height stays in `[16, ∞)`, prefers `50`, and yields toward the floor under pressure.

### Sibling Dimension Equality

Use a sibling target with `width` or `height` to match dimensions across components.

```json
{
  "layout": {
    "constraints": [
      { "type": "height", "target": "safeCard", "attribute": "height" }
    ]
  }
}
```

This pins `self.height == safeCard.height @ required`. Combined with content-driven sizing on the target, it makes two siblings stay visually equal without hardcoding a value.

---

## Common Constraint Patterns

### Center in Parent

```json
{
  "layout": {
    "constraints": [
      { "type": "centerX", "target": "superview" },
      { "type": "centerY", "target": "superview" }
    ],
    "width": 200,
    "height": 100
  }
}
```

### Below Another Component

```json
{
  "layout": {
    "constraints": [
      { "type": "top", "target": "sibling(titleLabel)", "attribute": "bottom", "constant": 16 }
    ],
    "leading": 20,
    "trailing": 20
  }
}
```

### Above Keyboard

```json
{
  "layout": {
    "constraints": [
      { "type": "bottom", "target": "keyboard", "constant": -16 }
    ],
    "leading": 20,
    "trailing": 20,
    "height": 50
  }
}
```

The component stays 16pt above the keyboard. When keyboard is hidden, it uses the view's bottom safe area.

### Align with Sibling

```json
{
  "layout": {
    "constraints": [
      { "type": "leading", "target": "sibling(avatar)", "attribute": "trailing", "constant": 12 },
      { "type": "centerY", "target": "sibling(avatar)" }
    ]
  }
}
```

### Priority-Bearing Gap (Flexible Spacer)

A spacer view with a hard floor and a low-priority preferred height. AL holds the preferred value when there's slack and shrinks toward the floor under overflow.

```json
{
  "id": "spacerA",
  "type": "view",
  "content": {
    "properties": {},
    "layout": {
      "constraints": [
        { "type": "height", "constant": 16, "op": ">=" },
        { "type": "height", "constant": 50, "priority": "defaultLow" }
      ]
    }
  }
}
```

Lock multiple spacers to the same value with sibling-dimension equality so they grow and shrink in lockstep:

```json
{
  "id": "spacerB",
  "type": "view",
  "content": {
    "properties": {},
    "layout": {
      "constraints": [
        { "type": "height", "constant": 16, "op": ">=" },
        { "type": "height", "constant": 50, "priority": "defaultLow" },
        { "type": "height", "target": "spacerA", "attribute": "height" }
      ]
    }
  }
}
```

### Match Sibling Height

Use to make two side-by-side views (e.g. cards in a row) visually equal regardless of which one's content is taller. The taller view drives its own height through its content chain; the shorter sibling matches via the equality and absorbs the surplus internally (e.g. via a flexible spacer at the bottom of its content stack).

```json
{
  "layout": {
    "constraints": [
      { "type": "height", "target": "safeCard", "attribute": "height" }
    ]
  }
}
```

---

## Constraints in UIStackView Arranged Subviews

When a view is an arranged subview of a `stackView`, the stack manages its position automatically. Sizing along the cross axis follows the stack's `alignment`; sizing along the main axis follows its `distribution`. The layout fields that take effect on the child are:

- Top-level `width` / `height` shorthand.
- `constraints[]` entries with `type: width` or `type: height` — both self-dimension clamps (omit `target`) and sibling-dimension equality (`target: "<sibling-id>"`, `attribute: "width|height"`).

This is what enables priority-bearing flexible spacers and lockstep-equal sibling sizes inside a stack:

```json
{
  "id": "rootStack",
  "type": "stackView",
  "content": {
    "properties": { "axis": "vertical", "alignment": "fill", "spacing": 0 },
    "children": [
      { "id": "header", "type": "view", "content": { "properties": {} } },
      {
        "id": "spacer",
        "type": "view",
        "content": {
          "properties": {},
          "layout": {
            "constraints": [
              { "type": "height", "constant": 16, "op": ">=" },
              { "type": "height", "constant": 50, "priority": "defaultLow" }
            ]
          }
        }
      },
      { "id": "footer", "type": "view", "content": { "properties": {} } }
    ]
  }
}
```

---

## Safe Area

Control how components interact with safe areas (notch, home indicator).

### Respect Safe Area (Default)

```json
{
  "layout": {
    "top": 0,
    "leading": 0,
    "trailing": 0,
    "ignoresSafeArea": false
  }
}
```

### Extend Under Safe Area

```json
{
  "layout": {
    "top": 0,
    "leading": 0,
    "trailing": 0,
    "ignoresSafeArea": true
  }
}
```

### Constrain to Safe Area Edge

Use `"target": "safeArea"` with `attribute` to anchor a component edge to the safe area boundary:

```json
{
  "layout": {
    "constraints": [
      { "type": "top",    "target": "superview" },
      { "type": "leading","target": "superview" },
      { "type": "trailing","target": "superview" },
      { "type": "bottom", "target": "safeArea", "attribute": "top" }
    ]
  }
}
```

This pins the bottom of the component to the **top** of the safe area — useful for a topbar that extends behind the status bar. Similarly, `"type": "top", "attribute": "bottom"` anchors to the bottom of the safe area for a bottom bar.

### Additional Safe Area Insets (Screen Level)

Declare `additionalSafeAreaInsets` on the screen's `content` to push scroll content away from overlaid bars. The engine applies these as `UIViewController.additionalSafeAreaInsets`, which automatically adjusts scroll views and safe-area-aware layouts.

```json
{
  "type": "screen",
  "content": {
    "additionalSafeAreaInsets": { "top": 60, "bottom": 60 },
    "children": [ ]
  }
}
```

Each edge is optional. The values are in points and correspond to the height of the bar that overlays that edge.

**Full topbar + bottom bar pattern:**

```json
{
  "type": "screen",
  "content": {
    "additionalSafeAreaInsets": { "top": 60, "bottom": 60 },
    "children": [
      {
        "id": "list",
        "type": "collection",
        "content": {
          "layout": {
            "constraints": [
              { "type": "top",      "target": "superview" },
              { "type": "leading",  "target": "superview" },
              { "type": "trailing", "target": "superview" },
              { "type": "bottom",   "target": "superview" }
            ]
          }
        }
      },
      {
        "id": "topbar",
        "type": "view",
        "content": {
          "layout": {
            "constraints": [
              { "type": "top",      "target": "superview" },
              { "type": "leading",  "target": "superview" },
              { "type": "trailing", "target": "superview" },
              { "type": "bottom",   "target": "safeArea", "attribute": "top" }
            ]
          },
          "children": [
            {
              "id": "topbar-content",
              "type": "view",
              "content": {
                "layout": {
                  "height": 60,
                  "constraints": [
                    { "type": "leading",  "target": "superview" },
                    { "type": "trailing", "target": "superview" },
                    { "type": "bottom",   "target": "superview" }
                  ]
                }
              }
            }
          ]
        }
      },
      {
        "id": "bottombar",
        "type": "view",
        "content": {
          "layout": {
            "constraints": [
              { "type": "top",      "target": "safeArea", "attribute": "bottom" },
              { "type": "leading",  "target": "superview" },
              { "type": "trailing", "target": "superview" },
              { "type": "bottom",   "target": "superview" }
            ]
          },
          "children": [
            {
              "id": "bottombar-content",
              "type": "view",
              "content": {
                "layout": {
                  "height": 60,
                  "constraints": [
                    { "type": "top",      "target": "superview" },
                    { "type": "leading",  "target": "superview" },
                    { "type": "trailing", "target": "superview" }
                  ]
                }
              }
            }
          ]
        }
      }
    ]
  }
}
```

**Key points:**
- `topbar` spans from screen top → safe area top (covers status bar). Its `topbar-content` (height = inset value) is pinned to its bottom — the visible bar area.
- `bottombar` spans from safe area bottom → screen bottom (covers home indicator). Its `bottombar-content` (height = inset value) is pinned to its top.
- `additionalSafeAreaInsets` values must match the `height` of the respective content views.

---

## Common Layout Patterns

### Fill Parent

```json
{
  "layout": {
    "leading": 0,
    "trailing": 0,
    "top": 0,
    "bottom": 0
  }
}
```

### Card with Margins

```json
{
  "layout": {
    "leading": 16,
    "trailing": 16,
    "top": 16
  }
}
```

### Fixed-Size Button Centered

```json
{
  "layout": {
    "constraints": [
      { "type": "centerX", "target": "superview" }
    ],
    "bottom": 40,
    "width": 200,
    "height": 50
  }
}
```

### Form Field Stack

```json
{
  "children": [
    {
      "type": "textField",
      "id": "emailField",
      "content": {
        "layout": {
          "leading": 20,
          "trailing": 20,
          "top": 100,
          "height": 50
        }
      }
    },
    {
      "type": "textField",
      "id": "passwordField",
      "content": {
        "layout": {
          "constraints": [
            { "type": "top", "target": "sibling(emailField)", "attribute": "bottom", "constant": 16 }
          ],
          "leading": 20,
          "trailing": 20,
          "height": 50
        }
      }
    },
    {
      "type": "button",
      "content": {
        "layout": {
          "constraints": [
            { "type": "top", "target": "sibling(passwordField)", "attribute": "bottom", "constant": 24 }
          ],
          "leading": 20,
          "trailing": 20,
          "height": 50
        }
      }
    }
  ]
}
```

### Keyboard-Aware Submit Button

```json
{
  "type": "button",
  "content": {
    "properties": { "text": "Submit" },
    "layout": {
      "constraints": [
        { "type": "bottom", "target": "keyboard", "constant": -20 }
      ],
      "leading": 20,
      "trailing": 20,
      "height": 50
    }
  }
}
```

---

## Layout Debugging Tips

1. **Missing size**: If a component doesn't appear, ensure it has either explicit width/height or constraints that define size

2. **Conflicting constraints**: Don't set both `leading`/`trailing` and `width` unless centering

3. **Safe area issues**: Use `ignoresSafeArea: true` for full-bleed backgrounds

4. **Keyboard layout**: The `keyboard` target automatically handles keyboard show/hide animations

5. **Pinning a generic container's size**: Hugging and compression-resistance priorities only act on views that have an intrinsic content size — labels, images, icons, buttons, stacks with intrinsic-sized children. To control the size of a generic container (`view`, `scrollView`, `collection`), use a self-dimension constraint or sibling-dimension equality.

6. **Priority cascade under pressure**: AL breaks the lowest-priority constraint first. A common multi-level layout uses *outer* spacers at `= preferred @ defaultLow` (250), *inner* group spacers at a custom priority around 500, and content (labels, icons) keeping default CR (750). The thing you want to yield first should carry the lowest priority on its preferred-size constraint, with a `>= floor @ required` to set its minimum.
