# TableView

A static, grouped list (`UITableView`) whose sections and rows are defined inline in the DSL — no datasource required. Each row hosts arbitrary DSL components in its cell.

Use `tableView` for **settings-style screens** and short fixed lists where you author every row by hand. For **data-driven** lists, grids, or carousels that repeat a template over a variable array, use a [collection](../collections.md) instead.

## Content Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `properties.tableStyle` | TableStyle | `insetGrouped` | Visual grouping — see [Table Styles](#tablestyle-values) |
| `properties.showsIndicator` | boolean | `true` | Show the scroll indicator |
| `properties.separatorInset` | number | `0` | Leading inset for row separators |
| `sections` | Section[] | `[]` | The sections, in order |
| `hidden` | boolean/expression | | Hide component |

`tableView` also supports `style`, `layout`, `variables`, `states`/`triggers`, and `onEvent` like other components.

## TableStyle Values

| Value | Appearance |
|-------|------------|
| `plain` | Edge-to-edge rows, sticky section headers |
| `grouped` | Grouped sections on a full-width background |
| `insetGrouped` | Rounded, inset cards per section (default) |

## Section

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique section identifier |
| `header` | string | No | Header text above the section |
| `footer` | string | No | Footer text below the section |
| `rows` | Row[] | No | The rows in this section |

## Row

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique row identifier |
| `height` | number | No | Fixed row height (auto-sizes if omitted) |
| `clearBackground` | boolean | No | Transparent cell (no card) — handy for footer-style rows |
| `children` | Component[] | No | DSL components rendered into the cell |
| `actions` | `{ tap: Action[] }` | No | Actions run when the row is tapped |
| `analytics` | `{ tap: AnalyticsBinding }` | No | Author-declared analytics for the row tap |

> **Row taps** fire the auto `app8.component.tapped` analytics event tagged with the row's own `id`, then run the row's `tap` actions. Add an `analytics.tap` binding to emit a custom event too — see [analytics.md](../analytics.md). Only `tap` is meaningful at the row level.

## Example

A settings screen with two sections:

```json
{
  "type": "tableView",
  "id": "settings",
  "content": {
    "properties": { "tableStyle": "insetGrouped" },
    "layout": { "leading": 0, "trailing": 0, "top": 0, "bottom": 0 },
    "sections": [
      {
        "id": "account",
        "header": "Account",
        "rows": [
          {
            "id": "profile",
            "height": 56,
            "actions": { "tap": [{ "type": "navigation", "nextScreen": "editProfile" }] },
            "children": [
              {
                "type": "label",
                "content": {
                  "properties": { "text": "Edit Profile" },
                  "layout": { "leading": 16, "centerY": 0 }
                }
              }
            ]
          },
          {
            "id": "notifications",
            "children": [
              {
                "type": "label",
                "content": { "properties": { "text": "Notifications" }, "layout": { "leading": 16, "centerY": 0 } }
              },
              {
                "type": "toggle",
                "content": {
                  "properties": { "bindVariable": "notificationsOn" },
                  "layout": { "trailing": 16, "centerY": 0 }
                }
              }
            ]
          }
        ]
      },
      {
        "id": "danger",
        "footer": "This cannot be undone.",
        "rows": [
          {
            "id": "signout",
            "actions": { "tap": [{ "type": "emit", "name": "signOut.tapped" }] },
            "children": [
              {
                "type": "label",
                "content": {
                  "properties": { "text": "Sign Out" },
                  "style": { "text": { "id": "destructive", "type": "text", "content": { "color": "#FF3B30" } } },
                  "layout": { "centerX": 0, "centerY": 0 }
                }
              }
            ]
          }
        ]
      }
    ]
  }
}
```

## See Also

- [Collections](../collections.md) — data-driven lists, grids, and carousels
- [Actions](../actions.md) — what a row tap can do
- [Analytics](../analytics.md) — per-row analytics bindings
