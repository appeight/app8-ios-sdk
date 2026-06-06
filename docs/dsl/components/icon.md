# Icon

Displays an icon — an SF Symbol, a bundled asset, or a remote image — with an optional tint and background. The `type` selects the source.

## Content Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `properties.type` | IconType | | Icon source — see [Icon Types](#icon-types) |
| `properties.name` | string | | SF Symbol name (`type: "symbol"`) or asset name (`type: "asset"`) |
| `properties.url` | string | | Image URL (`type: "remote"`) |
| `properties.tintColor` | color/expression | | Tint color. Accepts an expression, e.g. `"{{item.iconColor}}"`, or the wrapped `{ value, animation }` form |
| `properties.backgroundColor` | color/expression | | Background color. Accepts an expression or the wrapped `{ value, animation }` form |
| `properties.isHidden` | boolean/expression | | Hide via expression, e.g. `"{{!isChecked}}"` |
| `style` | IconStyle | | Icon styling — see [styles.md → IconStyle](../styles.md#iconstyle) |
| `layout` | Layout | | Position and size |
| `hidden` | boolean/expression | | Hide component |

> **Tint via property or style**: the `tintColor` property is expression- and animation-friendly — prefer it for dynamic colors. The static `tint`/`color` on [IconStyle](../styles.md#iconstyle) is equivalent for fixed colors.

## Icon Types

| `type` | Source | Companion property |
|--------|--------|--------------------|
| `symbol` | SF Symbol | `name` (e.g. `"heart.fill"`) |
| `asset` | Bundled image asset | `name` |
| `remote` | Remote image | `url` |
| `none` | Renders nothing | — |

> SF Symbol **weight and scale** are set through the icon's [IconStyle](../styles.md#iconstyle) (`symbolFontSize`, `renderingMode`, …), not as `properties`.

## Style: IconStyle

The most-used fields are below; see [styles.md → IconStyle](../styles.md#iconstyle) for the full set (`renderingMode`, `symbolFontSize`, `fontId`, `contentMode`, `transform`, …).

| Property | Type | Description |
|----------|------|-------------|
| `tint` | Color | Icon color (static; for dynamic use the `tintColor` property) |
| `symbolFontSize` | number | SF Symbol point size |
| `material` | Material | Background |
| `alpha` | number | Opacity |

## Example

<!-- @dsl-type: Component -->
```json
{
  "type": "icon",
  "content": {
    "properties": {
      "type": "symbol",
      "name": "heart.fill",
      "tintColor": "{{isLiked ? '#FF3B30' : '#C7C7CC'}}"
    },
    "style": {
      "symbolFontSize": 24
    },
    "layout": {
      "width": 44,
      "height": 44
    }
  }
}
```

## See Also

- [styles.md → IconStyle](../styles.md#iconstyle) — full icon styling surface
- [image.md](image.md) — for content images rather than glyphs
