# Components

Components are the building blocks of App8 DSL interfaces.

## Component Structure

Every component shares the same envelope:

<!-- @dsl-skip: generic structure example -->
```json
{
  "type": "componentType",
  "id": "optionalId",
  "templateId": "optionalTemplateRef",
  "content": { }
}
```

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `type` | string | Yes | Component type |
| `id` | string | No | Unique identifier for references |
| `templateId` | string | No | Template to inherit from ([templates.md](templates.md)) |
| `content` | object | Yes | Type-specific content |

`content` is where each component differs, but most components accept these shared keys:

| Key | Description | See |
|-----|-------------|-----|
| `properties` | Type-specific values (text, url, data, …) | Per-component doc below |
| `style` | Visual styling | [styles.md](styles.md) |
| `layout` | Position and size constraints | [layout.md](layout.md) |
| `actions` | Event handlers | [actions.md](actions.md) |
| `variables` | Component-scoped variables | [variables.md](variables.md) |
| `states` / `triggers` | State machine | [states.md](states.md) |
| `children` | Nested components (containers only) | — |

---

## Component Reference

Each component type has its own reference doc with its `properties`, styling, and examples.

| Type | Description | Docs |
|------|-------------|------|
| `screen` | Top-level screen container | [components/screen.md](components/screen.md) |
| `view` | General-purpose container | [components/view.md](components/view.md) |
| `label` | Text display | [components/label.md](components/label.md) |
| `button` | Interactive button | [components/button.md](components/button.md) |
| `image` | Image display | [components/image.md](components/image.md) |
| `icon` | SF Symbol display | [components/icon.md](components/icon.md) |
| `textField` | Single-line text input | [components/text-field.md](components/text-field.md) |
| `textView` | Multi-line text input | [components/text-view.md](components/text-view.md) |
| `scrollView` | Scrollable container | [components/scroll-view.md](components/scroll-view.md) |
| `stackView` | Linear layout container | [components/stack-view.md](components/stack-view.md) |
| `tabBarScreen` | Tab-based navigation | [components/tab-bar-screen.md](components/tab-bar-screen.md) |
| `collection` | Lists, grids, carousels | [collections.md](collections.md) |
| `map` | Interactive map with annotations and routing | [components/map.md](components/map.md) |
| `shape` | Arc rings, bars, circles, dividers | [components/shape.md](components/shape.md) |
