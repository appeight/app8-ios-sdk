# Actions & Events

Actions are triggered by user interactions or lifecycle events.

> **Forwarding events to the host?** See [events.md](events.md) for the `.emit` action and the typed `App8.Instance.subscribe(...)` API. See [analytics.md](analytics.md) for the analytics bus.

## Action Triggers

### Component Actions

```json
{
  "actions": {
    "tap": { "type": "navigation", "nextScreen": "details" }
  }
}
```

A trigger may also list **multiple actions** to run in JSON order:

```json
{
  "actions": {
    "tap": [
      { "type": "emit",       "name": "checkout.started", "payload": { "cart": "{{cartId}}" } },
      { "type": "navigation", "nextScreen": "confirm" }
    ]
  }
}
```

### Trigger Types

| Trigger | Components | When Fired |
|---------|------------|------------|
| `tap` | Button, View | User taps |
| `longPress` | Button, View | User long-presses |
| `onTextChange` | TextField, TextView | Text value changes |
| `onItemTap` | Collection | Collection item tapped |
| `onRefresh` | Collection | Pull-to-refresh triggered |
| `onLoadMore` | Collection | Pagination threshold reached |
| `onSelectionChange` | Collection | Selection changed |
| `onScrollThreshold` | ScrollView | Scroll crosses a configured threshold |
| `onAnnotationTap` | Map | Map annotation tapped |
| `onRegionChange` | Map | Visible map region changed |
| `onUserLocationUpdate` | Map | User location updated |
| `onVideoReady` | Video | Item is ready to play (before first frame) |
| `onVideoStart` | Video | Playback starts (first time it begins playing) |
| `onVideoPause` | Video | Playback pauses |
| `onVideoComplete` | Video | A non-looping clip plays to its end |
| `onVideoLoop` | Video | A looping clip completes a cycle (overlay `$loopCount`) |
| `onVideoStall` | Video | Playback stalls waiting to buffer |
| `onVideoError` | Video | The item fails to load/decode (overlay `$error`) |
| `onTimeMark` | Video | Playback crosses a configured `marks` time (overlay `$markId`) |

> Every trigger in this table also accepts an `analytics:` map alongside `actions:` — the engine fires the analytics binding regardless of whether `actions` is present. See [`analytics.md`](analytics.md).

---

## Navigation Actions

### Navigate to Screen

```json
{
  "type": "navigation",
  "nextScreen": "profileScreen",
  "params": { "userId": "{{selectedId}}" },
  "presentation": "push"
}
```

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `nextScreen` | string | | Screen ID to navigate to |
| `params` | object | | Parameters to pass |
| `presentation` | Presentation | `push` | Presentation style |
| `transition` | Transition | | Custom screen transition — see [transitions.md](transitions.md) |

### Presentation Styles

| Style | Description |
|-------|-------------|
| `push` | Standard navigation push (default) |
| `sheet` | iOS-style bottom sheet with detents |
| `fullScreen` | Full screen modal |
| `formSheet` | Smaller modal (iPad-optimized) |
| `pageSheet` | Page sheet modal |
| `crossDissolve` | Full screen modal with a fade transition |

### Examples

```json
{
  "type": "navigation",
  "nextScreen": "details"
}
```

```json
{
  "type": "navigation",
  "nextScreen": "editProfile",
  "presentation": "sheet"
}
```

```json
{
  "type": "navigation",
  "nextScreen": "fullScreenImage",
  "params": { "imageUrl": "{{item.imageUrl}}" },
  "presentation": "fullScreen"
}
```

### Dismiss Modal

Close the current modal screen.

```json
{
  "type": "dismiss"
}
```

### Complete Flow

Finish current flow and navigate to another flow.

```json
{
  "type": "completeFlow",
  "destination": "main"
}
```

| Property | Type | Description |
|----------|------|-------------|
| `destination` | string | Flow ID to navigate to |

### Select Tab

Switch to a tab in TabBarScreen.

By ID:
```json
{
  "type": "selectTab",
  "tabId": "profile"
}
```

By index:
```json
{
  "type": "selectTab",
  "tabIndex": 2
}
```

---

## Variable Actions

### Update Single Variable

```json
{
  "type": "updateVariable",
  "variableName": "count",
  "value": "{{count + 1}}"
}
```

| Property | Type | Description |
|----------|------|-------------|
| `variableName` | string | Variable to update |
| `value` | any/expression | New value |

### Increment Number

```json
{
  "type": "incrementVariable",
  "variableName": "count",
  "by": 1
}
```

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `variableName` | string | | Variable to increment |
| `by` | number | 1 | Amount to add |

### Toggle Array Value

Add value if missing, remove if present.

```json
{
  "type": "toggleArrayValue",
  "variableName": "selectedIds",
  "value": "{{item.id}}"
}
```

| Property | Type | Description |
|----------|------|-------------|
| `variableName` | string | Array variable |
| `value` | any/expression | Value to toggle |

For arrays of objects, use `matchBy` to identify entries by key (e.g. `"matchBy": "id"`).

### Append To Array

Append a value to the end of an array variable (no de-duplication).

```json
{
  "type": "appendToArray",
  "variableName": "messages",
  "value": "{{draftText}}"
}
```

| Property | Type | Description |
|----------|------|-------------|
| `variableName` | string | Array variable |
| `value` | any/expression | Value to append |

### Update Multiple Variables

```json
{
  "type": "updateMultipleVariables",
  "updates": {
    "isLoading": false,
    "hasError": true,
    "errorMessage": "Failed to load"
  }
}
```

| Property | Type | Description |
|----------|------|-------------|
| `updates` | object | Key-value pairs to update |

### Reset Variables

Reset variables to initial values.

```json
{
  "type": "resetVariables",
  "scope": "screen"
}
```

| Property | Type | Description |
|----------|------|-------------|
| `scope` | Scope | Which variables to reset |

### Scope Values

| Value | Description |
|-------|-------------|
| `component` | Component's local variables |
| `screen` | Current screen's variables |
| `app` | App-level variables |
| `all` | All variables |

---

## State Actions

### Set Component State

```json
{
  "type": "setState",
  "stateName": "active",
  "animated": true
}
```

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `stateName` | string | | State to transition to |
| `animated` | boolean | true | Animate transition |

See [states.md](states.md) for state definitions.

---

## Focus Actions

### Focus Specific Component

```json
{
  "type": "focus",
  "target": "emailField"
}
```

| Property | Type | Description |
|----------|------|-------------|
| `target` | string | Component ID to focus |

### Focus Next

Move focus to next focusable component.

```json
{
  "type": "focusNext"
}
```

### Focus Previous

Move focus to previous focusable component.

```json
{
  "type": "focusPrevious"
}
```

### Dismiss Keyboard

Hide the keyboard.

```json
{
  "type": "dismissKeyboard"
}
```

---

## Feedback & System Actions

### Show Alert

Present a native alert.

```json
{
  "type": "showAlert",
  "alertTitle": "Delete item?",
  "alertMessage": "This cannot be undone.",
  "alertActions": [
    { "title": "Cancel", "style": "cancel" },
    { "title": "Delete", "style": "destructive", "action": { "type": "executeFunction", "function": "deleteItem" } }
  ]
}
```

| Property | Type | Description |
|----------|------|-------------|
| `alertTitle` | string | Alert title |
| `alertMessage` | string | Alert body text |
| `alertActions` | AlertAction[] | Buttons (`title`, `style`, optional nested `action`) |

`style` is one of `default`, `cancel`, `destructive`.

### Haptic

Trigger haptic feedback.

```json
{
  "type": "haptic",
  "hapticStyle": "success"
}
```

| Property | Type | Description |
|----------|------|-------------|
| `hapticStyle` | string | `light`, `medium`, `heavy`, `success`, `warning`, `error`, `selection` |

### Open URL

Open a URL. `url` supports expressions.

```json
{
  "type": "openURL",
  "url": "https://example.com/{{slug}}",
  "urlPresentation": "sheet"
}
```

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `url` | string/expression | | URL to open |
| `urlPresentation` | string | `external` | `external` (system handler), `sheet`, or `fullScreen` (in-app Safari) |

---

## Function Actions

### Execute Backend Function

Invoke a named function by reference.

```json
{
  "type": "executeFunction",
  "function": "submitForm",
  "params": {
    "email": "{{email}}",
    "password": "{{password}}"
  }
}
```

| Property | Type | Description |
|----------|------|-------------|
| `function` | string | Function name |
| `params` | object | Parameters to pass |

> **Engine support**: `executeFunction` is a **no-op in the core engine** — it is reserved for higher-level delivery SDKs (e.g. the cloud SDK) that wire function names to real handlers. If you only use App8Engine directly, this action does nothing. **To trigger host-side logic, use [`emit`](events.md)** — it dispatches a typed event to the host event bus, which is the supported integration point. See [host-integration.md](host-integration.md).

---

## Event Triggers

Screen lifecycle and timer events.

### Event Structure

```json
{
  "onEvent": [
    {
      "event": "eventType",
      "action": { }
    }
  ]
}
```

### Event Types

| Event | When |
|-------|------|
| `appear` | Screen appeared |
| `disappear` | Screen will disappear |
| `timer` | Timer fired |

### On Appear

```json
{
  "onEvent": [
    {
      "event": "appear",
      "action": { "type": "executeFunction", "function": "loadData" }
    }
  ]
}
```

### On Disappear

```json
{
  "onEvent": [
    {
      "event": "disappear",
      "action": { "type": "executeFunction", "function": "cleanup" }
    }
  ]
}
```

### Timer Event

```json
{
  "onEvent": [
    {
      "event": "timer",
      "delay": 2.0,
      "interval": 5.0,
      "repeats": true,
      "action": { "type": "executeFunction", "function": "refresh" }
    }
  ]
}
```

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `delay` | number | 0 | Initial delay in seconds |
| `interval` | number | | Repeat interval (if repeats) |
| `repeats` | boolean | false | Whether to repeat |

---

## Action Arrays

Execute multiple actions in sequence.

```json
{
  "actions": {
    "tap": [
      { "type": "updateVariable", "variableName": "isLoading", "value": true },
      { "type": "executeFunction", "function": "submit" },
      { "type": "dismissKeyboard" }
    ]
  }
}
```

---

## Complete Examples

### Login Form Submit

<!-- @dsl-type: Component -->
```json
{
  "type": "button",
  "content": {
    "properties": {
      "text": "Sign In",
      "isEnabled": "{{email.length > 0 && password.length > 0}}"
    },
    "actions": {
      "tap": [
        { "type": "dismissKeyboard" },
        { "type": "updateVariable", "variableName": "isLoading", "value": true },
        {
          "type": "executeFunction",
          "function": "signIn",
          "params": {
            "email": "{{email}}",
            "password": "{{password}}"
          }
        }
      ]
    }
  }
}
```

### Like Button Toggle

<!-- @dsl-type: Component -->
```json
{
  "type": "button",
  "content": {
    "properties": {
      "icon": "{{likedIds.includes(item.id) ? 'heart.fill' : 'heart'}}"
    },
    "actions": {
      "tap": {
        "type": "toggleArrayValue",
        "variableName": "likedIds",
        "value": "{{item.id}}"
      }
    }
  }
}
```

### Form Field Navigation

Use `returnKeyType` to configure the keyboard return key. Focus flows to the next field automatically based on field order, or use explicit focus actions on buttons:

```json
{
  "children": [
    {
      "type": "textField",
      "id": "emailField",
      "content": {
        "properties": {
          "returnKeyType": "next",
          "bindVariable": "email"
        }
      }
    },
    {
      "type": "textField",
      "id": "passwordField",
      "content": {
        "properties": {
          "returnKeyType": "done",
          "bindVariable": "password",
          "isSecure": true
        }
      }
    },
    {
      "type": "button",
      "content": {
        "properties": { "text": "Submit" },
        "actions": {
          "tap": [
            { "type": "dismissKeyboard" },
            { "type": "executeFunction", "function": "submit" }
          ]
        }
      }
    }
  ]
}
```

Focus can also be controlled explicitly:

```json
{
  "type": "button",
  "content": {
    "properties": { "text": "Focus Password" },
    "actions": {
      "tap": { "type": "focus", "target": "passwordField" }
    }
  }
}
```

### Modal Dismiss with Confirmation

```json
{
  "type": "button",
  "content": {
    "properties": { "text": "Cancel" },
    "actions": {
      "tap": [
        { "type": "resetVariables", "scope": "screen" },
        { "type": "dismiss" }
      ]
    }
  }
}
```

### Tab Navigation with State

```json
{
  "type": "button",
  "content": {
    "properties": { "text": "Go to Profile" },
    "actions": {
      "tap": [
        { "type": "selectTab", "tabId": "profile" },
        { "type": "updateVariable", "variableName": "profileTab.shouldRefresh", "value": true }
      ]
    }
  }
}
```

### Screen Load with Timer

```json
{
  "type": "screen",
  "content": {
    "onEvent": [
      {
        "event": "appear",
        "action": { "type": "executeFunction", "function": "loadInitialData" }
      },
      {
        "event": "timer",
        "delay": 0,
        "interval": 30,
        "repeats": true,
        "action": { "type": "executeFunction", "function": "refreshData" }
      }
    ]
  }
}
```
