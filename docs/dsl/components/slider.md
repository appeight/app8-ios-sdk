# Slider

A native continuous or stepped slider (`UISlider`). Two-way bound to a number variable.

## Content Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `properties.value` | number/expression | `0` | Current value. Accepts an expression, e.g. `"{{volume}}"` |
| `properties.minimumValue` | number | `0` | Lower bound |
| `properties.maximumValue` | number | `1` | Upper bound |
| `properties.step` | number | | Optional snap increment — values snap to the nearest multiple within `[min, max]` |
| `properties.bindVariable` | string | | Variable name for two-way binding (no `{{}}`) |
| `properties.isEnabled` | boolean/expression | `true` | Whether the slider accepts input |
| `hidden` | boolean/expression | | Hide component |

> **Binding vs. value**: set `bindVariable` to the bare variable **name**; set `value` to an **expression**. See [variables.md → Variable Binding](../variables.md#variable-binding).

> **Stepping**: when `step` is set (and > 0), the slider reports only snapped values — e.g. `step: 5` over `0…100` yields `0, 5, 10, …`. Omit `step` for a continuous slider.

## Style: SliderStyle

| Property | Type | Description |
|----------|------|-------------|
| `minimumTrackTintColor` | Color | Filled portion of the track |
| `maximumTrackTintColor` | Color | Unfilled portion of the track |
| `thumbTintColor` | Color | Thumb (knob) color |
| `material` | Material | Background |
| `alpha` | number | Opacity (0.0–1.0) |
| `contentMode` | ContentMode | Content alignment |

## Example

```json
{
  "type": "slider",
  "id": "volumeSlider",
  "content": {
    "properties": {
      "value": "{{volume}}",
      "minimumValue": 0,
      "maximumValue": 100,
      "step": 5,
      "bindVariable": "volume"
    },
    "style": {
      "minimumTrackTintColor": "#007AFF"
    },
    "layout": { "leading": 20, "trailing": 20, "centerY": 0 }
  }
}
```

Pair with a label that reads the same variable for a live readout:

```json
{
  "type": "label",
  "content": { "properties": { "text": "{{volume}}%" } }
}
```

## See Also

- [Forms & Inputs](../forms.md)
- [Toggle](toggle.md), [Picker](picker.md), [DatePicker](date-picker.md) — other bound inputs
- [variables.md](../variables.md) — binding and expressions
