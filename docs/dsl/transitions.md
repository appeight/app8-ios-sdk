# Screen Transitions

A **transition** describes how one screen gives way to the next — the animation
that plays when you push, pop, present, or dismiss. It is the navigation-level
companion to the [animation primitive](animations.md): a transition animates a
set of view properties (opacity, translate, scale, rotate) on the **outgoing**
and **incoming** screens from a `begin` keyframe to an `end` keyframe, under a
shared animation descriptor.

Transitions are fully generic (author any begin/end property states), come with
ergonomic presets, are reusable across flows via a registry, and support
gesture-driven interactive dismiss/pop.

```jsonc
// Push the detail screen with a slide from the trailing edge.
{ "type": "navigation", "nextScreen": "detail", "transition": "slide" }
```

---

## Where a transition can be declared

A transition is resolved by precedence — the first one found wins:

1. **Navigation action** — `transition` on a `navigation` action (highest priority).
2. **Target screen default** — `content.transition` on the screen being navigated to.
3. **App default** — `defaultTransition` in `app.json` (lowest-priority fallback).

```jsonc
// app.json
{
  "transitions": [ /* reusable named transitions, see Registry */ ],
  "defaultTransition": { "id": "slideTrans" }     // applies to every push unless overridden
}

// a screen
{ "type": "screen", "content": { "transition": { "preset": "fade" }, /* … */ } }

// a navigation action (wins over both of the above)
{ "type": "navigation", "nextScreen": "detail", "transition": { "id": "zoomModal" } }
```

Screen and app defaults apply to **push** navigations. Custom **modal** transitions
are declared explicitly on the action (see [Routing](#routing-push-vs-modal)).

---

## Reference forms

A `transition` value can be written four ways — identical to the
[animation](animations.md) model:

| Form | JSON | Meaning |
|------|------|---------|
| Preset shorthand | `"slide"` | bare string = a named preset |
| Pointer | `{ "id": "slideTrans" }` | reference into the `transitions` registry |
| Wrapped inline | `{ "id": "x", "type": "transition", "content": { … } }` | named, defined in place |
| Flat inline | `{ "preset": "slide", "edge": "trailing" }` | anonymous, inline |

---

## Inline transition fields

```jsonc
{
  "mode": "push",                 // "push" (nav stack) | "modal" (present). Optional — presets pick a default.
  "preset": "slide",              // optional named preset that seeds the keyframes
  "edge": "trailing",             // edge presets enter from: leading | trailing | top | bottom
  "animation": { "duration": 0.35, "curve": "easeInOut" },  // any animation, or { "id": "smooth" }

  // Fully custom keyframes — override / replace the preset seed.
  "from": { "begin": { /* TransitionState */ }, "end": { /* … */ } },  // outgoing screen
  "to":   { "begin": { /* … */ },               "end": { /* … */ } },  // incoming screen

  "reverse": "auto",              // "auto" (default) or an explicit { from, to } for an asymmetric exit
  "raise": "incoming",            // z-order: "incoming" (default) | "outgoing" — see Layering

  "dimming":     { "color": "#000000", "opacity": 0.4 },     // modal backdrop (optional)
  "interactive": { "enabled": true, "edge": "trailing", "threshold": 0.3, "velocity": 800 }
}
```

`animation` accepts the full [animation](animations.md) descriptor — named curves,
custom `cubicBezier`, and `spring`. A `{ "id": "…" }` resolves against the app
[`animations` registry](animations.md#registry).

### TransitionState

A keyframe applied to one screen's view. Every field is optional and defaults to
identity, so you specify only what moves.

```jsonc
{
  "opacity": 1.0,                       // 0…1, default 1
  "translate": { "x": "100%", "y": 0 }, // number = points, "NN%" = fraction of container width (x) / height (y)
  "scale": 0.9,                         // number (uniform) or { "x": .., "y": .. }, default 1
  "rotate": 0,                          // degrees, clockwise, default 0
  "anchor": { "x": 0.5, "y": 0.5 }      // scale/rotate origin in 0…1, default centre
}
```

`translate` uses **percent-of-container**, so `"100%"` is exactly one screen
width/height on any device — the key to robust slide/cover transitions.

`opacity` is **absolute** per keyframe: omitting it means the natural,
fully-opaque resting state (`1`). So an `end` keyframe that leaves `opacity` out
always animates the screen back to fully visible — a `begin` that fades a screen
in (`opacity: 0`) doesn't need to repeat `opacity: 1` at `end`.

## Layering (`raise`)

The container z-order is set by `raise`, defined in forward terms:

| `raise` | Forward stacking | Use it for |
|---------|------------------|------------|
| `incoming` (default) | entering/revealed screen **on top** | slide / zoom / cover *in* over the old screen |
| `outgoing` | leaving screen **on top** | the old screen moves **away to reveal** a stationary new screen underneath |

The reverse (pop/dismiss) mirrors the chosen stacking automatically, so the exit
reads as the exact inverse of the entrance.

```jsonc
// Old screen slides down and off, revealing the new screen sitting beneath it.
{
  "mode": "push",
  "raise": "outgoing",
  "from": { "begin": {}, "end": { "translate": { "x": 0, "y": "100%" } } },
  "to":   { "begin": {}, "end": {} }
}
```

---

## Presets

Each preset expands to begin/end keyframes plus a default animation. Any explicit
field on the transition overrides the preset's value.

| Preset | Default mode | Behavior |
|--------|--------------|----------|
| `slide` | push | Incoming enters from `edge` (default trailing); outgoing parallaxes the opposite way. The default tunable push. |
| `fade` / `crossDissolve` | push | Incoming fades in over the outgoing. |
| `scale` / `zoom` | modal | Incoming scales up from 92% while fading in (spring). |
| `cover` | modal | Incoming slides in from `edge` (default bottom); pairs well with `dimming`. |
| `shared` | push | **Shared-element** morph — matched elements fly between screens (hero / composite). See [Shared-element transitions](#shared-element-transitions-zoom--composite). |
| `none` | push | Instantaneous (no animation). |
| `system` | push / modal | Sentinel — installs **no** custom animation; uses UIKit's native push / modal. Opt back out per-navigation. |

```jsonc
{ "type": "navigation", "nextScreen": "photo", "transition": { "preset": "cover", "edge": "bottom" } }
```

---

## Shared-element transitions (zoom & composite)

A **shared-element** transition morphs individual *matched* elements from one
screen into their counterparts on the next — a thumbnail that grows into a
full-screen hero (SwiftUI-style zoom), or several elements that fly independently
into their new positions (composite). It is opted into with the **`shared`**
preset and needs **no element ids** in the transition itself.

### How matching works

Matching is by a **transition key declared on each component**, never by the
component's `id` (which stays free for state, layout, and analytics). A component
opts in by giving its `content.transition` an **element context**:

```jsonc
{
  "id": "hero-card", "type": "view",        // id is untouched
  "content": {
    "transition": {
      "key": "hero",          // matched across screens
      "morph": "frameFade",   // frame | fade | frameFade (default)
      "fallback": "fade",     // fade (default) | slideTop | slideBottom | none
      "stagger": 0.04,        // optional: delay this element's morph (composite)
      "animation": { "cubicBezier": [0.2, 0.9, 0.1, 1], "duration": 0.5 }  // optional
    },
    /* … */
  }
}
```

At transition time the engine collects each screen's `[key → view]`, keeps the
keys present on **both** screens, and morphs each matched pair from the outgoing
element's frame to the incoming element's frame. **One** matched key reads as a
zoom; **several** matched keys read as a composite. The screen-level `from`/`to`
keyframes still animate the **backdrop** (the non-matched content) underneath.

> `content.transition` carries two kinds of context, told apart by the presence of
> `key`: on a **screen root** it is the screen's default `ScreenTransition`
> (above); on a **child component** it is this element-participation context.

### Authoring flow

Because matching is a plain key intersection, give each screen **unique** keys
(one `hero`). The natural pattern is to open a *source* screen first, then trigger
the *destination* — so each screen has exactly one element per key:

```jsonc
// app.json — opt in with the `shared` preset; no ids here
{ "id": "heroZoom", "type": "transition",
  "content": { "preset": "shared", "animation": { "id": "dramatic" } } }

// source screen: the element to zoom + a trigger to the destination
{ "id": "hero-card", "type": "view", "content": {
    "transition": { "key": "hero" },
    "actions": { "tap": { "type": "navigation", "nextScreen": "heroDest",
                          "transition": { "id": "heroZoom" } } } } }

// destination screen: the same key, full-screen
{ "id": "hero-card", "type": "view", "content": { "transition": { "key": "hero" } } }
```

The reverse (pop / dismiss) morphs the destination element back to the source
element automatically.

### `morph`, `fallback`, `stagger`, per-element timing

- **`morph`** — how the matched element's *appearance* transfers while its frame
  and corner radius interpolate. `frameFade` (default) **cross-dissolves** a render
  of the outgoing element (fading out on top) into the **real** incoming view
  (morphing into place underneath), so differing content/corners blend smoothly and
  there is no hand-off snap at completion. `fade` cross-dissolves **without** moving
  the frame — use it for co-located elements. `frame` slides a single opaque source
  render into place with **no** dissolve, revealing the real destination at the end
  — use it when source and destination are visually identical.
- **`fallback`** — what happens to a keyed element with **no** counterpart on the
  other screen: `fade` (default), `slideTop` / `slideBottom` (fade + slide), or
  `none` (ride the backdrop).
- **`stagger`** — delays an element's morph by N seconds (resolved as a fraction of
  the duration), so a composite plays element-by-element.
- **`animation`** — a lone hero may carry its **own** timing (any named curve,
  custom `cubicBezier`, or `spring`); for multi-element composites the
  transition-level `animation` drives and `stagger` orders the elements.

`shared` also accepts `mode: "modal"`, `dimming`, and `interactive` like any other
preset. **Reduce Motion** collapses a shared transition to a plain cross-dissolve.

### Correctness

The morph is deliberately **asymmetric**, and that is what makes it robust. The
*outgoing* element is always fully painted on screen, so the engine lifts a
snapshot of it above both screens to fade and move out. The *incoming* element is
the **real view** — never a snapshot — given a transform that starts it at the
source frame and animates back to identity. So the destination is rendered live by
UIKit at every step: there is **no dependency on the incoming screen having
painted** (the cause of an intermittently blank destination), and the real view is
never rasterized or upscaled (so it stays sharp). The source snapshot fading out
over the real destination *is* the cross-dissolve; both follow the same morphing
frame, so the element reads as one object. On every completion path (success *and*
cancel) the snapshot is removed, the real views are unhidden, and all transforms
are reset to identity — a matched element is never left blank, translucent,
transformed, or duplicated.

---

## Reverse (dismiss / pop)

By default the dismiss/pop animation is the forward transition **played backwards**
(`"reverse": "auto"`). For an asymmetric exit, provide explicit keyframes:

```jsonc
{
  "preset": "slide",
  "reverse": {
    "from": { "begin": {}, "end": { "opacity": 0, "scale": 0.9 } },
    "to":   { "begin": {}, "end": {} }
  }
}
```

The screen that remains visible always rests at identity (full opacity, no
transform) — a transition never leaves a screen scaled, shifted, or faded.

---

## Routing (push vs modal)

The navigation **action** decides the route; the transition decides how it looks:

- No `presentation` (or `"push"`) → **push** onto the nav stack. The transition's
  forward keyframes play on push, reversed on pop/back.
- A modal `presentation` (`sheet`, `fullScreen`, …) → **system modal** with native
  animation (see [navigation.md](navigation.md#presentation-styles)).
- An action transition whose `mode` is `"modal"` → **custom modal** — the
  engine-driven transition replaces the system modal animation, with optional
  `dimming` and interactive swipe-to-dismiss.

---

## Interactive dismiss / pop

Set `interactive.enabled` to drive the dismiss (modal) or pop (push) with a pan
gesture. Drag toward the dismissal `edge`; lifting past `threshold` (fraction of
the screen) **or** above `velocity` (points/sec) completes, otherwise it springs
back.

```jsonc
{
  "preset": "cover",
  "mode": "modal",
  "dimming": { "color": "#000000", "opacity": 0.5 },
  "interactive": { "enabled": true, "edge": "bottom", "threshold": 0.3, "velocity": 700 }
}
```

For a custom interactive push, the engine installs its own screen-edge gesture and
disables the system swipe-back so the two never fight.

---

## Registry

Define reusable transitions once in `app.json`, reference them by pointer
anywhere — exactly like the [`animations` registry](animations.md#registry). A
registry transition can reference an animation by pointer too.

```jsonc
{
  "animations": [
    { "id": "smooth", "type": "animation", "content": { "duration": 0.45, "cubicBezier": [0.2, 0.8, 0.2, 1.0] } }
  ],
  "transitions": [
    { "id": "slideTrans", "type": "transition",
      "content": { "preset": "slide", "edge": "trailing", "animation": { "id": "smooth" } } },
    { "id": "coverModal", "type": "transition",
      "content": { "preset": "cover", "mode": "modal",
                   "dimming": { "color": "#000000", "opacity": 0.5 },
                   "interactive": { "enabled": true } } }
  ],
  "defaultTransition": { "id": "slideTrans" }
}
```

```jsonc
// referenced at a navigation action
{ "type": "navigation", "nextScreen": "detail", "transition": { "id": "slideTrans" } }
```

---

## Accessibility

When **Reduce Motion** is enabled, every custom transition automatically degrades
to a short cross-dissolve. Authors don't need to special-case it.

---

## Example

The **Screen Transitions** example app (`TestExamples/apps/TransitionGallery`)
exercises every preset, a fully custom keyframe transition, a screen-level
default, the `system` passthrough, instant `none`, and an interactive
swipe-to-dismiss cover modal. It also includes two **shared-element** demos: a
**hero zoom** (`heroSource` → `heroDest`, a card that grows to full screen with a
custom cubic-bézier curve) and a **composite** (`compositeSource` →
`compositeDest`, three elements morphing independently with staggered timing) —
each destination offering *back to source* (pop) and *back to list* (pop-to-root).

See also: [navigation.md](navigation.md) · [animations.md](animations.md) · [actions.md](actions.md)
