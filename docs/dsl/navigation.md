# Navigation

Navigation controls flow between screens using flows, push/pop, modals, and tabs.

## App Structure

```json
{
  "app": {
    "name": "MyApp",
    "variables": { }
  },
  "navigation": {
    "startFlow": "onboarding",
    "flows": [
      { "id": "onboarding", "startScreen": "welcome" },
      { "id": "main", "startScreen": "home" }
    ]
  },
  "screens": {
    "welcome": { },
    "home": { }
  },
  "templates": [ ]
}
```

| Key | Description |
|-----|-------------|
| `app` | App metadata and global variables |
| `navigation` | Flow definitions |
| `screens` | Screen definitions by ID |
| `templates` | Reusable component templates |

---

## Flows

Flows are navigation containers with independent stacks.

### Flow Definition

```json
{
  "navigation": {
    "startFlow": "onboarding",
    "flows": [
      { "id": "onboarding", "startScreen": "welcome" },
      { "id": "main", "startScreen": "home" }
    ]
  }
}
```

| Property | Type | Description |
|----------|------|-------------|
| `startFlow` | string | Initial flow on app launch |
| `flows` | Flow[] | Array of flow definitions |

### Flow Object

| Property | Type | Description |
|----------|------|-------------|
| `id` | string | Unique flow identifier |
| `startScreen` | string | Initial screen for this flow |

### Switching Flows

Use `completeFlow` to finish current flow and switch:

```json
{
  "type": "completeFlow",
  "destination": "main"
}
```

### Common Flow Patterns

**Onboarding → Main:**
```json
{
  "flows": [
    { "id": "onboarding", "startScreen": "welcome" },
    { "id": "main", "startScreen": "tabBar" }
  ]
}
```

**Auth → App:**
```json
{
  "flows": [
    { "id": "auth", "startScreen": "login" },
    { "id": "app", "startScreen": "dashboard" }
  ]
}
```

---

## Screen Navigation

### Push (Default)

Standard hierarchical navigation with back button.

```json
{
  "type": "navigation",
  "nextScreen": "details"
}
```

### With Parameters

```json
{
  "type": "navigation",
  "nextScreen": "userProfile",
  "params": {
    "userId": "{{selectedUserId}}",
    "showEdit": true
  }
}
```

### Receiving Parameters

Define expected parameters in the screen:

```json
{
  "type": "screen",
  "content": {
    "inputParameters": {
      "userId": { "type": "string", "required": true },
      "showEdit": { "type": "boolean", "required": false }
    }
  }
}
```

Parameters are available as variables:

```json
"text": "{{userId}}"
"hidden": "{{!showEdit}}"
```

---

## Custom Transitions

The presentation styles below cover the built-in system animations. To customize
*how* a screen animates in and out — slide/fade/zoom/cover presets, fully custom
opacity/translate/scale/rotate keyframes, reusable named transitions,
gesture-driven interactive dismiss, **sized modal popups & sheets** (a `presentation`
block sizing the container relatively or absolutely), and **shared-element**
(hero / composite) morphs that grow a matched component into its counterpart on the
next screen — add a `transition` to the navigation action:

```json
{ "type": "navigation", "nextScreen": "detail", "transition": "slide" }
```

See [transitions.md](transitions.md) for the full transition system, including the
`popup` / `sheet` presets for sized modals and the `shared` preset for
shared-element transitions.

## Presentation Styles

### Push (Hierarchical)

Standard navigation push with back button.

```json
{
  "type": "navigation",
  "nextScreen": "details",
  "presentation": "push"
}
```

### Sheet

iOS-style bottom sheet (native `UISheetPresentationController`), with a grabber and
swipe-to-dismiss.

```json
{
  "type": "navigation",
  "nextScreen": "filter",
  "presentation": "sheet",
  "detents": ["medium", "large"]
}
```

**Detents** are the heights the sheet can rest at; supply several to let the user
drag between them. Each entry is one of:

| Form | Meaning |
|------|---------|
| `"medium"` | System half-height detent. |
| `"large"` | System full-height detent. |
| a number, e.g. `320` | Custom detent at a fixed height in points. |
| `"NN%"`, e.g. `"60%"` | Custom detent at a fraction of the largest available height. |

```json
{ "type": "navigation", "nextScreen": "peer", "presentation": "pageSheet",
  "detents": ["60%", "large"], "grabber": false }
```

Omitting `detents` defaults to a single `large` detent. Scrolling the content past
its top grows the sheet to the next detent. Set **`grabber: false`** to hide the
drag indicator (it's shown by default). For a fully custom-styled bottom card (your
own size, corner radius, shadow, and dismiss animation) use the engine-driven
[`sheet` transition preset](transitions.md#sized-modal-presentation-popups--sheets)
instead.

### Full Screen Modal

```json
{
  "type": "navigation",
  "nextScreen": "fullScreenImage",
  "presentation": "fullScreen"
}
```

No swipe to dismiss. Must explicitly dismiss.

### Form Sheet

```json
{
  "type": "navigation",
  "nextScreen": "editItem",
  "presentation": "formSheet"
}
```

Smaller modal, optimized for iPad. Centered with backdrop.

### Page Sheet

```json
{
  "type": "navigation",
  "nextScreen": "settings",
  "presentation": "pageSheet",
  "detents": ["medium", "large"]
}
```

Same native sheet as [Sheet](#sheet) and accepts the same `detents`
(`medium` / `large` / a fixed number / `"NN%"`).

### Cross Dissolve

Full screen modal that fades in instead of sliding up. Good for splash-style transitions and image lightboxes.

```json
{
  "type": "navigation",
  "nextScreen": "photoViewer",
  "presentation": "crossDissolve"
}
```

---

## Navigation Bar

Configure the navigation bar for each screen.

### Structure

```json
{
  "type": "screen",
  "content": {
    "navigationBar": {
      "title": "Profile",
      "titleView": { },
      "titleAlignment": "left",
      "backLabel": "Back",
      "hidden": false,
      "leftAction": { },
      "rightAction": { },
      "rightActions": [ ]
    }
  }
}
```

| Property | Type | Description |
|----------|------|-------------|
| `title` | string | Navigation bar title (ignored when `titleView` is set) |
| `titleView` | Component | Custom DSL component rendered as the nav bar title |
| `titleAlignment` | string | `"left"` places `titleView` as left bar item; `"center"` (default) uses standard title area |
| `backLabel` | string | Custom back button label (ignored when `titleView` is set) |
| `hidden` | boolean | Hide navigation bar |
| `leftAction` | BarAction | Left bar button (ignored when `titleAlignment: "left"`) |
| `rightAction` | BarAction | Single right bar button (kept for backward compatibility) |
| `rightActions` | BarAction[] | Multiple right bar buttons — takes priority over `rightAction` |

### Bar Action

```json
{
  "label": "Save",
  "icon": "checkmark",
  "style": "bold",
  "action": { "type": "executeFunction", "function": "save" }
}
```

| Property | Type | Description |
|----------|------|-------------|
| `label` | string | Button text |
| `icon` | string | SF Symbol name (alternative to label) |
| `style` | string | `"bold"`, `"destructive"` |
| `action` | Action | Action to execute |

### Examples

**Title Only:**
```json
{
  "navigationBar": {
    "title": "Settings"
  }
}
```

**Hidden:**
```json
{
  "navigationBar": {
    "hidden": true
  }
}
```

**With Actions:**
```json
{
  "navigationBar": {
    "title": "Edit Profile",
    "leftAction": {
      "label": "Cancel",
      "action": { "type": "dismiss" }
    },
    "rightAction": {
      "label": "Save",
      "style": "bold",
      "action": { "type": "executeFunction", "function": "saveProfile" }
    }
  }
}
```

**Custom Back:**
```json
{
  "navigationBar": {
    "title": "Details",
    "backLabel": "List"
  }
}
```

**With Icon:**
```json
{
  "navigationBar": {
    "title": "Settings",
    "rightAction": {
      "icon": "gear",
      "action": { "type": "navigation", "nextScreen": "preferences" }
    }
  }
}
```

**Multiple Right Buttons:**
```json
{
  "navigationBar": {
    "title": "Select Items",
    "leftAction": {
      "label": "Cancel",
      "action": { "type": "dismiss" }
    },
    "rightActions": [
      {
        "icon": "square.and.pencil",
        "action": { "type": "executeFunction", "function": "edit" }
      },
      {
        "icon": "trash",
        "style": "destructive",
        "action": { "type": "executeFunction", "function": "delete" }
      }
    ]
  }
}
```

Note: `rightActions` renders right-to-left — the first item in the array appears rightmost.

**Left-Aligned Title View (avatar + title):**
```json
{
  "navigationBar": {
    "titleView": {
      "id": "navTitleStack",
      "type": "stackView",
      "content": {
        "properties": { "axis": "horizontal", "spacing": 10, "alignment": "center" },
        "children": [
          {
            "id": "navAvatar",
            "type": "image",
            "content": {
              "properties": { "url": "{{user.avatarUrl}}", "contentMode": "scaleAspectFill" },
              "layout": { "width": 36, "height": 36 },
              "style": { "material": [{ "corner": { "radius": 18, "curve": "circular" } }] }
            }
          },
          {
            "id": "navTitleLabel",
            "type": "label",
            "content": {
              "properties": { "text": "{{user.name}}" },
              "style": { "text": { "fontSize": 20, "fontWeight": "bold", "color": "#FFFFFF" } }
            }
          }
        ]
      }
    },
    "titleAlignment": "left",
    "rightActions": [
      { "icon": "magnifyingglass", "action": { "type": "navigation", "nextScreen": "search" } },
      { "icon": "plus", "action": { "type": "navigation", "nextScreen": "newChat" } }
    ]
  }
}
```

---

## Tab Bar

Tab-based navigation using TabBarScreen.

### Structure

```json
{
  "type": "tabBarScreen",
  "content": {
    "tabs": [
      { "id": "home", "label": "Home", "icon": "house.fill", "screen": "homeScreen" },
      { "id": "search", "label": "Search", "icon": "magnifyingglass", "screen": "searchScreen" },
      { "id": "profile", "label": "Profile", "icon": "person.fill", "screen": "profileScreen" }
    ],
    "initialTab": "home",
    "tintColor": "#007AFF",
    "unselectedColor": "#8E8E93"
  }
}
```

### Tab Properties

| Property | Type | Description |
|----------|------|-------------|
| `id` | string | Unique tab identifier |
| `label` | string | Tab label text |
| `icon` | string | SF Symbol name |
| `screen` | string | Screen ID to display |

### TabBarScreen Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `tabs` | Tab[] | | Tab definitions |
| `initialTab` | string | First tab | Initial tab ID |
| `tintColor` | Color | System blue | Selected tab color |
| `unselectedColor` | Color | Gray | Unselected tab color |

### Programmatic Tab Selection

```json
{
  "type": "selectTab",
  "tabId": "profile"
}
```

Or by index:

```json
{
  "type": "selectTab",
  "tabIndex": 2
}
```

---

## Dismissing Modals

Close modal screens (sheet, fullScreen, formSheet, pageSheet).

```json
{
  "type": "dismiss"
}
```

---

## Going Back

Pop the current screen (back one) with `isBack`, or pop all the way to the
navigation-stack root ("back to list") by adding `toRoot`:

```json
{ "type": "navigation", "isBack": true }
```

```json
{ "type": "navigation", "isBack": true, "toRoot": true }
```

---

## Disabling swipe-back

By default a pushed screen can be popped with the iOS interactive **swipe-back**
edge gesture. Set `swipeBackEnabled: false` on the screen's `content` to turn that
gesture off while the screen is on top — useful for forward-only flows
(onboarding, a wizard, a checkout step) where an accidental back-swipe would lose
state or skip a required action.

```json
{
  "type": "screen",
  "id": "onboarding-goals",
  "content": {
    "navigationBar": { "hidden": true },
    "swipeBackEnabled": false,
    "children": [ ]
  }
}
```

The flag is per-screen and applies whenever that screen is the visible (top)
one. It disables **both** the system swipe-back and any custom interactive-pop
edge-pan (see [transitions.md](transitions.md#interactive-dismiss--pop)), so the
screen can only be left programmatically (a button running
`{ "type": "navigation", "isBack": true }`, `completeFlow`, etc.). It does not
affect the push/pop **animation** — pair it with any `transition`. A back button
in the `navigationBar` still works; only the gesture is suppressed.

---

## Complete Example

### App with Onboarding and Tabs

```json
{
  "app": {
    "name": "MyApp",
    "variables": {
      "isOnboarded": { "type": "boolean", "initialValue": false }
    }
  },
  "navigation": {
    "startFlow": "onboarding",
    "flows": [
      { "id": "onboarding", "startScreen": "welcome" },
      { "id": "main", "startScreen": "tabBar" }
    ]
  },
  "screens": {
    "welcome": {
      "type": "screen",
      "content": {
        "navigationBar": { "hidden": true },
        "children": [
          {
            "type": "label",
            "content": {
              "properties": { "text": "Welcome!" },
              "layout": { "centerX": 0, "top": 200 }
            }
          },
          {
            "type": "button",
            "content": {
              "properties": { "text": "Get Started" },
              "layout": { "centerX": 0, "top": 300, "width": 200, "height": 50 },
              "actions": {
                "tap": {
                  "type": "completeFlow",
                  "destination": "main"
                }
              }
            }
          }
        ]
      }
    },
    "tabBar": {
      "type": "tabBarScreen",
      "content": {
        "tabs": [
          { "id": "home", "label": "Home", "icon": "house.fill", "screen": "home" },
          { "id": "profile", "label": "Profile", "icon": "person.fill", "screen": "profile" }
        ],
        "initialTab": "home",
        "tintColor": "#007AFF"
      }
    },
    "home": {
      "type": "screen",
      "content": {
        "navigationBar": { "title": "Home" },
        "children": [
          {
            "type": "button",
            "content": {
              "properties": { "text": "View Details" },
              "layout": { "centerX": 0, "top": 100 },
              "actions": {
                "tap": {
                  "type": "navigation",
                  "nextScreen": "details",
                  "params": { "itemId": "123" }
                }
              }
            }
          }
        ]
      }
    },
    "details": {
      "type": "screen",
      "content": {
        "inputParameters": {
          "itemId": { "type": "string", "required": true }
        },
        "navigationBar": {
          "title": "Details",
          "rightAction": {
            "label": "Edit",
            "action": {
              "type": "navigation",
              "nextScreen": "edit",
              "presentation": "sheet"
            }
          }
        },
        "children": [
          {
            "type": "label",
            "content": {
              "properties": { "text": "Item: {{itemId}}" },
              "layout": { "leading": 20, "top": 20 }
            }
          }
        ]
      }
    },
    "edit": {
      "type": "screen",
      "content": {
        "navigationBar": {
          "title": "Edit",
          "leftAction": {
            "label": "Cancel",
            "action": { "type": "dismiss" }
          },
          "rightAction": {
            "label": "Save",
            "style": "bold",
            "action": [
              { "type": "executeFunction", "function": "save" },
              { "type": "dismiss" }
            ]
          }
        }
      }
    },
    "profile": {
      "type": "screen",
      "content": {
        "navigationBar": { "title": "Profile" },
        "children": [ ]
      }
    }
  }
}
```
