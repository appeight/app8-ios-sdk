# Picker

A single-choice selector. Renders as a tap-to-open menu (`UIMenu`) or an inline segmented control (`UISegmentedControl`). Two-way bound to a string variable.

## Content Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `properties.options` | Option[] | | Selectable choices |
| `properties.selectedValue` | string/expression | | Current selection. Accepts an expression, e.g. `"{{selectedColor}}"` |
| `properties.bindVariable` | string | | Variable name for two-way binding (no `{{}}`) |
| `properties.displayMode` | DisplayMode | `menu` | `menu` or `segmented` |
| `properties.placeholder` | string | | Text shown in `menu` mode when nothing is selected |
| `properties.isEnabled` | boolean/expression | `true` | Whether the picker accepts input |
| `hidden` | boolean/expression | | Hide component |

> **Binding vs. value**: set `bindVariable` to the bare variable **name**; set `selectedValue` to an **expression**. The picker writes the selected option's `value` (not its `label`) back to the variable. See [variables.md → Variable Binding](../variables.md#variable-binding).

### Option

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `value` | string | Yes | Stored value written to the bound variable |
| `label` | string | Yes | Text shown to the user |
| `icon` | string | No | SF Symbol name shown beside the label |

## DisplayMode Values

| Value | Renders as | Best for |
|-------|------------|----------|
| `menu` | Tap-to-open dropdown menu | Many options, compact footprint |
| `segmented` | Inline segmented control | 2–4 options, all visible at once |

## Style: PickerStyle

| Property | Type | Description |
|----------|------|-------------|
| `text` | TextModel | Label text style (menu mode button) |
| `selectedSegmentTintColor` | Color | Selected segment color (segmented mode) |
| `material` | Material | Background |
| `alpha` | number | Opacity (0.0–1.0) |
| `contentMode` | ContentMode | Content alignment |

## Examples

**Segmented control:**

```json
{
  "type": "picker",
  "id": "sortPicker",
  "content": {
    "properties": {
      "displayMode": "segmented",
      "options": [
        { "value": "new", "label": "Newest" },
        { "value": "top", "label": "Top" },
        { "value": "hot", "label": "Trending" }
      ],
      "selectedValue": "{{sortOrder}}",
      "bindVariable": "sortOrder"
    },
    "layout": { "leading": 20, "trailing": 20, "top": 16 }
  }
}
```

**Menu with icons and a placeholder:**

```json
{
  "type": "picker",
  "content": {
    "properties": {
      "displayMode": "menu",
      "placeholder": "Choose a color",
      "options": [
        { "value": "red", "label": "Red", "icon": "circle.fill" },
        { "value": "blue", "label": "Blue", "icon": "circle.fill" }
      ],
      "bindVariable": "selectedColor"
    }
  }
}
```

## See Also

- [Forms & Inputs](../forms.md)
- [DatePicker](date-picker.md) — for dates and times
- [variables.md](../variables.md) — binding and expressions
