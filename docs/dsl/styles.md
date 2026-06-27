# Styles

Styles define visual appearance for components. They can be inline, referenced via pointers, or inherited from templates.

## Using Styles in Components

Every style property inside a component's `style` block must be a **Style Entity** — an object with `id` and `type` fields. The engine uses these fields to decode the correct style type. Without them, the style silently fails to decode (SCR005 warnings).

### Style Entity Formats

**Inline Style Entity** — full definition in-place:

<!-- @dsl-skip: style entity fragment -->
```json
{
  "id": "headingText",
  "type": "text",
  "content": {
    "fontSize": 24,
    "fontWeight": "bold",
    "alignment": "center"
  }
}
```

**Style Pointer** — reference to a style defined in the app-level `styles` array:

<!-- @dsl-skip: style pointer fragment -->
```json
{
  "id": "headingText"
}
```

The short form (no `"type"`) is preferred for pointers. `"type"` may still be included for clarity and continues to work:

<!-- @dsl-skip: style pointer fragment -->
```json
{
  "id": "headingText",
  "type": "text"
}
```

When `content` is absent, the engine treats the entity as a pointer and resolves it by `id` from the shared styles.

### Required Fields

| Field | Required | Description |
|-------|----------|-------------|
| `id` | Yes | Unique identifier for the style |
| `type` | No (pointer) / Yes (inline) | Required when `content` is present (discriminator for decoding). Optional for pointer-only references — the parent key already encodes the expected type. |
| `content` | No | Style data. Omit to create a pointer reference |

### Valid `type` Values

| Type | Content | Description |
|------|---------|-------------|
| `material` | Material layers array | Background, corner, outline, shadow, effects |
| `text` | TextModel | Typography styling |
| `icon` | Icon style | SF Symbol styling |
| `fill` | Fill | Solid or gradient fill |
| `color` | Themed color | Hex color with theme support |
| `gradient` | Gradient | Gradient definition |
| `outline` | Outline | Border/stroke |
| `shadow` | Shadow | Drop shadow |
| `corner` | Corner | Corner radius |
| `visualEffect` | VisualEffect | Blur/glass effects |
| `view` | ViewStyle | General view appearance |
| `image` | ImageStyle | Image rendering options |
| `font` | Font | Font definition |
| `systemButton` | SystemButton | Native `UIButton.Configuration` styling (filled/tinted/bordered/glass, capsule corners, tint, role, SF-Symbol image). Reference it from a button via `style.system`. See [components/button.md](components/button.md#style-systembutton-native). |

### Component Examples

Label with inline text style:

```json
{
  "type": "label",
  "content": {
    "properties": { "text": "Hello" },
    "style": {
      "text": {
        "id": "helloText",
        "type": "text",
        "content": { "fontSize": 24, "alignment": "center" }
      }
    }
  }
}
```

View with inline material style:

```json
{
  "type": "view",
  "content": {
    "style": {
      "material": {
        "id": "cardMaterial",
        "type": "material",
        "content": [
          { "id": "cardFill", "type": "fill", "content": { "solid": "#FFFFFF" } },
          { "id": "cardCorner", "type": "corner", "content": { "radius": 12, "curve": "continuous" } }
        ]
      }
    }
  }
}
```

Icon with inline style:

```json
{
  "type": "icon",
  "content": {
    "properties": { "icon": "star.fill" },
    "style": {
      "icon": {
        "id": "starIcon",
        "type": "icon",
        "content": { "tint": "#FF9500", "symbolFontSize": 20 }
      }
    }
  }
}
```

### Common Mistakes

**Missing `id` and `type`** — style content without the entity wrapper:

```json
// WRONG — will fail to decode (SCR005)
"style": {
  "text": { "fontSize": 24, "alignment": "center" }
}

// CORRECT — wrapped as a Style Entity
"style": {
  "text": {
    "id": "myText",
    "type": "text",
    "content": { "fontSize": 24, "alignment": "center" }
  }
}
```

**Missing `id`/`type` on material layers** — each layer in a material array is also a Style Entity:

```json
// WRONG — material layers lack entity fields
"material": {
  "id": "card",
  "type": "material",
  "content": [
    { "solid": "#FFFFFF" },
    { "radius": 12 }
  ]
}

// CORRECT — each layer has id and type
"material": {
  "id": "card",
  "type": "material",
  "content": [
    { "id": "cardFill", "type": "fill", "content": { "solid": "#FFFFFF" } },
    { "id": "cardCorner", "type": "corner", "content": { "radius": 12 } }
  ]
}
```

---

## Color

Hex color values with optional theme support.

### Formats

| Format | Example | Description |
|--------|---------|-------------|
| `#RGB` | `#F00` | Short hex (red) |
| `#RRGGBB` | `#FF5500` | Standard hex |
| `#RRGGBBAA` | `#FF550080` | With alpha |
| Themed | `{ "light": "#000", "dark": "#FFF" }` | Light/dark theme |

### Examples

```json
"color": "#FF5500"
```

```json
"color": "#FF550080"
```

```json
"color": {
  "light": "#000000",
  "dark": "#FFFFFF"
}
```

---

## Fill

Background fill - solid color or gradient.

### Solid Fill

<!-- @dsl-skip: fill fragment -->
```json
{
  "solid": "#FF5500"
}
```

### Gradient Fill

<!-- @dsl-skip: gradient fragment -->
```json
{
  "gradient": {
    "start": { "x": 0, "y": 0, "color": "#FF0000" },
    "end": { "x": 1, "y": 1, "color": "#0000FF" },
    "middlePoints": [
      { "position": 0.5, "color": "#00FF00" }
    ]
  }
}
```

### Gradient Properties

| Property | Type | Description |
|----------|------|-------------|
| `start` | Vertex | Start point (x: 0-1, y: 0-1) and color |
| `end` | Vertex | End point and color |
| `middlePoints` | MiddlePoint[] | Optional intermediate colors |

---

## Material

Composition of visual layers applied in order.

### Structure

A `material` entity's `content` is an array of layers, and **each layer is itself a Style Entity** (`id` + `type` + `content`):

```json
{
  "material": {
    "id": "cardMaterial",
    "type": "material",
    "content": [
      { "id": "cardFill", "type": "fill", "content": { "solid": "#FFFFFF" } },
      { "id": "cardCorner", "type": "corner", "content": { "radius": 12, "curve": "continuous" } },
      { "id": "cardOutline", "type": "outline", "content": { "lineWidth": 1, "fill": { "solid": "#E5E5E5" } } },
      { "id": "cardShadow", "type": "shadow", "content": [{ "color": "#00000020", "radius": 8, "offset": { "y": 4 } }] }
    ]
  }
}
```

The per-style sections below show only the layer `content` shape — wrap each as a Style Entity when used.

### Layer Types

- `fill` - Background fill
- `corner` - Corner radius
- `outline` - Border/stroke
- `shadow` - Drop shadow
- `visualEffect` - Blur effect

---

## Outline

Border/stroke styling.

### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `lineWidth` | number | | Stroke width in points |
| `position` | Position | `inside` | Stroke position |
| `fill` | Fill | | Stroke color/fill |

### Position Values

| Value | Description |
|-------|-------------|
| `inside` | Stroke inside bounds |
| `outside` | Stroke outside bounds |
| `center` | Stroke centered on bounds |

### Example

<!-- @dsl-skip: outline fragment -->
```json
{
  "outline": {
    "lineWidth": 2,
    "position": "inside",
    "fill": { "solid": "#007AFF" }
  }
}
```

---

## Shadow

Drop shadow as an array of layers.

### Layer Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `color` | Color | | Shadow color |
| `radius` | number | | Blur radius |
| `offset` | Offset | | Shadow offset |
| `opacity` | number | 1.0 | Shadow opacity |
| `isHollow` | boolean | false | Hollow shadow (cutout) |

### Offset Structure

```json
{ "x": 0, "y": 4 }
```

### Example

<!-- @dsl-skip: shadow fragment -->
```json
{
  "shadow": [
    {
      "color": "#00000040",
      "radius": 8,
      "offset": { "x": 0, "y": 4 },
      "opacity": 1.0
    }
  ]
}
```

### Multiple Shadows

<!-- @dsl-skip: shadow fragment -->
```json
{
  "shadow": [
    { "color": "#00000010", "radius": 2, "offset": { "y": 1 } },
    { "color": "#00000020", "radius": 8, "offset": { "y": 4 } },
    { "color": "#00000010", "radius": 16, "offset": { "y": 8 } }
  ]
}
```

---

## Corner

Corner radius configuration.

### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `radius` | number \| string \| object | | Corner radius — see [Radius](#radius) |
| `curve` | Curve | `circular` | Corner curve type |

### Radius

`radius` accepts an absolute or a relative value. A relative radius is a
fraction of the view's **smaller** dimension and is re-resolved whenever the
view is resized, so it stays correct when a layout compresses. `"50%"` always
yields a perfect circle/capsule.

| Form | Example | Meaning |
|------|---------|---------|
| Fixed | `16` | Absolute radius in points |
| Percent string | `"50%"` | Fraction of `min(width, height)` |
| Capsule | `"capsule"` | Pill shape — `min(width, height) / 2`, scales with the view |
| Keyed object | `{ "type": "fraction", "value": 0.5 }` | Fraction of `min(width, height)` |
| Keyed object | `{ "type": "fixed", "value": 16 }` | Absolute radius in points |
| Keyed object | `{ "type": "capsule" }` | Pill shape |

`curve` is optional and defaults to `circular`. On an iOS 26 **glass** effect the
corner is applied via the system glass corner configuration (`"capsule"` → a true
glass capsule), so the glass keeps its own contoured edge instead of being
hard-clipped by a layer mask.

### Curve Values

| Value | Description |
|-------|-------------|
| `circular` | Standard circular corners |
| `continuous` | iOS-style smooth corners |

### Example

```json
{
  "corner": {
    "radius": 16,
    "curve": "continuous"
  }
}
```

Circular avatar that stays round at any size:

```json
{
  "corner": {
    "radius": "50%",
    "curve": "circular"
  }
}
```

---

## VisualEffect

Blur and glass effects.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `blur` | BlurStyle | Background blur style |
| `glass` | GlassStyle | Glass effect |
| `container` | boolean | iOS 26 glass only. When `true`, the owning view's content renders *inside* the glass (`UIVisualEffectView.contentView`) so it refracts/morphs with the glass, and the glass is made interactive. Default `false` — glass is a background layer with content layered above it. No effect on blur or below iOS 26. |

### Glass as a content container

By default a glass `visualEffect` is a **background** layer: the view's children
are drawn on top of it. Set `container: true` to host the view's content *inside*
the glass instead — children then refract and morph with the iOS 26 liquid glass,
and the glass becomes touch-interactive. All of the view's children move together
(their mutual constraints are preserved); this is a view-level switch, not per child.

```json
{
  "type": "view",
  "content": {
    "style": { "material": [
      { "id": "g", "type": "visualEffect", "content": { "glass": "normal", "container": true } },
      { "id": "c", "type": "corner", "content": { "radius": "capsule" } }
    ] },
    "children": [ /* rendered inside the glass */ ]
  }
}
```

### Blur Styles

| Value | Appearance |
|-------|------------|
| `extraLight` | Extra light blur |
| `light` | Light blur |
| `dark` | Dark blur |
| `regular` | Regular blur |
| `systemUltraThinMaterial` | Ultra thin material |
| `systemThinMaterial` | Thin material |
| `systemMaterial` | Standard material |
| `systemThickMaterial` | Thick material |
| `systemChromeMaterial` | Chrome material |
| `systemUltraThinMaterialDark` | Dark ultra thin |
| `systemThinMaterialDark` | Dark thin |
| `systemMaterialDark` | Dark standard |
| `systemThickMaterialDark` | Dark thick |
| `systemChromeMaterialDark` | Dark chrome |

### Glass Styles

| Value | Description |
|-------|-------------|
| `normal` | Normal glass |
| `clear` | Clear glass |

### Example

```json
{
  "visualEffect": {
    "blur": "systemThinMaterial"
  }
}
```

---

## Text (TextModel)

Typography styling for text content.

### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `fontSize` | number | 17 | Font size in points |
| `fontWeight` | FontWeight | `regular` | Font weight |
| `alignment` | Alignment | `natural` | Text alignment |
| `color` | Color | | Text color |
| `lineHeight` | LineHeight | | Line height |
| `letterSpacing` | LetterSpacing \| number | | Letter spacing (kerning, in points) |
| `numberOfLines` | number | 0 | Max lines (0 = unlimited) |
| `lineBreakMode` | LineBreakMode | `truncateTail` | How text wraps/truncates on overflow |
| `underline` | boolean | false | Draw a single underline under the text |
| `strikethrough` | boolean | false | Draw a single strikethrough line through the text |
| `adjustsFontSizeToFitWidth` | boolean | false | Shrink font to fit width instead of truncating |
| `minimumScaleFactor` | number | 0.5 | Smallest font scale autoshrink may use (0–1); only used when `adjustsFontSizeToFitWidth` is true |

### FontWeight Values

| Value | Weight |
|-------|--------|
| `ultraLight` | 100 |
| `thin` | 200 |
| `light` | 300 |
| `regular` | 400 |
| `medium` | 500 |
| `semibold` | 600 |
| `bold` | 700 |
| `heavy` | 800 |
| `black` | 900 |

### Alignment Values

| Value | Description |
|-------|-------------|
| `left` | Left aligned |
| `center` | Center aligned |
| `right` | Right aligned |
| `justified` | Justified |
| `natural` | Natural (follows locale) |

### LineBreakMode Values

| Value | Description |
|-------|-------------|
| `wordWrap` | Wrap at word boundaries |
| `charWrap` | Wrap at character boundaries |
| `clip` | Clip at the edge, no truncation |
| `truncateHead` | Truncate at the start (…end) |
| `truncateTail` | Truncate at the end (start…) — UIKit default |
| `truncateMiddle` | Truncate in the middle (sta…end) |

### LineHeight Types

| Type | Description |
|------|-------------|
| `auto` | Automatic |
| `multiplier` | Multiple of font size |
| `fontSizeFraction` | Fraction of font size |
| `fixed` | Fixed value in points |
| `interLineSpacing` | Additional spacing between lines |

### LineHeight Example

```json
"lineHeight": { "type": "multiplier", "value": 1.4 }
```

### LetterSpacing Types

| Type | Description |
|------|-------------|
| `auto` | Automatic (no kerning applied) |
| `fixed` | Fixed value in points |

### LetterSpacing Example

Object form, or a bare number shorthand for fixed spacing in points:

```json
"letterSpacing": { "type": "fixed", "value": -1.5 }
```

```json
"letterSpacing": -1.5
```

### Complete Example

<!-- @dsl-skip: text style fragment -->
```json
{
  "text": {
    "fontSize": 16,
    "fontWeight": "medium",
    "color": "#333333",
    "alignment": "center",
    "lineHeight": { "type": "multiplier", "value": 1.4 },
    "letterSpacing": { "type": "fixed", "value": 0.5 },
    "numberOfLines": 2
  }
}
```

### Autoshrink Example

Shrink a single-line title to fit narrow containers instead of truncating it:

<!-- @dsl-skip: text style fragment -->
```json
{
  "text": {
    "fontSize": 22,
    "numberOfLines": 1,
    "adjustsFontSizeToFitWidth": true,
    "minimumScaleFactor": 0.6
  }
}
```

---

## Transform

View transformations.

### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `translateY` | number | 0 | Vertical translation |
| `scale` | number | 1.0 | Scale factor |
| `rotation` | number | 0 | Rotation in degrees |

### Example

```json
{
  "transform": {
    "translateY": -10,
    "scale": 0.95,
    "rotation": 45
  }
}
```

---

## Component Style Summary

### ViewStyle

| Property | Type |
|----------|------|
| `material` | Material |
| `alpha` | number |
| `contentMode` | ContentMode |
| `transform` | Transform |

### ContentMode Values

How a view positions or scales its content within its bounds. Available on `view`, `image`, `icon`, and most other component styles.

| Value | Behavior |
|-------|----------|
| `scaleToFill` | Stretch to fill, ignoring aspect ratio |
| `scaleAspectFit` | Scale to fit, preserving aspect ratio (may letterbox) |
| `scaleAspectFill` | Scale to fill, preserving aspect ratio (may crop) |
| `redraw` | Redraw on bounds change |
| `center` | Center, no scaling |
| `top` | Pin to top |
| `bottom` | Pin to bottom |
| `left` | Pin to left |
| `right` | Pin to right |
| `topLeft` | Pin to top-left |
| `topRight` | Pin to top-right |
| `bottomLeft` | Pin to bottom-left |
| `bottomRight` | Pin to bottom-right |

> For images, `scaleAspectFill` (fill + crop) and `scaleAspectFit` (fit + letterbox) are the two you'll reach for most.

### LabelStyle

| Property | Type |
|----------|------|
| `text` | TextModel |
| `material` | Material |
| `alpha` | number |

### ButtonStyle

| Property | Type |
|----------|------|
| `text` | TextModel |
| `material` | Material |
| `alpha` | number |

### ImageStyle

| Property | Type |
|----------|------|
| `contentMode` | ContentMode |
| `tintColor` | Color |
| `renderingMode` | RenderingMode |
| `corner` | Corner |
| `material` | Material |
| `alpha` | number |

### IconStyle

| Property | Type | Description |
|----------|------|-------------|
| `tint` | Color | Primary icon tint color |
| `color` | Color | Alternative color property |
| `hierarchicalColor` | Color | Color for hierarchical rendering `[Planned]` |
| `renderingMode` | RenderingMode | Image rendering mode |
| `fontId` | string | Custom font identifier |
| `symbolFontSize` | number | Symbol font size |
| `contentMode` | ContentMode | Content alignment |
| `transform` | Transform | Icon transform |
| `material` | Material | Background material |
| `alpha` | number | Opacity (0.0-1.0) |

### RenderingMode Values (for Icons)

| Value | Description |
|-------|-------------|
| `original` | Render with original colors |
| `template` | Render as template (uses tint color) |

### TextFieldStyle

| Property | Type |
|----------|------|
| `text` | TextModel |
| `placeholder` | TextModel |
| `tintColor` | Color |
| `padding` | EdgeInsets |
| `material` | Material |
| `alpha` | number |

### TextViewStyle

| Property | Type |
|----------|------|
| `text` | TextModel |
| `placeholder` | TextModel |
| `tintColor` | Color |
| `padding` | EdgeInsets |
| `material` | Material |
| `alpha` | number |

> Every component style below also accepts the shared `contentMode`, `alpha`, and `transform` fields (omitted from the per-component tables for brevity).

### ToggleStyle

| Property | Type | Description |
|----------|------|-------------|
| `onTintColor` | Color | Track color when on |
| `thumbTintColor` | Color | Thumb color |
| `material` | Material | Background |
| `alpha` | number | Opacity |

See [components/toggle.md](components/toggle.md).

### SliderStyle

| Property | Type | Description |
|----------|------|-------------|
| `minimumTrackTintColor` | Color | Filled track |
| `maximumTrackTintColor` | Color | Unfilled track |
| `thumbTintColor` | Color | Thumb color |
| `material` | Material | Background |
| `alpha` | number | Opacity |

See [components/slider.md](components/slider.md).

### PickerStyle

| Property | Type | Description |
|----------|------|-------------|
| `text` | TextModel | Menu-mode label text |
| `selectedSegmentTintColor` | Color | Selected segment (segmented mode) |
| `material` | Material | Background |
| `alpha` | number | Opacity |

See [components/picker.md](components/picker.md).

### DatePickerStyle

| Property | Type | Description |
|----------|------|-------------|
| `tintColor` | Color | Accent color for controls |
| `material` | Material | Background |
| `alpha` | number | Opacity |

See [components/date-picker.md](components/date-picker.md).

### PageControlStyle

| Property | Type | Description |
|----------|------|-------------|
| `pageIndicatorTintColor` | Color | Inactive dot color |
| `currentPageIndicatorTintColor` | Color | Active dot color |
| `material` | Material | Background |
| `alpha` | number | Opacity |

See [components/page-control.md](components/page-control.md).

### ActivityIndicatorStyle

| Property | Type | Description |
|----------|------|-------------|
| `indicatorStyle` | `medium` \| `large` | Spinner size |
| `color` | Color (hex) | Spinner tint |
| `material` | Material | Background |
| `alpha` | number | Opacity |

See [components/activity-indicator.md](components/activity-indicator.md).

---

## Style Pointers [Advanced]

Reference shared styles by ID. A pointer is a Style Entity without `content` — just `id` (and optionally `type`):

```json
{
  "style": {
    "text": { "id": "primaryButtonText" }
  }
}
```

The `"type"` field is optional for pointers — the parent key (`"text"`, `"material"`, etc.) already identifies the expected style type. Including `"type"` is still valid and ignored during resolution:

```json
{
  "style": {
    "text": { "id": "primaryButtonText", "type": "text" }
  }
}
```

The pointer is resolved at decode time against styles defined in the app-level `styles` array, allowing styles to be defined once and reused across components.

---

## EdgeInsets

Padding/margin specification.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `top` | number | Top inset |
| `left` | number | Left inset |
| `bottom` | number | Bottom inset |
| `right` | number | Right inset |

### Example

```json
{
  "padding": {
    "top": 12,
    "left": 16,
    "bottom": 12,
    "right": 16
  }
}
```
