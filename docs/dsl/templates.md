# Templates

Templates are reusable component definitions that can be referenced and customized.

Every style block below uses the **Style Entity** format (`id` + `type` + `content`) — see [styles.md](styles.md) for the rules.

## Template Definition

Define templates at the app level:

```json
{
  "templates": [
    {
      "id": "PrimaryButton",
      "type": "button",
      "content": {
        "style": {
          "material": {
            "id": "primaryBtnMaterial",
            "type": "material",
            "content": [
              { "id": "primaryBtnFill", "type": "fill", "content": { "solid": "#007AFF" } },
              { "id": "primaryBtnCorner", "type": "corner", "content": { "radius": 12, "curve": "continuous" } }
            ]
          },
          "text": {
            "id": "primaryBtnText",
            "type": "text",
            "content": { "fontSize": 17, "fontWeight": "semibold", "color": "#FFFFFF" }
          }
        },
        "layout": { "height": 50 }
      }
    }
  ]
}
```

---

## Template Usage

Reference a template by `templateId`:

<!-- @dsl-type: Component -->
```json
{
  "type": "button",
  "templateId": "PrimaryButton",
  "content": {
    "properties": { "text": "Sign Up" }
  }
}
```

The component inherits all template properties, with usage properties merged on top.

---

## Template Inheritance

Templates can extend other templates:

```json
{
  "templates": [
    {
      "id": "BaseButton",
      "type": "button",
      "content": {
        "style": {
          "material": {
            "id": "baseBtnMaterial",
            "type": "material",
            "content": [
              { "id": "baseBtnCorner", "type": "corner", "content": { "radius": 12, "curve": "continuous" } }
            ]
          },
          "text": {
            "id": "baseBtnText",
            "type": "text",
            "content": { "fontSize": 17, "fontWeight": "semibold" }
          }
        },
        "layout": { "height": 50 }
      }
    },
    {
      "id": "PrimaryButton",
      "templateId": "BaseButton",
      "content": {
        "style": {
          "material": {
            "id": "primaryBtnMaterial",
            "type": "material",
            "content": [
              { "id": "primaryBtnFill", "type": "fill", "content": { "solid": "#007AFF" } }
            ]
          },
          "text": {
            "id": "primaryBtnText",
            "type": "text",
            "content": { "color": "#FFFFFF" }
          }
        }
      }
    },
    {
      "id": "SecondaryButton",
      "templateId": "BaseButton",
      "content": {
        "style": {
          "material": {
            "id": "secondaryBtnMaterial",
            "type": "material",
            "content": [
              { "id": "secondaryBtnFill", "type": "fill", "content": { "solid": "#E5E5EA" } }
            ]
          },
          "text": {
            "id": "secondaryBtnText",
            "type": "text",
            "content": { "color": "#007AFF" }
          }
        }
      }
    }
  ]
}
```

---

## Property Merging

When using a template, properties merge as follows:

1. Template provides base properties
2. Usage overrides specific properties
3. Deep merge for nested objects

### Example

**Template:**
<!-- @dsl-skip: template definition -->
```json
{
  "id": "Card",
  "type": "view",
  "content": {
    "style": {
      "material": {
        "id": "cardMaterial",
        "type": "material",
        "content": [
          { "id": "cardFill", "type": "fill", "content": { "solid": "#FFFFFF" } },
          { "id": "cardCorner", "type": "corner", "content": { "radius": 12 } },
          { "id": "cardShadow", "type": "shadow", "content": [{ "color": "#00000020", "radius": 8, "offset": { "y": 4 } }] }
        ]
      }
    },
    "layout": { "leading": 16, "trailing": 16 }
  }
}
```

**Usage:**
```json
{
  "templateId": "Card",
  "content": {
    "layout": {
      "top": 8,
      "bottom": 8
    },
    "children": [
      {
        "type": "label",
        "content": {
          "properties": { "text": "Card Content" }
        }
      }
    ]
  }
}
```

**Result:** Card with template styles + merged layout (leading, trailing from template; top, bottom from usage) + children.

---

## Template Variables (Customization via Props)

Templates can expose customizable values through `content.variables`. Instances pass overrides via a top-level `variables` field — outside `content`, so the instance stays concise without knowing template internals.

### Defining a Parameterized Template

<!-- @dsl-skip: template definition -->
```json
{
  "id": "CounterCard",
  "type": "view",
  "content": {
    "variables": {
      "label": { "type": "string", "initialValue": "Counter" },
      "count": { "type": "number", "initialValue": 0 }
    },
    "style": {
      "material": {
        "id": "counterCardMaterial",
        "type": "material",
        "content": [
          { "id": "counterCardFill", "type": "fill", "content": { "solid": "#FFFFFF18" } },
          { "id": "counterCardCorner", "type": "corner", "content": { "radius": 20 } }
        ]
      }
    },
    "layout": { "height": 120 },
    "children": [
      {
        "type": "label",
        "content": { "properties": { "text": "{{label}}" } }
      },
      {
        "type": "label",
        "content": { "properties": { "text": "{{count}}" } }
      }
    ]
  }
}
```

### Using a Parameterized Template

Pass values via the top-level `variables` field. Shorthand (bare values) is supported:

```json
{
  "id": "card-a",
  "templateId": "CounterCard",
  "variables": {
    "label": "Score",
    "count": 42
  },
  "content": {
    "layout": {
      "constraints": [
        { "type": "top", "target": "superview", "constant": 100 },
        { "type": "leading", "target": "superview", "constant": 24 },
        { "type": "trailing", "target": "superview", "constant": -24 }
      ]
    }
  }
}
```

**Merge priority:** instance `variables` > template `content.variables` defaults. Unoverridden variables keep their template defaults.

### Reactive Variables — Binding to Parent Scope

Instance variables can be **computed expressions** that reactively track a parent-scope (screen-level) variable. When the screen variable changes, the template instance automatically updates.

```json
{
  "type": "screen",
  "content": {
    "variables": {
      "counter1": { "type": "number", "initialValue": 0 },
      "counter2": { "type": "number", "initialValue": 0 }
    },
    "children": [
      {
        "id": "card-a",
        "templateId": "CounterCard",
        "variables": {
          "label": "Player A",
          "count": { "type": "number", "computed": "{{counter1}}" }
        },
        "content": { "layout": { "constraints": [...] } }
      },
      {
        "id": "card-b",
        "templateId": "CounterCard",
        "variables": {
          "label": "Player B",
          "count": { "type": "number", "computed": "{{counter2}}" }
        },
        "content": { "layout": { "constraints": [...] } }
      }
    ]
  }
}
```

Both instances use the same template but track **independent** screen variables. Updating `counter1` only re-renders `card-a`; `card-b` is unaffected.

### Key Rules

- `variables` is always top-level on the instance (sibling of `content`, not inside it)
- Shorthand bare values (`"label": "Score"`) are auto-normalized to full `VariableDefinition` format
- Full form allows computed bindings: `"count": { "type": "number", "computed": "{{counter1}}" }`
- Template defaults in `content.variables` are used for any variable the instance doesn't override

---

## Collection Templates

Templates can be used in collections:

```json
{
  "type": "collection",
  "content": {
    "properties": { "data": "{{users}}" },
    "template": "UserCard"
  }
}
```

Where `UserCard` is defined:

<!-- @dsl-skip: template definition -->
```json
{
  "id": "UserCard",
  "type": "view",
  "content": {
    "style": {
      "material": {
        "id": "userCardMaterial",
        "type": "material",
        "content": [
          { "id": "userCardFill", "type": "fill", "content": { "solid": "#FFFFFF" } },
          { "id": "userCardCorner", "type": "corner", "content": { "radius": 8 } }
        ]
      }
    },
    "layout": { "height": 80 },
    "children": [
      {
        "type": "image",
        "content": {
          "properties": { "url": "{{item.avatarUrl}}" },
          "style": {
            "contentMode": "scaleAspectFill",
            "corner": { "id": "userAvatarCorner", "type": "corner", "content": { "radius": 20 } }
          },
          "layout": { "leading": 16, "centerY": 0, "width": 40, "height": 40 }
        }
      },
      {
        "type": "label",
        "content": {
          "properties": { "text": "{{item.name}}" },
          "style": {
            "text": { "id": "userNameText", "type": "text", "content": { "fontSize": 17, "fontWeight": "medium" } }
          },
          "layout": { "leading": 72, "top": 20 }
        }
      },
      {
        "type": "label",
        "content": {
          "properties": { "text": "{{item.email}}" },
          "style": {
            "text": { "id": "userEmailText", "type": "text", "content": { "fontSize": 14, "color": "#666666" } }
          },
          "layout": { "leading": 72, "top": 44 }
        }
      }
    ]
  }
}
```

---

## States in Templates

Templates can include state definitions:

<!-- @dsl-skip: template definition -->
```json
{
  "id": "InteractiveCard",
  "type": "view",
  "content": {
    "defaultStateName": "normal",
    "triggers": {
      "touchDown": "pressed",
      "touchUp": "normal"
    },
    "states": {
      "normal": {
        "style": { "transform": { "scale": 1.0 } },
        "animation": { "duration": 0.3, "curve": "spring" }
      },
      "pressed": {
        "style": { "transform": { "scale": 0.98 } },
        "animation": { "duration": 0.1, "curve": "easeOut" }
      }
    }
  }
}
```

Usage inherits states:

```json
{
  "templateId": "InteractiveCard",
  "content": {
    "children": [ ]
  }
}
```

---

## Common Template Patterns

### Button Variants

```json
{
  "templates": [
    {
      "id": "PrimaryButton",
      "type": "button",
      "content": {
        "style": {
          "material": {
            "id": "primaryBtnMaterial",
            "type": "material",
            "content": [
              { "id": "primaryBtnFill", "type": "fill", "content": { "solid": "#007AFF" } },
              { "id": "primaryBtnCorner", "type": "corner", "content": { "radius": 12 } }
            ]
          },
          "text": { "id": "primaryBtnText", "type": "text", "content": { "fontSize": 17, "fontWeight": "semibold", "color": "#FFFFFF" } }
        },
        "layout": { "height": 50 }
      }
    },
    {
      "id": "SecondaryButton",
      "type": "button",
      "content": {
        "style": {
          "material": {
            "id": "secondaryBtnMaterial",
            "type": "material",
            "content": [
              { "id": "secondaryBtnFill", "type": "fill", "content": { "solid": "#E5E5EA" } },
              { "id": "secondaryBtnCorner", "type": "corner", "content": { "radius": 12 } }
            ]
          },
          "text": { "id": "secondaryBtnText", "type": "text", "content": { "fontSize": 17, "fontWeight": "semibold", "color": "#007AFF" } }
        },
        "layout": { "height": 50 }
      }
    },
    {
      "id": "TextButton",
      "type": "button",
      "content": {
        "style": {
          "text": { "id": "textBtnText", "type": "text", "content": { "fontSize": 17, "fontWeight": "medium", "color": "#007AFF" } }
        }
      }
    }
  ]
}
```

### Card Variants

```json
{
  "templates": [
    {
      "id": "Card",
      "type": "view",
      "content": {
        "style": {
          "material": {
            "id": "cardMaterial",
            "type": "material",
            "content": [
              { "id": "cardFill", "type": "fill", "content": { "solid": "#FFFFFF" } },
              { "id": "cardCorner", "type": "corner", "content": { "radius": 12, "curve": "continuous" } }
            ]
          }
        }
      }
    },
    {
      "id": "ElevatedCard",
      "templateId": "Card",
      "content": {
        "style": {
          "material": {
            "id": "elevatedCardMaterial",
            "type": "material",
            "content": [
              { "id": "elevatedCardShadow", "type": "shadow", "content": [{ "color": "#00000015", "radius": 8, "offset": { "y": 2 } }] }
            ]
          }
        }
      }
    },
    {
      "id": "OutlinedCard",
      "templateId": "Card",
      "content": {
        "style": {
          "material": {
            "id": "outlinedCardMaterial",
            "type": "material",
            "content": [
              { "id": "outlinedCardOutline", "type": "outline", "content": { "lineWidth": 1, "fill": { "solid": "#E5E5E5" } } }
            ]
          }
        }
      }
    }
  ]
}
```

### Form Input

<!-- @dsl-skip: template definition -->
```json
{
  "id": "FormInput",
  "type": "textField",
  "content": {
    "style": {
      "material": {
        "id": "formInputMaterial",
        "type": "material",
        "content": [
          { "id": "formInputFill", "type": "fill", "content": { "solid": "#F5F5F5" } },
          { "id": "formInputCorner", "type": "corner", "content": { "radius": 8 } }
        ]
      },
      "text": { "id": "formInputText", "type": "text", "content": { "fontSize": 16, "color": "#333333" } },
      "placeholder": { "fontSize": 16, "color": "#999999" },
      "padding": { "left": 12, "right": 12 }
    },
    "layout": { "height": 50 },
    "defaultStateName": "normal",
    "triggers": {
      "focus": "focused",
      "blur": "normal"
    },
    "states": {
      "normal": {
        "style": {
          "material": {
            "id": "formInputNormalMaterial",
            "type": "material",
            "content": [
              { "id": "formInputNormalOutline", "type": "outline", "content": { "lineWidth": 0 } }
            ]
          }
        }
      },
      "focused": {
        "style": {
          "material": {
            "id": "formInputFocusedMaterial",
            "type": "material",
            "content": [
              { "id": "formInputFocusedOutline", "type": "outline", "content": { "lineWidth": 2, "fill": { "solid": "#007AFF" } } }
            ]
          }
        }
      }
    }
  }
}
```

### List Item

<!-- @dsl-skip: template definition -->
```json
{
  "id": "ListItem",
  "type": "view",
  "content": {
    "style": {
      "material": {
        "id": "listItemMaterial",
        "type": "material",
        "content": [
          { "id": "listItemFill", "type": "fill", "content": { "solid": "#FFFFFF" } }
        ]
      }
    },
    "layout": { "height": 60 },
    "defaultStateName": "normal",
    "triggers": {
      "touchDown": "pressed",
      "touchUp": "normal"
    },
    "states": {
      "normal": {
        "style": { "alpha": 1.0 }
      },
      "pressed": {
        "style": {
          "material": {
            "id": "listItemPressedMaterial",
            "type": "material",
            "content": [
              { "id": "listItemPressedFill", "type": "fill", "content": { "solid": "#E5E5E5" } }
            ]
          }
        }
      }
    },
    "children": [
      {
        "type": "icon",
        "content": {
          "properties": { "name": "chevron.right" },
          "style": { "tintColor": "#C7C7CC" },
          "layout": { "trailing": 16, "centerY": 0 }
        }
      }
    ]
  }
}
```

### Badge

<!-- @dsl-skip: template definition -->
```json
{
  "id": "Badge",
  "type": "view",
  "content": {
    "style": {
      "material": {
        "id": "badgeMaterial",
        "type": "material",
        "content": [
          { "id": "badgeFill", "type": "fill", "content": { "solid": "#FF3B30" } },
          { "id": "badgeCorner", "type": "corner", "content": { "radius": 10 } }
        ]
      }
    },
    "layout": { "width": 20, "height": 20 },
    "children": [
      {
        "type": "label",
        "content": {
          "style": {
            "text": { "id": "badgeText", "type": "text", "content": { "fontSize": 12, "fontWeight": "bold", "color": "#FFFFFF", "alignment": "center" } }
          },
          "layout": { "leading": 0, "trailing": 0, "centerY": 0 }
        }
      }
    ]
  }
}
```

---

## Best Practices

### 1. Consistent Naming

Use clear, descriptive names: `PrimaryButton`, `SecondaryButton`, `DangerButton`; `Card`, `ElevatedCard`, `OutlinedCard`.

### 2. Build from Base Templates

Create base templates and extend them:

```
BaseButton
├── PrimaryButton
├── SecondaryButton
└── DangerButton
```

### 3. Include Default States

Add common states (`touchDown` → `pressed`, `touchUp` → `normal`) to interactive templates.

### 4. Define Layout in Templates

Include consistent layout properties (`leading`, `trailing`, `height`) so instances stay concise.

### 5. Use Templates for Collection Items

Define collection item templates separately for reuse via `"template": "ProductCard"`.

---

## Template Resolution

Templates are resolved at decode time:

1. Find template by ID
2. Deep merge template content with usage content
3. Resolve nested template references
4. Apply result to component

Multiple inheritance levels are supported: `BaseButton → PrimaryButton → LargePrimaryButton`.
