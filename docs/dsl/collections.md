# Collections

Collections render dynamic lists, grids, and carousels from data.

> For layout choice, inset values, header patterns, and common mistakes, see [collections-best-practices.md](collections-best-practices.md).

## Basic Structure

```json
{
  "type": "collection",
  "content": {
    "properties": {
      "data": "{{items}}"
    },
    "layout": {
      "type": "vertical",
      "itemSpacing": 8
    },
    "template": { }
  }
}
```

---

## Data Sources

| Property | Type | Description |
|----------|------|-------------|
| `data` | expression | Dynamic data from a variable (e.g., `"{{users}}"`) |
| `sectionDefinitions` | array | Multiple independent data sources, one per section |

These two are **mutually exclusive**. Precedence: `sectionDefinitions` > `data`.

Use `data` when the array comes from a variable (use a variable with `initialValue` for static data). Use `sectionDefinitions` when each section has a completely independent data source (see [Multiple Independent Sections](#multiple-independent-sections)).

For grouping a **single** data source into sections, use `groupBy` instead (see [Sections](#sections)).

### Dynamic Data

```json
{
  "properties": {
    "data": "{{users}}"
  }
}
```

---

## Layout Types

### Vertical List

Standard scrolling list.

```json
{
  "layout": {
    "type": "vertical",
    "itemSpacing": 12,
    "separatorStyle": "inset"
  }
}
```

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `type` | string | | `"vertical"` |
| `itemSpacing` | number | `0` | Space between items |
| `separatorStyle` | string | `"none"` | `"none"`, `"full"`, `"inset"` |
| `estimatedItemHeight` | number | | Hint for self-sizing items; improves layout performance |
| `contentInsets` | object | | Padding around content: `top`, `left`, `bottom`, `right` |
| `showsScrollIndicator` | boolean | `true` | Show or hide the vertical scroll indicator |

### Horizontal Carousel

Horizontally scrolling list.

```json
{
  "layout": {
    "type": "horizontal",
    "itemSpacing": 16,
    "itemWidth": 280,
    "itemHeight": 200,
    "pagingStyle": "paging"
  }
}
```

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `type` | string | | `"horizontal"` |
| `itemSpacing` | number | `0` | Space between items |
| `itemWidth` | number | | Fixed item width |
| `itemHeight` | number | | Fixed item height |
| `rows` | number | `1` | Number of rows in a multi-row horizontal carousel |
| `pagingStyle` | string | `"continuous"` | `"continuous"` (free scroll), `"paging"` (page by item width), `"pagingCentered"` (page with centered item) |
| `currentPageVariable` | string | | Plain variable name to write the current page index to (e.g., `"currentPage"`) |
| `estimatedItemHeight` | number | | Hint for self-sizing items |
| `contentInsets` | object | | Padding around content: `top`, `left`, `bottom`, `right` |
| `showsScrollIndicator` | boolean | `false` | Show or hide the horizontal scroll indicator |

> **Legacy**: `snapToItem: true` and `pagingEnabled: true` are accepted but `pagingStyle` is preferred.

### Grid

```json
{
  "layout": {
    "type": "grid",
    "columns": 3,
    "itemSpacing": 8,
    "lineSpacing": 8,
    "aspectRatio": 1.0
  }
}
```

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `type` | string | | `"grid"` |
| `columns` | number | | Number of columns |
| `itemSpacing` | number | `0` | Horizontal space between items |
| `lineSpacing` | number | `0` | Vertical space between rows |
| `aspectRatio` | number | | Item aspect ratio (width ÷ height) |
| `itemHeight` | number | | Fixed item height (alternative to `aspectRatio`) |
| `estimatedItemHeight` | number | | Hint for self-sizing items |
| `contentInsets` | object | | Padding around content: `top`, `left`, `bottom`, `right` |
| `showsScrollIndicator` | boolean | `true` | Show or hide the scroll indicator |

---

## Mixed Layouts

Use `defaultSectionLayout` or `sectionLayouts` inside `properties` to give each section its own layout (orthogonal scrolling). This enables, for example, a vertical list where each section scrolls horizontally.

`defaultSectionLayout` sets the fallback layout applied to all sections. `sectionLayouts` overrides per section, keyed by the `groupBy` value or `SectionDefinition.key`.

```json
{
  "properties": {
    "data": "{{feed}}",
    "groupBy": "item.category",
    "defaultSectionLayout": {
      "type": "horizontal",
      "itemWidth": 160,
      "itemHeight": 200,
      "itemSpacing": 12,
      "contentInsets": { "left": 16, "right": 16 }
    },
    "sectionLayouts": {
      "featured": {
        "type": "horizontal",
        "itemWidth": 320,
        "itemHeight": 240,
        "pagingStyle": "paging"
      }
    }
  }
}
```

| Property | Type | Description |
|----------|------|-------------|
| `defaultSectionLayout` | Layout | Fallback layout applied to all sections (overridden per-section by `sectionLayouts`) |
| `sectionLayouts` | object | Per-section layout overrides keyed by `groupBy` value or `SectionDefinition.key` |

---

## Style

The `style` key controls the visual appearance of the collection container.

```json
{
  "style": {
    "backgroundColor": "#F2F2F7",
    "separatorColor": "#E5E5EA",
    "separatorInset": 16
  }
}
```

| Property | Type | Description |
|----------|------|-------------|
| `material` | array | Material/fill layers (same format as view `material`) |
| `alpha` | number | Opacity of the collection view |
| `backgroundColor` | string | Hex background color |
| `separatorColor` | string | Hex color for separators (used with `separatorStyle`) |
| `separatorInset` | number | Leading inset for `"inset"` separators |

---

## Templates

### Single Template

All items use the same inline template:

```json
{
  "template": {
    "type": "view",
    "content": {
      "style": {
        "material": [
          { "fill": { "solid": "#FFFFFF" } },
          { "corner": { "radius": 8 } }
        ]
      },
      "layout": { "height": 60 },
      "children": [
        {
          "type": "label",
          "content": {
            "properties": { "text": "{{item.name}}" },
            "layout": { "leading": 16, "centerY": 0 }
          }
        }
      ]
    }
  }
}
```

### Template Reference

Reference an app-level template by name via `properties.templateName`:

```json
{
  "properties": {
    "templateName": "UserCard"
  }
}
```

### Heterogeneous Templates

Use `templateKey` and `templates` to render different templates per item type. `templateKey` is an item property path; `templates` maps each value to an inline component or a named template string.

```json
{
  "properties": {
    "templateKey": "item.type"
  },
  "templates": {
    "post": {
      "type": "view",
      "content": { }
    },
    "ad": "AdBanner",
    "product": "ProductTile"
  }
}
```

> **Boolean keys**: When `templateKey` points to a boolean property, the value is coerced to the string `"true"` or `"false"`. Use those as your template keys:
> ```json
> { "templateKey": "item.isFeatured", "templates": { "true": { ... }, "false": { ... } } }
> ```

---

## Item Variables

Inside templates, these variables are automatically available:

| Variable | Description |
|----------|-------------|
| `{{item}}` | Current item data |
| `{{item.$index}}` | 0-based index of the item |
| `{{item.property}}` | Any property on the item |
| `{{$parent}}` | Parent scope (screen-level variables) |
| `{{$parent.$parent}}` | Grandparent scope |

### Accessing Screen Variables

```json
"text": "{{$parent.currency}}{{item.price}}"
"hidden": "{{!$parent.showPrices}}"
```

---

## Sections

Group items by a property and render section headers.

```json
{
  "properties": {
    "groupBy": "item.category",
    "stickyHeaders": true
  },
  "defaultSectionHeader": {
    "type": "label",
    "content": {
      "properties": { "text": "{{section.key}}" },
      "style": {
        "text": { "fontSize": 14, "fontWeight": "semibold", "color": "#666666" }
      },
      "layout": { "leading": 16, "height": 32 }
    }
  }
}
```

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `groupBy` | string | | Item property path to group by (e.g., `"item.category"`) |
| `stickyHeaders` | boolean | `false` | Pin section headers while scrolling |

**Header templates** (defined at the `content` level, not inside `properties`):

| Key | Description |
|-----|-------------|
| `defaultSectionHeader` | Single template applied as the default header for **all** sections |
| `sectionHeaders` | Map of templates keyed by section key — overrides `defaultSectionHeader` for specific sections |

If both are defined, `sectionHeaders[key]` takes precedence over `defaultSectionHeader` for any section whose key has a match.

### Section Variables

Inside `defaultSectionHeader` (or `sectionHeaders`) templates:

| Variable | Description |
|----------|-------------|
| `{{section.key}}` | The grouping value for this section |
| `{{section.items}}` | Items in this section |
| `{{section.$index}}` | 0-based section index |

---

## Multiple Independent Sections

Use `sectionDefinitions` when each section has its own completely independent data source (e.g., a profile header, a settings list, and a support list all from different variables).

**When to use `sectionDefinitions` vs `groupBy`:**
- `sectionDefinitions` — each section binds to a **different variable** (independent data sources)
- `groupBy` — all items come from a **single variable**, dynamically split into sections by a property value

```json
{
  "properties": {
    "sectionDefinitions": [
      { "key": "header",   "data": "{{profileData}}",   "templateName": "profileHeader" },
      { "key": "settings", "data": "{{settingsItems}}", "templateName": "settingsRow" },
      { "key": "support",  "data": "{{supportItems}}",  "templateName": "settingsRow" }
    ]
  }
}
```

Each entry in `sectionDefinitions`:

| Property | Type | Description |
|----------|------|-------------|
| `key` | string | Unique section key (used to match `sectionLayouts` and `sectionHeaders`) |
| `data` | expression | Variable expression for this section's data |
| `templateName` | string | Name of the registered template to use for items in this section |
| `templateKey` | string | Item property path for heterogeneous templates within this section |

---

## Empty / Loading / Error States

Provide component trees to display when the collection is empty, loading, or in an error state.

```json
{
  "emptyState": {
    "type": "view",
    "content": {
      "children": [
        {
          "type": "icon",
          "content": {
            "properties": { "name": "tray" },
            "style": { "tintColor": "#999999" }
          }
        },
        {
          "type": "label",
          "content": {
            "properties": { "text": "No items yet" }
          }
        }
      ]
    }
  },
  "loadingState": {
    "type": "view",
    "content": {
      "children": [
        {
          "type": "label",
          "content": { "properties": { "text": "Loading..." } }
        }
      ]
    }
  },
  "errorState": {
    "type": "view",
    "content": {
      "children": [
        {
          "type": "label",
          "content": { "properties": { "text": "Failed to load" } }
        },
        {
          "type": "button",
          "content": {
            "properties": { "text": "Retry" },
            "actions": {
              "tap": { "type": "executeFunction", "function": "retry" }
            }
          }
        }
      ]
    }
  }
}
```

---

## Selection

Enable item selection with single or multiple modes. The selected value (or array of values) is written back to a variable via `binding`.

### Single Selection

```json
{
  "properties": {
    "selection": {
      "mode": "single",
      "binding": "{{selectedId}}"
    }
  }
}
```

### Multiple Selection

```json
{
  "properties": {
    "selection": {
      "mode": "multiple",
      "binding": "{{selectedIds}}"
    }
  },
  "actions": {
    "onSelectionChange": {
      "type": "executeFunction",
      "function": "handleSelectionChange"
    }
  }
}
```

| Mode | Description |
|------|-------------|
| `none` | No selection (default) |
| `single` | One item selected at a time |
| `multiple` | Toggle items in/out of a set |

---

## Scroll Behavior

### Inverted

Flip the scroll direction so the latest content appears at the bottom. Useful for chat-style lists.

```json
{
  "properties": {
    "inverted": true
  }
}
```

### Scroll Offset Output

Write the current scroll offset to a variable. The value updates as the user scrolls.

```json
{
  "properties": {
    "scrollOffsetVariable": "scrollY"
  }
}
```

The value written is the vertical (or horizontal) content offset in points, adjusted for content insets.

---

## Actions

### Item Tap

```json
{
  "actions": {
    "onItemTap": {
      "type": "navigation",
      "nextScreen": "details",
      "params": { "itemId": "{{item.id}}" }
    }
  }
}
```

### Pull to Refresh

```json
{
  "properties": {
    "pullToRefresh": true
  },
  "actions": {
    "onRefresh": { "type": "executeFunction", "function": "refresh" }
  }
}
```

### Pagination

Trigger a load-more action when the user scrolls within `threshold` items of the end.

```json
{
  "properties": {
    "pagination": {
      "threshold": 5
    }
  },
  "actions": {
    "onLoadMore": { "type": "executeFunction", "function": "loadMore" }
  }
}
```

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `threshold` | number | `5` | Number of items from the end that triggers `onLoadMore` |

---

## Nested Collections

A collection inside a collection template. The inner collection's `data` binds to a property on the outer `{{item}}`.

```json
{
  "type": "collection",
  "content": {
    "properties": { "data": "{{sections}}" },
    "layout": { "type": "vertical", "itemSpacing": 24 },
    "template": {
      "type": "view",
      "content": {
        "children": [
          {
            "type": "label",
            "content": {
              "properties": { "text": "{{item.title}}" },
              "style": { "text": { "fontSize": 20, "fontWeight": "bold" } },
              "layout": { "leading": 16, "top": 0 }
            }
          },
          {
            "type": "collection",
            "content": {
              "properties": { "data": "{{item.items}}" },
              "layout": {
                "type": "horizontal",
                "itemSpacing": 12,
                "itemWidth": 150,
                "itemHeight": 200
              },
              "template": {
                "type": "view",
                "content": {
                  "children": [
                    {
                      "type": "image",
                      "content": {
                        "properties": { "url": "{{item.imageUrl}}" },
                        "style": { "contentMode": "scaleAspectFill" },
                        "layout": { "leading": 0, "trailing": 0, "top": 0, "height": 150 }
                      }
                    },
                    {
                      "type": "label",
                      "content": {
                        "properties": { "text": "{{item.name}}" },
                        "layout": { "leading": 8, "trailing": 8, "top": 158 }
                      }
                    }
                  ]
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

---

## Complete Examples

### Simple List

```json
{
  "type": "collection",
  "content": {
    "properties": { "data": "{{users}}" },
    "layout": {
      "type": "vertical",
      "itemSpacing": 1,
      "separatorStyle": "full"
    },
    "style": {
      "separatorColor": "#E5E5EA"
    },
    "template": {
      "type": "view",
      "content": {
        "style": {
          "material": [{ "fill": { "solid": "#FFFFFF" } }]
        },
        "layout": { "height": 60 },
        "children": [
          {
            "type": "label",
            "content": {
              "properties": { "text": "{{item.name}}" },
              "style": { "text": { "fontSize": 17 } },
              "layout": { "leading": 16, "centerY": 0 }
            }
          },
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
    },
    "actions": {
      "onItemTap": {
        "type": "navigation",
        "nextScreen": "userDetail",
        "params": { "userId": "{{item.id}}" }
      }
    }
  }
}
```

### Photo Grid

```json
{
  "type": "collection",
  "content": {
    "properties": { "data": "{{photos}}" },
    "layout": {
      "type": "grid",
      "columns": 3,
      "itemSpacing": 2,
      "lineSpacing": 2,
      "aspectRatio": 1.0
    },
    "template": {
      "type": "image",
      "content": {
        "properties": { "url": "{{item.thumbnailUrl}}" },
        "style": { "contentMode": "scaleAspectFill" }
      }
    },
    "actions": {
      "onItemTap": {
        "type": "navigation",
        "nextScreen": "photoViewer",
        "params": { "photoId": "{{item.id}}" },
        "presentation": "fullScreen"
      }
    }
  }
}
```

### Paged Horizontal Carousel

```json
{
  "type": "collection",
  "content": {
    "properties": {
      "data": "{{slides}}",
      "scrollOffsetVariable": "carouselOffset"
    },
    "layout": {
      "type": "horizontal",
      "itemWidth": 320,
      "itemHeight": 200,
      "itemSpacing": 16,
      "pagingStyle": "pagingCentered",
      "currentPageVariable": "currentSlide",
      "contentInsets": { "left": 24, "right": 24 }
    },
    "template": {
      "type": "view",
      "content": {
        "style": {
          "material": [
            { "fill": { "solid": "#FFFFFF" } },
            { "corner": { "radius": 16 } }
          ]
        },
        "children": [
          {
            "type": "image",
            "content": {
              "properties": { "url": "{{item.imageUrl}}" },
              "style": { "contentMode": "scaleAspectFill" },
              "layout": { "leading": 0, "trailing": 0, "top": 0, "bottom": 0 }
            }
          }
        ]
      }
    }
  }
}
```

### Chat List (Inverted)

```json
{
  "type": "collection",
  "content": {
    "properties": {
      "data": "{{messages}}",
      "inverted": true
    },
    "layout": {
      "type": "vertical",
      "itemSpacing": 8,
      "contentInsets": { "top": 16, "bottom": 16, "left": 12, "right": 12 }
    },
    "template": {
      "type": "view",
      "content": {
        "children": [
          {
            "type": "label",
            "content": {
              "properties": { "text": "{{item.text}}" },
              "style": { "text": { "fontSize": 15 } },
              "layout": { "leading": 12, "trailing": 12, "top": 8, "bottom": 8 }
            }
          }
        ]
      }
    }
  }
}
```

### Grouped List with Section Headers

```json
{
  "type": "collection",
  "content": {
    "properties": {
      "data": "{{contacts}}",
      "groupBy": "item.section",
      "stickyHeaders": true
    },
    "layout": {
      "type": "vertical",
      "itemSpacing": 0,
      "separatorStyle": "inset"
    },
    "defaultSectionHeader": {
      "type": "view",
      "content": {
        "style": {
          "backgroundColor": "#F2F2F7"
        },
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
    },
    "template": {
      "type": "view",
      "content": {
        "style": { "material": [{ "fill": { "solid": "#FFFFFF" } }] },
        "layout": { "height": 56 },
        "children": [
          {
            "type": "label",
            "content": {
              "properties": { "text": "{{item.name}}" },
              "layout": { "leading": 16, "centerY": 0 }
            }
          }
        ]
      }
    },
    "actions": {
      "onItemTap": {
        "type": "navigation",
        "nextScreen": "contactDetail",
        "params": { "contactId": "{{item.id}}" }
      }
    }
  }
}
```
