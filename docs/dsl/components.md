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
| `gestures` | Continuous gesture → variable bindings | [gestures.md](gestures.md) |
| `interaction` | Touch / clipping / z-order overrides | [Interaction](#interaction) below |
| `accessibility` | VoiceOver metadata | [Accessibility](#accessibility) below |
| `variables` | Component-scoped variables | [variables.md](variables.md) |
| `states` / `triggers` | State machine | [states.md](states.md) |
| `children` | Nested components (containers only) | — |

---

## Interaction

The optional `content.interaction` block overrides touch handling, clipping, and
z-ordering on **any** component. All fields accept a literal (`"true"`, `"2"`) or a
`{{expression}}` and re-evaluate reactively when variables change.

| Field | Type | Description |
|-------|------|-------------|
| `enabled` | boolean/expression | Explicit `isUserInteractionEnabled`. By default a component only handles touches when it declares `actions` / `triggers` / `gestures`; set this to force-enable a passive container or force-disable an otherwise-interactive subtree. |
| `clipsToBounds` | boolean/expression | Clip children to the component's bounds. |
| `zIndex` | number/expression | Raise/lower the component among its siblings (maps to `layer.zPosition`) without reordering the hierarchy. |

```json
{
  "type": "view",
  "content": {
    "interaction": { "enabled": "{{editing}}", "clipsToBounds": "true", "zIndex": "10" }
  }
}
```

## Accessibility

The optional `content.accessibility` block sets VoiceOver metadata on any component.
String fields accept a literal or `{{expression}}`. (`accessibilityIdentifier` is set
automatically from the component `id`.)

| Field | Type | Description |
|-------|------|-------------|
| `label` | string/expression | Spoken label. |
| `hint` | string/expression | Spoken hint. |
| `value` | string/expression | Spoken value (e.g. a slider's current value). |
| `traits` | string[] | Accessibility traits — e.g. `["button", "header"]`. See values below. |
| `isElement` | boolean/expression | Override `isAccessibilityElement`. |
| `hidden` | boolean/expression | Hide from accessibility (`accessibilityElementsHidden`). |

Trait values: `button`, `link`, `header`, `image`, `selected`, `disabled`,
`adjustable`, `searchField`, `staticText`, `summaryElement`, `updatesFrequently`,
`startsMediaSession`, `allowsDirectInteraction`.

```json
{
  "type": "image",
  "content": {
    "accessibility": { "label": "Profile photo", "hint": "Double tap to change", "traits": ["button"] }
  }
}
```

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
| `video` | Looping background video (local asset) | [components/video.md](components/video.md) |
| `icon` | SF Symbol, asset, or remote icon | [components/icon.md](components/icon.md) |
| `textField` | Single-line text input | [components/text-field.md](components/text-field.md) |
| `textView` | Multi-line text input | [components/text-view.md](components/text-view.md) |
| `toggle` | On/off switch | [components/toggle.md](components/toggle.md) |
| `slider` | Numeric slider | [components/slider.md](components/slider.md) |
| `picker` | Single-choice menu / segmented control | [components/picker.md](components/picker.md) |
| `datePicker` | Date / time selector | [components/date-picker.md](components/date-picker.md) |
| `scrollView` | Scrollable container | [components/scroll-view.md](components/scroll-view.md) |
| `stackView` | Linear layout container | [components/stack-view.md](components/stack-view.md) |
| `tabBarScreen` | Tab-based navigation | [components/tab-bar-screen.md](components/tab-bar-screen.md) |
| `collection` | Data-driven lists, grids, carousels | [collections.md](collections.md) |
| `tableView` | Static grouped/settings lists | [components/table-view.md](components/table-view.md) |
| `map` | Interactive map with annotations and routing | [components/map.md](components/map.md) |
| `shape` | Arc rings, bars, circles, dividers | [components/shape.md](components/shape.md) |
| `activityIndicator` | Spinner for indeterminate waits | [components/activity-indicator.md](components/activity-indicator.md) |
| `shimmer` | Skeleton loading placeholder | [components/shimmer.md](components/shimmer.md) |
| `pageControl` | Page-indicator dots | [components/page-control.md](components/page-control.md) |

These cover the building blocks; [forms.md](forms.md) shows how to combine the input components, and [host-integration.md](host-integration.md) covers how the host feeds them data.
