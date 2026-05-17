# Collections — Best Practices

Practical guidance for building correct, polished, and performant collection screens.

---

## Choosing a Layout Type

| Use case | Layout type | Key settings |
|----------|-------------|-------------|
| Settings list, contacts, feed | `vertical` | `itemSpacing: 0`, `separatorStyle: "inset"` |
| Photo/product grid | `grid` | `columns`, `aspectRatio` or `itemHeight` |
| Horizontally scrolling cards | `horizontal` | `itemWidth`, `itemHeight`, `pagingStyle` |
| Full-screen paged slides / onboarding | `horizontal` | `pagingStyle: "paging"`, `itemWidth` = screen width |
| Centered carousel with peek | `horizontal` | `pagingStyle: "pagingCentered"`, `contentInsets`, `itemWidth` < screen width |
| Chat / reverse-chronological | `vertical` + `inverted: true` | `contentInsets` for breathing room |

**Rule:** Never use `vertical` for a carousel — it fights UIKit's compositing model and breaks momentum scrolling.

---

## Content Insets

`contentInsets` controls the padding around all items inside the scrollable area. It is not the same as the collection's external `layout` — it shifts where items start and end within the scroll content.

### Horizontal carousels

Always add `left` + `right` insets to create the "peek" effect (partial next/previous item visible):

```json
{
  "layout": {
    "type": "horizontal",
    "itemWidth": 280,
    "itemSpacing": 16,
    "pagingStyle": "pagingCentered",
    "contentInsets": { "left": 24, "right": 24 }
  }
}
```

The inset must equal `(screenWidth - itemWidth) / 2` when you want the center item to be exactly centered. For asymmetric peek use unequal values.

### Vertical lists

Use `top` and `bottom` insets to add breathing room between the list edge and surrounding UI, especially when a list sits below a navigation bar or above a tab bar:

```json
"contentInsets": { "top": 8, "bottom": 24 }
```

Do not use `left`/`right` insets on vertical lists to indent all items — put horizontal padding inside the template instead. This keeps tap targets full-width and separators flush.

### Standard inset values

All inset values must be multiples of 4.

| Purpose | Value |
|---------|-------|
| Screen edge horizontal margin | 24pt |
| Section breathing room (top/bottom) | 16pt |
| Tight card gap | 8pt |
| No inset | omit the key (defaults to 0) |

---

## Item Spacing

| Layout | Recommended `itemSpacing` | Notes |
|--------|--------------------------|-------|
| Settings / compact list | 0 | Rely on separators |
| Card list | 12–16pt | Enough to see card edges |
| Tight grid (photos) | 2–4pt | Emphasizes the grid |
| Loose grid (products) | 12–16pt | Breathes more |
| Horizontal carousel | 12–16pt | Also set `contentInsets` |

For grids, `lineSpacing` controls the gap between rows. Set it equal to `itemSpacing` for a square grid.

---

## Sizing Items

### Fixed size

Best for carousels and grids where items are uniform:

```json
"itemWidth": 160,
"itemHeight": 200
```

### Aspect ratio

For grids where columns determine item width and height should derive from it:

```json
"columns": 2,
"aspectRatio": 1.33
```

`aspectRatio = width / height`. A landscape card (3:2) = `1.5`. A portrait photo (2:3) = `0.67`.

### Self-sizing (vertical lists)

Omit `itemHeight` and let the template define its own height via constraints. Always provide `estimatedItemHeight` to avoid layout thrashing:

```json
"estimatedItemHeight": 72
```

Set this to the typical height of most items. An accurate estimate improves scroll performance — the collection view uses it to pre-calculate content size before all cells are rendered.

---

## Section Headers

### Use `defaultSectionHeader` for uniform headers

When all sections use the same header format (e.g., an alphabetical contacts list):

```json
{
  "properties": {
    "groupBy": "item.section",
    "stickyHeaders": true
  },
  "defaultSectionHeader": {
    "type": "view",
    "content": {
      "style": { "backgroundColor": "#F2F2F7" },
      "layout": { "height": 28 },
      "children": [
        {
          "type": "label",
          "content": {
            "properties": { "text": "{{section.key}}" },
            "style": { "text": { "fontSize": 13, "fontWeight": "semibold", "color": "#6D6D72" } },
            "layout": { "leading": 16, "centerY": 0 }
          }
        }
      ]
    }
  }
}
```

### Use `sectionHeaders` map for per-section overrides

When specific sections need different header treatment:

```json
{
  "sectionHeaders": {
    "featured": {
      "type": "view",
      "content": {
        "layout": { "height": 48 },
        "children": [
          {
            "type": "label",
            "content": {
              "properties": { "text": "Featured" },
              "style": { "text": { "fontSize": 20, "fontWeight": "bold" } },
              "layout": { "leading": 16, "centerY": 0 }
            }
          }
        ]
      }
    }
  }
}
```

`sectionHeaders[key]` takes precedence over `defaultSectionHeader` for matching sections. All unmatched sections fall back to `defaultSectionHeader`.

### Header sizing

Always give headers an explicit `height` constraint. Self-sizing headers are not supported — a header without a height will collapse to zero.

### Sticky headers

Enable `stickyHeaders: true` when the list is long enough that losing context of the current section is disorienting (alphabetical lists, grouped settings, date-bucketed feeds). For short lists or carousels, leave it off.

---

## Data Sources

### Prefer `data` over inline `initialValue` arrays

For static data, declare the array as a variable with `initialValue` and bind with `data`:

```json
{
  "variables": {
    "menuItems": {
      "type": "array",
      "initialValue": [
        { "id": "1", "label": "Profile", "icon": "person" },
        { "id": "2", "label": "Settings", "icon": "gear" }
      ]
    }
  }
}
```

```json
{
  "properties": { "data": "{{menuItems}}" }
}
```

This makes the data replaceable at runtime (e.g., via a function that updates the variable) without changing the collection structure.

### Use `sectionDefinitions` for truly independent sections

When sections pull from different variables that change independently, use `sectionDefinitions`. Do not use `groupBy` as a workaround for independent data — it re-groups a single array and won't reflect independent variable updates correctly.

```json
"sectionDefinitions": [
  { "key": "pinned",   "data": "{{pinnedItems}}",   "templateName": "PinnedRow" },
  { "key": "recent",  "data": "{{recentItems}}",   "templateName": "StandardRow" },
  { "key": "archived","data": "{{archivedItems}}", "templateName": "StandardRow" }
]
```

### Use `groupBy` for dynamic categorization of a single array

When the grouping key is a property on the items themselves and the entire array comes from one source:

```json
"groupBy": "item.category"
```

---

## Templates

### Inline template: use when the template is unique to this collection

Inline templates live inside `"template": { ... }` at the content level. Use them when the cell design is specific to this screen and won't be reused anywhere else.

### Named template reference: use when the cell is reused

Reference a registered app-level template by name via `properties.templateName`:

```json
"properties": { "templateName": "ContactRow" }
```

The template must be registered in the app's `templates` array. This is the preferred approach for any cell that appears in more than one collection.

### Heterogeneous templates: key must be a string-coercible property

When items have different types, `templateKey` must resolve to a string for each item. If you use a boolean property, the effective keys are `"true"` and `"false"`:

```json
{
  "properties": { "templateKey": "item.isPro" },
  "templates": { "true": "ProCard", "false": "StandardCard" }
}
```

Always define a `"default"` fallback key to handle unexpected values:

```json
"templates": {
  "post": "PostCard",
  "ad": "AdBanner",
  "default": "PostCard"
}
```

---

## Pagination and Pull-to-Refresh

### Pagination

Set `threshold` to trigger `onLoadMore` before the user hits the end. A value of 5 (the default) is appropriate for most cases. For fast-loading, short lists, raise it to 10 to trigger earlier.

```json
"pagination": { "threshold": 5 }
```

The `onLoadMore` action is responsible for appending new items to the data variable. The collection does not manage loading state — your function must update `screenState` and append to the array variable.

### Pull to Refresh

Always pair `pullToRefresh: true` with an `onRefresh` action. The refresh control is dismissed when the data variable updates — your `onRefresh` function should reset the array variable, not append to it.

```json
{
  "properties": { "pullToRefresh": true },
  "actions": {
    "onRefresh": { "type": "executeFunction", "function": "reload" }
  }
}
```

---

## Nested Collections

When a collection appears inside another collection's template (e.g., a horizontal row inside a vertical list):

- The inner collection's scroll direction **must differ** from the outer collection's direction
- The inner collection **must have a fixed height** via its `layout.height` constraint — self-sizing is not supported for nested collections
- Bind inner data to a property on the outer item: `"data": "{{item.subItems}}"`

```json
{
  "type": "collection",
  "content": {
    "properties": { "data": "{{item.photos}}" },
    "layout": {
      "type": "horizontal",
      "itemWidth": 120,
      "itemHeight": 120,
      "itemSpacing": 8
    },
    "layout": { "leading": 0, "trailing": 0, "height": 136 }
  }
}
```

> Note: `layout` here refers to the collection component's layout constraints (position/size within its parent), while the `layout` inside `content.properties` controls item arrangement within the collection. Both keys are valid and serve different purposes.

---

## Empty, Loading, and Error States

Provide all three states for any collection that loads data asynchronously. Use a `screenState` variable to toggle between them:

```json
"variables": {
  "screenState": { "type": "string", "initialValue": "loading" }
}
```

```json
{
  "emptyState": { ... },     // shown when data.length == 0 after load
  "loadingState": { ... },   // shown while fetch is in flight
  "errorState": { ... }      // shown on fetch failure
}
```

The collection automatically shows the appropriate state based on `isLoading`, `isEmpty`, and `error` signals from the ViewModel. You do not need to `hidden`-toggle them manually — just provide the component trees.

**Always include a retry button in `errorState`** wired to the same load function as the `appear` event.

---

## Scroll Behavior

### Scroll indicators

- Vertical lists: leave `showsScrollIndicator` at its default (`true`) — users expect it
- Horizontal carousels: set `showsScrollIndicator: false` — the indicator is visually disruptive on carousels
- Full-screen grids: `true` is appropriate; for photo grids where the indicator is distracting, `false` is acceptable

### Scroll offset tracking

Use `scrollOffsetVariable` when other UI elements need to react to scroll position (e.g., collapsing a header, parallax, hiding a floating button):

```json
"scrollOffsetVariable": "scrollY"
```

The value is in points, adjusted for content insets, updated in real time. Bind it to opacity, transform, or `hidden` on other components.

### Inverted lists

For chat-style lists where the most recent item appears at the bottom, set `inverted: true`. The collection flips its coordinate system — data index 0 appears at the bottom. Your data array should be ordered newest-first.

```json
{
  "properties": {
    "data": "{{messages}}",
    "inverted": true
  },
  "layout": {
    "type": "vertical",
    "itemSpacing": 8,
    "contentInsets": { "top": 12, "bottom": 12 }
  }
}
```

---

## Common Mistakes

| Mistake | Correct approach |
|---------|-----------------|
| `left`/`right` insets on a vertical list to indent items | Put horizontal padding inside the template |
| No `estimatedItemHeight` on self-sizing cells | Always set it — saves a layout pass |
| Self-sizing nested collection height | Always set an explicit `height` on the inner collection |
| `groupBy` for independent data sources | Use `sectionDefinitions` instead |
| No `"default"` key in heterogeneous `templates` | Add `"default": "FallbackTemplate"` |
| `showsScrollIndicator: true` on a horizontal carousel | Set it to `false` |
| Section header without a `height` constraint | Always give headers a fixed `height` |
| `pagingEnabled: true` or `snapToItem: true` | Use `pagingStyle` (`"paging"` or `"pagingCentered"`) instead — these legacy flags are accepted but deprecated |
| Same scroll direction in nested collections | Inner collection direction must differ from outer |
