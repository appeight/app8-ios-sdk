# App8 DSL Reference

App8 DSL is a JSON-based declarative UI definition language that renders to native UIKit components. It supports reactive variables, state management, and flow-based navigation.

## Document Conventions

- `[Planned]` - Feature designed but not yet implemented
- `[Partial]` - Feature partially implemented
- JSON examples use standard JSON syntax

## Quick Start

A minimal app with one screen and a button:

```json
{
  "app": {
    "name": "MyApp"
  },
  "navigation": {
    "startFlow": "main",
    "flows": [
      { "id": "main", "startScreen": "home" }
    ]
  },
  "screens": {
    "home": {
      "type": "screen",
      "content": {
        "navigationBar": { "title": "Home" },
        "variables": {
          "count": { "type": "number", "initialValue": 0 }
        },
        "children": [
          {
            "type": "label",
            "content": {
              "properties": { "text": "Count: {{count}}" },
              "style": { "text": { "id": "countLabel", "type": "text", "content": { "fontSize": 24, "alignment": "center" } } },
              "layout": { "leading": 20, "trailing": 20, "top": 100 }
            }
          },
          {
            "type": "button",
            "content": {
              "properties": { "text": "Increment" },
              "layout": { "centerX": 0, "top": 160, "width": 200, "height": 50 },
              "actions": {
                "tap": {
                  "type": "incrementVariable",
                  "variableName": "count",
                  "by": 1
                }
              }
            }
          }
        ]
      }
    }
  }
}
```

## App Structure

```json
{
  "app": {
    "name": "AppName",
    "variables": { }
  },
  "navigation": {
    "startFlow": "flowId",
    "flows": [ ]
  },
  "screens": { },
  "templates": [ ]
}
```

| Key | Description |
|-----|-------------|
| `app` | App metadata and global variables |
| `navigation` | Flow definitions and start flow |
| `screens` | Screen definitions by ID |
| `templates` | Reusable component templates |

## Component Types

**Layout & containers**

| Type | Description | See |
|------|-------------|-----|
| `screen` | Top-level screen container | [components/screen.md](components/screen.md) |
| `view` | General-purpose container | [components/view.md](components/view.md) |
| `stackView` | Linear layout container | [components/stack-view.md](components/stack-view.md) |
| `scrollView` | Scrollable container | [components/scroll-view.md](components/scroll-view.md) |
| `tabBarScreen` | Tab-based navigation | [components/tab-bar-screen.md](components/tab-bar-screen.md) |

**Content & display**

| Type | Description | See |
|------|-------------|-----|
| `label` | Text display | [components/label.md](components/label.md) |
| `button` | Interactive button | [components/button.md](components/button.md) |
| `image` | Image display | [components/image.md](components/image.md) |
| `icon` | SF Symbol, asset, or remote icon | [components/icon.md](components/icon.md) |
| `map` | Interactive map with annotations and routing | [components/map.md](components/map.md) |
| `shape` | Arc rings, bars, circles, dividers | [components/shape.md](components/shape.md) |

**Lists**

| Type | Description | See |
|------|-------------|-----|
| `collection` | Data-driven lists, grids, carousels | [collections.md](collections.md) |
| `tableView` | Static grouped/settings lists | [components/table-view.md](components/table-view.md) |

**Inputs** — see [forms.md](forms.md) for putting these together

| Type | Description | See |
|------|-------------|-----|
| `textField` | Single-line text input | [components/text-field.md](components/text-field.md) |
| `textView` | Multi-line text input | [components/text-view.md](components/text-view.md) |
| `toggle` | On/off switch | [components/toggle.md](components/toggle.md) |
| `slider` | Numeric slider | [components/slider.md](components/slider.md) |
| `picker` | Single-choice menu / segmented control | [components/picker.md](components/picker.md) |
| `datePicker` | Date / time selector | [components/date-picker.md](components/date-picker.md) |

**Feedback & loading**

| Type | Description | See |
|------|-------------|-----|
| `activityIndicator` | Spinner for indeterminate waits | [components/activity-indicator.md](components/activity-indicator.md) |
| `shimmer` | Skeleton loading placeholder | [components/shimmer.md](components/shimmer.md) |
| `pageControl` | Page-indicator dots | [components/page-control.md](components/page-control.md) |

## Style Types

| Type | Purpose | See |
|------|---------|-----|
| `color` | Hex color with theme support | [styles.md](styles.md#color) |
| `fill` | Solid or gradient background | [styles.md](styles.md#fill) |
| `material` | Composition of visual layers | [styles.md](styles.md#material) |
| `outline` | Border/stroke styling | [styles.md](styles.md#outline) |
| `shadow` | Drop shadow | [styles.md](styles.md#shadow) |
| `corner` | Corner radius | [styles.md](styles.md#corner) |
| `visualEffect` | Blur effects | [styles.md](styles.md#visualeffect) |
| `text` | Typography styling | [styles.md](styles.md#text-textmodel) |
| `transform` | View transformations | [styles.md](styles.md#transform) |

## Action Types

| Type | Purpose | See |
|------|---------|-----|
| `navigation` | Navigate to screen | [actions.md](actions.md#navigation-actions) |
| `dismiss` | Close modal | [actions.md](actions.md#dismiss-modal) |
| `completeFlow` | Finish flow, go to destination | [actions.md](actions.md#complete-flow) |
| `selectTab` | Switch tab | [actions.md](actions.md#select-tab) |
| `updateVariable` | Set variable value | [actions.md](actions.md#variable-actions) |
| `incrementVariable` | Add to number | [actions.md](actions.md#increment-number) |
| `toggleArrayValue` | Add/remove from array | [actions.md](actions.md#toggle-array-value) |
| `appendToArray` | Append to array | [actions.md](actions.md#append-to-array) |
| `updateMultipleVariables` | Batch update variables | [actions.md](actions.md#update-multiple-variables) |
| `resetVariables` | Reset to initial values | [actions.md](actions.md#reset-variables) |
| `executeFunction` | Call backend function | [actions.md](actions.md#function-actions) |
| `setState` | Change component state | [actions.md](actions.md#state-actions) |
| `focus` | Focus component | [actions.md](actions.md#focus-actions) |
| `focusNext` | Focus next focusable | [actions.md](actions.md#focus-actions) |
| `focusPrevious` | Focus previous focusable | [actions.md](actions.md#focus-actions) |
| `dismissKeyboard` | Close keyboard | [actions.md](actions.md#focus-actions) |
| `showAlert` | Present a native alert | [actions.md](actions.md#show-alert) |
| `haptic` | Trigger haptic feedback | [actions.md](actions.md#haptic) |
| `openURL` | Open a URL | [actions.md](actions.md#open-url) |
| `emit` | Fire typed event to the host event bus | [events.md](events.md) |

## Expression Syntax

Expressions use `{{...}}` syntax:

```json
"text": "{{userName}}"
"text": "{{user.profile.name}}"
"text": "{{items[0].title}}"
"value": "{{count + 1}}"
"hidden": "{{!isVisible}}"
"icon": "{{isLiked ? 'heart.fill' : 'heart'}}"
```

See [variables.md](variables.md) for full expression documentation.

## Documentation Index

**Core reference**

- [components.md](components.md) - All component types and properties
- [styles.md](styles.md) - Style system (colors, materials, text, content modes, etc.)
- [layout.md](layout.md) - Layout and constraint system
- [variables.md](variables.md) - Variables and expression syntax
- [actions.md](actions.md) - Actions and event triggers
- [navigation.md](navigation.md) - Navigation and flow system
- [transitions.md](transitions.md) - Screen transitions (presets, custom keyframes, registry, interactive) and shared-element / hero / composite morphs

**Building interfaces**

- [forms.md](forms.md) - Inputs, two-way binding, validation, and loading states
- [collections.md](collections.md) - Lists, grids, and carousels
- [collections-best-practices.md](collections-best-practices.md) - Layout choice, insets, headers, templates, and common mistakes
- [states.md](states.md) - Component states and animations
- [animations.md](animations.md) - Animation primitive (timing, springs, registry, per-property)
- [templates.md](templates.md) - Reusable component templates
- [localization.md](localization.md) - Translations, the `$i18n` marker, locale fallback

**Host & analytics**

- [host-integration.md](host-integration.md) - Data sources, datasources, assets, streaming, and event wiring
- [events.md](events.md) - Host-facing event bus (`.emit` action + subscribe API)
- [analytics.md](analytics.md) - Analytics bus (auto `app8.*` + author-declared `analytics` binding, SDK auto-prefixed)
- [analytics-events.spec.md](analytics-events.spec.md) - Canonical registry of every auto-fired event (cross-platform contract)
