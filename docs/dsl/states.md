# States & Animations

Components can have multiple visual states with animated transitions.

## State Structure

```json
{
  "content": {
    "defaultStateName": "normal",
    "states": {
      "normal": { },
      "pressed": { },
      "disabled": { }
    },
    "triggers": {
      "touchDown": "pressed",
      "touchUp": "normal"
    }
  }
}
```

---

## Default State

The initial state for a component.

### Static Default

```json
"defaultStateName": "normal"
```

### Dynamic Default (Expression)

```json
"defaultStateName": "{{isSelected ? 'selected' : 'normal'}}"
```

---

## Triggers

User interactions that trigger state changes.

### Trigger Types

| Trigger | When Fired |
|---------|------------|
| `touchDown` | Finger touches component |
| `touchUp` | Finger releases |
| `focus` | TextField gains focus |
| `blur` | TextField loses focus |
| `hover` | Pointer hovers (iPad) |
| `hoverEnd` | Pointer leaves |

### Example

```json
{
  "triggers": {
    "touchDown": "pressed",
    "touchUp": "normal"
  }
}
```

### TextField Focus Example

```json
{
  "triggers": {
    "focus": "focused",
    "blur": "normal"
  }
}
```

---

## State Definition

States can override properties, styles, and layouts.

### Properties Override

```json
{
  "states": {
    "disabled": {
      "properties": {
        "text": "Unavailable",
        "icon": "xmark.circle"
      }
    }
  }
}
```

### Style Override

```json
{
  "states": {
    "pressed": {
      "style": {
        "alpha": 0.7,
        "transform": { "scale": 0.95 }
      }
    }
  }
}
```

### Layout Override

```json
{
  "states": {
    "expanded": {
      "layout": {
        "height": 200
      }
    },
    "collapsed": {
      "layout": {
        "height": 50
      }
    }
  }
}
```

### Combined Override

```json
{
  "states": {
    "active": {
      "properties": {
        "icon": "checkmark.circle.fill"
      },
      "style": {
        "tintColor": "#34C759",
        "transform": { "scale": 1.1 }
      }
    }
  }
}
```

---

## Animations

Each state declares an `animation` describing how the component transitions **into** that state. The same descriptor type is used everywhere across the engine — see [animations.md](animations.md) for the full schema (timing options, structured springs, cubic-bezier, the named-animation registry, and per-property animations for variable changes).

```jsonc
{
  "animation": {
    "duration": 0.15,
    "curve": "easeOut"
  }
}
```

```jsonc
// Bouncy settle with explicit damping/velocity
{
  "animation": {
    "duration": 0.4,
    "spring": { "damping": 0.8, "velocity": 0.9 }
  }
}
```

```jsonc
// Reference a named animation from app.animations
{ "animation": { "id": "fastPress" } }
```

### What animates during a state transition

A single state animation drives all of the following under one synchronized transition:

- `alpha`, `transform`
- Gradient fill (CAGradientLayer colors and locations)
- `shadowColor`, `shadowRadius`, `shadowOffset`, `shadowOpacity`
- Outline `strokeColor` (the layer is rebuilt if `lineWidth` or `position` changes)
- `cornerRadius`

When a state has no `animation`, the transition is instantaneous. System-level Reduce Motion collapses every transition to instantaneous regardless of the descriptor.

### Example

```json
{
  "triggers": { "touchDown": "pressed", "touchUp": "normal" },
  "defaultStateName": "normal",
  "states": {
    "pressed": {
      "style": { "alpha": 0.85, "transform": { "scale": 0.97 } },
      "animation": { "duration": 0.15, "curve": "easeOut" }
    },
    "normal": {
      "style": { "alpha": 1.0, "transform": { "scale": 1.0 } },
      "animation": {
        "duration": 0.4,
        "spring": { "damping": 0.8, "velocity": 0.9 }
      }
    }
  }
}
```

---

## Child State Propagation

Parent components can set children's states.

```json
{
  "states": {
    "inactive": {
      "childStates": {
        "icon": "dimmed",
        "label": "dimmed"
      }
    },
    "active": {
      "childStates": {
        "icon": "highlighted",
        "label": "highlighted"
      }
    }
  }
}
```

Children must have matching state names:

<!-- @dsl-skip: state propagation example -->
```json
{
  "type": "icon",
  "id": "icon",
  "content": {
    "states": {
      "dimmed": {
        "style": { "alpha": 0.5 }
      },
      "highlighted": {
        "style": { "alpha": 1.0 }
      }
    }
  }
}
```

---

## Programmatic State Change

Change state via actions.

```json
{
  "type": "setState",
  "stateName": "active",
  "animated": true
}
```

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `stateName` | string | | Target state |
| `animated` | boolean | true | Animate transition |

---

## Complete Examples

### Button Press Effect

<!-- @dsl-type: Component -->
```json
{
  "type": "button",
  "content": {
    "properties": { "text": "Press Me" },
    "defaultStateName": "normal",
    "triggers": {
      "touchDown": "pressed",
      "touchUp": "normal"
    },
    "states": {
      "normal": {
        "style": {
          "alpha": 1.0,
          "transform": { "scale": 1.0 }
        },
        "animation": {
          "duration": 0.3,
          "curve": "spring"
        }
      },
      "pressed": {
        "style": {
          "alpha": 0.8,
          "transform": { "scale": 0.95 }
        },
        "animation": {
          "duration": 0.1,
          "curve": "easeOut"
        }
      }
    }
  }
}
```

### Toggle Button

<!-- @dsl-skip: button with icon only -->
```json
{
  "type": "button",
  "id": "likeButton",
  "content": {
    "properties": { "icon": "heart" },
    "defaultStateName": "{{isLiked ? 'active' : 'normal'}}",
    "states": {
      "normal": {
        "properties": { "icon": "heart" },
        "style": { "tintColor": "#999999" }
      },
      "active": {
        "properties": { "icon": "heart.fill" },
        "style": { "tintColor": "#FF3B30" },
        "animation": {
          "duration": 0.2,
          "curve": "spring"
        }
      }
    },
    "actions": {
      "tap": {
        "type": "updateVariable",
        "variableName": "isLiked",
        "value": "{{!isLiked}}"
      }
    }
  }
}
```

### Text Field Focus

<!-- @dsl-skip: textField with focus states -->
```json
{
  "type": "textField",
  "id": "emailField",
  "content": {
    "properties": {
      "placeholder": "Email",
      "bindVariable": "email"
    },
    "defaultStateName": "normal",
    "triggers": {
      "focus": "focused",
      "blur": "normal"
    },
    "states": {
      "normal": {
        "style": {
          "material": [
            { "fill": { "solid": "#F5F5F5" } },
            { "corner": { "radius": 8 } },
            { "outline": { "lineWidth": 0 } }
          ]
        },
        "animation": {
          "duration": 0.2,
          "curve": "easeOut"
        }
      },
      "focused": {
        "style": {
          "material": [
            { "fill": { "solid": "#FFFFFF" } },
            { "corner": { "radius": 8 } },
            { "outline": { "lineWidth": 2, "fill": { "solid": "#007AFF" } } }
          ]
        },
        "animation": {
          "duration": 0.2,
          "curve": "easeOut"
        }
      },
      "error": {
        "style": {
          "material": [
            { "fill": { "solid": "#FFF5F5" } },
            { "corner": { "radius": 8 } },
            { "outline": { "lineWidth": 2, "fill": { "solid": "#FF3B30" } } }
          ]
        }
      }
    }
  }
}
```

### Card with Hover (iPad)

<!-- @dsl-type: Component -->
```json
{
  "type": "view",
  "content": {
    "defaultStateName": "normal",
    "triggers": {
      "hover": "hovered",
      "hoverEnd": "normal",
      "touchDown": "pressed",
      "touchUp": "normal"
    },
    "states": {
      "normal": {
        "style": {
          "transform": { "scale": 1.0, "translateY": 0 },
          "material": [
            { "shadow": [{ "color": "#00000010", "radius": 4, "offset": { "y": 2 } }] }
          ]
        },
        "animation": {
          "duration": 0.3,
          "curve": "spring"
        }
      },
      "hovered": {
        "style": {
          "transform": { "scale": 1.02, "translateY": -2 },
          "material": [
            { "shadow": [{ "color": "#00000020", "radius": 8, "offset": { "y": 4 } }] }
          ]
        },
        "animation": {
          "duration": 0.2,
          "curve": "easeOut"
        }
      },
      "pressed": {
        "style": {
          "transform": { "scale": 0.98, "translateY": 0 },
          "material": [
            { "shadow": [{ "color": "#00000008", "radius": 2, "offset": { "y": 1 } }] }
          ]
        },
        "animation": {
          "duration": 0.1,
          "curve": "easeOut"
        }
      }
    }
  }
}
```

### Expandable Section

<!-- @dsl-type: Component -->
```json
{
  "type": "view",
  "content": {
    "variables": {
      "isExpanded": { "type": "boolean", "initialValue": false }
    },
    "children": [
      {
        "type": "button",
        "content": {
          "properties": { "text": "Toggle" },
          "actions": {
            "tap": {
              "type": "updateVariable",
              "variableName": "isExpanded",
              "value": "{{!isExpanded}}"
            }
          }
        }
      },
      {
        "type": "view",
        "id": "content",
        "content": {
          "defaultStateName": "{{isExpanded ? 'expanded' : 'collapsed'}}",
          "states": {
            "collapsed": {
              "style": { "alpha": 0 },
              "layout": { "height": 0 },
              "animation": {
                "duration": 0.3,
                "curve": "easeInOut"
              }
            },
            "expanded": {
              "style": { "alpha": 1 },
              "layout": { "height": 100 },
              "animation": {
                "duration": 0.3,
                "curve": "easeInOut"
              }
            }
          }
        }
      }
    ]
  }
}
```

### Disabled State

<!-- @dsl-type: Component -->
```json
{
  "type": "button",
  "content": {
    "properties": {
      "text": "Submit",
      "isEnabled": "{{isFormValid}}"
    },
    "defaultStateName": "{{isFormValid ? 'normal' : 'disabled'}}",
    "triggers": {
      "touchDown": "pressed",
      "touchUp": "{{isFormValid ? 'normal' : 'disabled'}}"
    },
    "states": {
      "normal": {
        "style": {
          "material": [{ "fill": { "solid": "#007AFF" } }],
          "text": { "color": "#FFFFFF" }
        }
      },
      "pressed": {
        "style": {
          "material": [{ "fill": { "solid": "#0056B3" } }],
          "transform": { "scale": 0.98 }
        }
      },
      "disabled": {
        "style": {
          "material": [{ "fill": { "solid": "#E5E5E5" } }],
          "text": { "color": "#999999" }
        }
      }
    }
  }
}
```
