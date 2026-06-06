# DatePicker

A native date/time selector (`UIDatePicker`). Two-way bound to a string variable holding an ISO date.

## Content Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `properties.selectedDate` | string/expression | | Current date as ISO8601 or `"yyyy-MM-dd"`. Accepts an expression |
| `properties.bindVariable` | string | | Variable name for two-way binding (no `{{}}`) |
| `properties.datePickerMode` | Mode | `date` | What to pick — see [Modes](#mode-values) |
| `properties.displayStyle` | DisplayStyle | `compact` | How it renders — see [Display Styles](#displaystyle-values) |
| `properties.minimumDate` | string | | Earliest selectable date (ISO8601 or `"yyyy-MM-dd"`) |
| `properties.maximumDate` | string | | Latest selectable date |
| `properties.isEnabled` | boolean/expression | `true` | Whether the picker accepts input |
| `hidden` | boolean/expression | | Hide component |

> **Storage format**: the picker writes the selected value back to the bound variable as a `"yyyy-MM-dd"` string. Format it for display with [`formatDate`](../variables.md#date--time), e.g. `"{{formatDate(startDate, 'medium')}}"`.

> **Binding vs. value**: set `bindVariable` to the bare variable **name**; set `selectedDate` to an **expression**. See [variables.md → Variable Binding](../variables.md#variable-binding).

## Mode Values

| Value | Picks |
|-------|-------|
| `date` | Calendar date only (default) |
| `time` | Time of day only |
| `dateAndTime` | Both date and time |
| `countdownTimer` | Hours and minutes duration |

## DisplayStyle Values

| Value | Appearance |
|-------|------------|
| `compact` | Tappable pill that expands on tap (default) |
| `inline` | Always-visible calendar/clock |
| `wheels` | Classic spinning wheels |

## Style: DatePickerStyle

| Property | Type | Description |
|----------|------|-------------|
| `tintColor` | Color | Accent color for selected day / controls |
| `material` | Material | Background |
| `alpha` | number | Opacity (0.0–1.0) |
| `contentMode` | ContentMode | Content alignment |

## Example

```json
{
  "type": "datePicker",
  "id": "startDate",
  "content": {
    "properties": {
      "datePickerMode": "date",
      "displayStyle": "compact",
      "bindVariable": "startDate",
      "minimumDate": "2026-01-01",
      "maximumDate": "2026-12-31"
    },
    "style": { "tintColor": "#007AFF" },
    "layout": { "trailing": 20, "centerY": 0 }
  }
}
```

## See Also

- [Forms & Inputs](../forms.md)
- [Picker](picker.md) — for non-date choices
- [variables.md → Date & Time](../variables.md#date--time) — formatting the stored value
