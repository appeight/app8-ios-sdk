# Screen

Top-level container for a screen.

## Content Properties

| Property | Type | Description |
|----------|------|-------------|
| `children` | Component[] | Child components |
| `variables` | object | Screen-scoped variables |
| `inputParameters` | object | Parameters passed from navigation |
| `navigationBar` | NavigationBar | Navigation bar configuration — see [Navigation Bar](#navigation-bar) below |
| `onEvent` | EventTrigger[] | Screen lifecycle events — see [Event Triggers](#event-triggers) below |
| `style` | ScreenStyle | Screen styling |
| `additionalSafeAreaInsets` | EdgeInsets | Extra safe area insets applied to the screen — see [layout.md](../layout.md#additional-safe-area-insets-screen-level) |
| `hidesTabBar` | boolean | Hide the tab bar when this screen is pushed |
| `dismissKeyboardOnTap` | boolean | Dismiss keyboard when tapping outside inputs (default `true`) |

## Navigation Bar

See [navigation.md — Navigation Bar](../navigation.md#navigation-bar) for full property reference.

| Property | Type | Description |
|----------|------|-------------|
| `title` | string | Navigation bar title text |
| `backLabel` | string | Custom back button label |
| `hidden` | boolean | Hide the navigation bar |
| `leftAction` | BarAction | Leading bar button item |
| `rightAction` | BarAction | Trailing bar button item |

**BarAction structure:**
```json
{
  "label": "Edit",
  "icon": "pencil",
  "action": { "type": "navigation", "nextScreen": "editProfile" }
}
```

## Event Triggers

See [actions.md — Event Triggers](../actions.md#event-triggers) for full reference.

| Event | Description |
|-------|-------------|
| `appear` | Screen has appeared (viewDidAppear) |
| `disappear` | Screen has disappeared (viewDidDisappear) |
| `timer` | Fires once after a `delay` (seconds) |

```json
"onEvent": [
  { "event": "appear", "action": { "type": "executeFunction", "function": "loadData" } },
  { "event": "timer", "delay": 1.5, "action": { "type": "updateVariable", "variableName": "isReady", "value": true } }
]
```

## Example

```json
{
  "type": "screen",
  "content": {
    "navigationBar": {
      "title": "Profile",
      "rightAction": {
        "label": "Edit",
        "action": { "type": "navigation", "nextScreen": "editProfile" }
      }
    },
    "variables": {
      "userName": { "type": "string", "initialValue": "" }
    },
    "inputParameters": {
      "userId": { "type": "string", "required": true }
    },
    "onEvent": [
      { "event": "appear", "action": { "type": "executeFunction", "function": "loadUser" } }
    ],
    "children": [ ]
  }
}
```
