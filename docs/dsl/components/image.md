# Image

Image display component.

## Content Properties

| Property | Type | Description |
|----------|------|-------------|
| `properties.url` | string | Remote image URL |
| `properties.asset` | string | Local asset name |
| `style` | ImageStyle | Image styling |
| `layout` | Layout | Position and size |
| `hidden` | boolean/expression | Hide component |

## Style: ImageStyle

| Property | Type | Description |
|----------|------|-------------|
| `contentMode` | ContentMode | How image fills bounds |
| `tintColor` | Color | Tint for template images |
| `renderingMode` | RenderingMode | Image rendering mode |
| `corner` | Corner | Corner radius |
| `material` | Material | Background material |
| `alpha` | number | Opacity |

## ContentMode Values

| Value | Description |
|-------|-------------|
| `scaleToFill` | Stretch to fill |
| `scaleAspectFit` | Fit maintaining aspect ratio |
| `scaleAspectFill` | Fill maintaining aspect ratio |
| `center` | Center without scaling |

## RenderingMode Values

| Value | Description |
|-------|-------------|
| `automatic` | System decides |
| `alwaysTemplate` | Render as template (tintable) |
| `alwaysOriginal` | Render original colors |

## Example

<!-- @dsl-type: Component -->
```json
{
  "type": "image",
  "content": {
    "properties": {
      "url": "https://example.com/photo.jpg"
    },
    "style": {
      "contentMode": "scaleAspectFill",
      "corner": { "radius": 8 }
    },
    "layout": {
      "width": 100,
      "height": 100
    }
  }
}
```
