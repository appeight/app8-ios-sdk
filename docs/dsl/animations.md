# Animations

The `animation` primitive describes how a property change should transition over time. It drives:

- **State transitions** — every `state.animation` field on a `StatefulContent` view (button, view, etc.). When the component moves between states (touchDown → "pressed", focus, hover, …), the runner uses this descriptor to animate **alpha, transform, and material layers** (gradient fill, shadow, outline, cornerRadius) under one synchronized transition.
- **Per-property variable changes** *(parsing only — runtime hookup pending)* — properties driven by `{{expression}}` values can declare an `animation` next to the `value` so future variable mutations animate.
- **Default press feedback** — buttons without explicit `states` use a built-in animation as touch-down/up feedback.
- **Screen transitions** — the [transition](transitions.md) system reuses this primitive for the timing of screen-to-screen animations.

The same primitive shows up everywhere — one schema, one runner, one mental model.

## Anatomy

```jsonc
{
  "duration": 0.15,                 // seconds, required
  "delay": 0,                       // seconds, optional, default 0
  "options": ["beginFromCurrent"],  // optional, see Options

  // Timing — supply at most one of `curve`, `cubicBezier`, or `spring`.
  // If you pass several, precedence is: spring > cubicBezier > curve.
  "curve": "easeOut",               // linear | easeIn | easeOut | easeInOut
  "cubicBezier": [0.25, 0.1, 0.25, 1.0],
  "spring": { "damping": 0.8, "velocity": 0.9, "mass": 1.0, "stiffness": 100 }
}
```

| Field | Type | Notes |
|-------|------|-------|
| `duration` | `Number` | Seconds. Required. UIView's spring API requires a duration even though a true spring runs until rest. |
| `delay` | `Number` | Seconds. Default `0`. |
| `options` | `[String]` | See [Options](#options). |
| `curve` | `"linear" \| "easeIn" \| "easeOut" \| "easeInOut"` | Named easing. |
| `cubicBezier` | `[x1, y1, x2, y2]` | Custom cubic-bezier control points. |
| `spring` | `{ damping, velocity, mass?, stiffness? }` | See [Spring](#spring). |

### Options

| Value | Effect |
|-------|--------|
| `beginFromCurrent` | Maps to `UIView.AnimationOptions.beginFromCurrentState` so a re-press during a release picks up the in-flight presentation values. |
| `allowUserInteraction` | Permits touch input during the animation. |
| `repeat` | Loops the animation. |
| `autoreverse` | Plays back in reverse after each forward pass. |

State-driven animations always run with `beginFromCurrentState` and `allowUserInteraction` added on top of whatever you specify in `options` — re-pressing during settle should always feel right. You don't need to pass them.

### Spring

| Field | Default | Notes |
|-------|---------|-------|
| `damping` | `0.85` | Damping fraction in `[0, 1]`. Lower = bouncier. Maps to `usingSpringWithDamping:` for view animations. |
| `velocity` | `0` | Initial velocity. Positive values continue the gesture's direction. |
| `mass` | *unset* | Optional. When provided, the runner uses `UIViewPropertyAnimator` with `UISpringTimingParameters(mass:stiffness:damping:initialVelocity:)`. |
| `stiffness` | *unset* | Optional. Required alongside `mass`. |

Most authors only need `damping` and `velocity`. The standard recipe for a settle is `{ damping: 0.8, velocity: 0.9 }`.

## State Transitions

Each `state.animation` describes how the component animates **into** that state. Pair `pressed` with a snappy ease-out and `normal` with a longer settle so the press feels reactive but the release feels smooth:

```json
{
  "type": "view",
  "content": {
    "triggers": { "touchDown": "pressed", "touchUp": "normal" },
    "defaultStateName": "normal",
    "states": {
      "normal": {
        "style": { "alpha": 1.0, "material": [...] },
        "animation": {
          "duration": 0.4,
          "spring": { "damping": 0.8, "velocity": 0.9 }
        }
      },
      "pressed": {
        "style": { "alpha": 0.85, "material": [...] },
        "animation": {
          "duration": 0.15,
          "curve": "easeOut"
        }
      }
    }
  }
}
```

What animates during a state transition:

- `alpha`, `transform` (UIView)
- Gradient fill colors and locations (CAGradientLayer)
- `shadowColor`, `shadowRadius`, `shadowOffset`, `shadowOpacity`
- Outline `strokeColor` (when only the color changes — `lineWidth` / `position` changes still recreate the layer)
- `cornerRadius`

All run under one duration so the visual change reads as a single coordinated event. See [states.md](states.md) for the trigger / child-state model.

## Reusable Registry

Define named animations once at the app level and reference them from anywhere:

```jsonc
// app.json
{
  "title": "MyApp",
  "navigation": { /* … */ },
  "animations": [
    {
      "id": "fastPress",
      "type": "animation",
      "content": { "duration": 0.15, "curve": "easeOut" }
    },
    {
      "id": "settle",
      "type": "animation",
      "content": {
        "duration": 0.4,
        "spring": { "damping": 0.8, "velocity": 0.9 }
      }
    }
  ]
}
```

Reference by id — same `Pointer` form as [styles](styles.md):

```json
{
  "states": {
    "pressed": { "animation": { "id": "fastPress" } },
    "normal":  { "animation": { "id": "settle"    } }
  }
}
```

The engine resolves pointers at decode time using the registry from `app.json`. A pointer that doesn't exist in the registry is preserved as-is and falls back to instantaneous at runtime.

## Per-Property Animations

Property values that drive animatable view properties accept an optional `animation` describing how variable changes should transition. Both shapes parse — wrap when you want the change to animate, leave it bare otherwise:

```json
{
  "properties": {
    "transformTranslateX": {
      "value": "{{ x }}",
      "animation": { "duration": 0.2, "curve": "easeOut" }
    },
    "alpha": {
      "value": "{{ visible ? 1 : 0 }}",
      "animation": { "id": "settle" }
    }
  }
}
```

```json
{
  "properties": {
    "transformTranslateX": "{{ x }}"
  }
}
```

### Where it works today

| Component | Animatable expression-driven properties |
|---|---|
| `view` | `transformScale`, `transformTranslateX`, `transformTranslateY`, `alpha`, `backgroundColor` |
| `label` | `backgroundColor` |
| `icon` | `tintColor`, `backgroundColor` |
| `shape` | `progress` |

### Precedence

When a variable change fires and the property is animatable, the runtime picks an `Animation.Inline` to drive `AnimationRunner.run` in this order:

1. **Per-property `animation`** wrapped on the property value — wins when present. Pointer references resolve at decode time against the app-level `animations` registry.
2. **Legacy fallback** — preserves bit-for-bit historic behavior so existing screens animate exactly as before:
   - `transformScale` / `transformTranslateX` / `transformTranslateY`: `0.3s spring (damping 0.75, velocity 0.3)`
   - `alpha`: `0.25s easeOut`
   - `shape.progress`: derived from the legacy `animationDuration` + `animationCurve` siblings on the same Properties object
   - All other color/visual properties: instantaneous (matches what they did before)

Per-property animation also takes precedence over the active state animation. Rationale: an author who attached a descriptor to *this property* expects it to win over a generic state transition.

### First apply

The first time a property gets a value (component initialization, or first time a `dynamicBackgroundView` is added) is always **instantaneous** regardless of the descriptor — there's no meaningful "from" value to animate from. Subsequent variable-driven changes use the descriptor.

### Notes

- `isHidden` is currently animation-free (a discrete bool); cross-fade as alpha is a planned follow-up.
- Layout-driving expressions (`width` / `height`) are not animatable through this path — they need a separate layout-transition API.

## Defaults

| Situation | Behavior |
|-----------|----------|
| No `animation` on a state | Instantaneous transition. |
| No `states` on a button | Built-in press-feedback animation (~150ms ease-out). |
| `curve: "spring"` (legacy, no parameters) | Spring with `damping: 0.85`, `velocity: 0`. |
| Reduce Motion enabled (system setting) | All animations collapse to instantaneous. |
| Animation pointer fails to resolve | Instantaneous + warning. |

## Quick Reference

```json
// Snappy press feedback
{ "duration": 0.15, "curve": "easeOut" }

// Bouncy settle on release
{ "duration": 0.4, "spring": { "damping": 0.8, "velocity": 0.9 } }

// Custom timing curve
{ "duration": 0.3, "cubicBezier": [0.25, 0.1, 0.25, 1.0] }

// Critically damped layout settle
{ "duration": 0.5, "spring": { "damping": 1.0, "velocity": 0 } }

// Linear, kept simple
{ "duration": 0.2, "curve": "linear" }
```
