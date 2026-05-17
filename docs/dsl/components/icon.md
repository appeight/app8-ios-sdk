# Icon

SF Symbol display component.

## Content Properties

| Property | Type | Description |
|----------|------|-------------|
| `properties.name` | string | SF Symbol name |
| `properties.weight` | FontWeight | Symbol weight |
| `properties.scale` | Scale | Symbol scale |
| `style` | IconStyle | Icon styling |
| `layout` | Layout | Position and size |
| `hidden` | boolean/expression | Hide component |

## FontWeight Values

`ultraLight`, `thin`, `light`, `regular`, `medium`, `semibold`, `bold`, `heavy`, `black`

## Scale Values

`small`, `medium`, `large`

## Style: IconStyle

| Property | Type | Description |
|----------|------|-------------|
| `tintColor` | Color | Icon color |
| `material` | Material | Background |
| `alpha` | number | Opacity |

## Example

<!-- @dsl-type: Component -->
```json
{
  "type": "icon",
  "content": {
    "properties": {
      "name": "heart.fill",
      "weight": "medium",
      "scale": "large"
    },
    "style": {
      "tintColor": "#FF3B30"
    },
    "layout": {
      "width": 44,
      "height": 44
    }
  }
}
```
