# Map

Interactive map view backed by `MKMapView`. Supports static and dynamic annotations, directions routing, and two-way variable bindings for region, selected annotation, and user location.

## Content Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `properties.mapType` | string | `"standard"` | Map style: `"standard"`, `"satellite"`, `"hybrid"`, `"satelliteFlyover"`, `"hybridFlyover"`, `"mutedStandard"` |
| `properties.showUserLocation` | boolean | `false` | Show blue dot for user's location (requires permission) |
| `properties.zoomEnabled` | boolean | `true` | Allow pinch-to-zoom |
| `properties.scrollEnabled` | boolean | `true` | Allow panning |
| `properties.rotateEnabled` | boolean | `true` | Allow rotation gesture |
| `properties.pitchEnabled` | boolean | `true` | Allow 3D tilt gesture |
| `properties.center` | object or expression | map default | `{ "latitude": X, "longitude": Y }` or `"{{coordVar}}"` |
| `properties.span` | object | map default | `{ "latitudeDelta": X, "longitudeDelta": Y }` — controls zoom level |
| `properties.annotations` | Annotation[] | none | Static array of pin definitions |
| `properties.annotationsExpression` | string | none | Expression resolving to array variable, e.g. `"{{locations}}"` |
| `properties.showDirections` | boolean | `false` | Render a route polyline between `routeFrom` and `routeTo` |
| `properties.routeFrom` | object or expression | none | Start coordinate for directions |
| `properties.routeTo` | object or expression | none | End coordinate for directions |
| `properties.routeTransportType` | string | `"automobile"` | `"automobile"`, `"walking"`, `"transit"` |
| `properties.polyline` | Coordinate[] or expression | none | Draw a line directly — array of `{ "latitude", "longitude" }` or `"{{coordsVar}}"` |
| `properties.polylineFollowsRoads` | boolean | `false` | Treat `polyline` points as via-points and snap the line to real roads (via MKDirections) |
| `properties.viewportInsets` | EdgeInsets | none | Padding reserved at each map edge when auto-fitting to a polyline/annotations |
| `properties.regionBinding` | string | none | Expression variable to write current map region into, e.g. `"{{mapRegion}}"` |
| `properties.selectedAnnotationBinding` | string | none | Expression variable to write selected annotation ID into |
| `properties.userLocationBinding` | string | none | Expression variable to write user coordinate into |
| `properties.routeStatusBinding` | string | none | Expression variable that receives `"ok"` or `"error"` after a directions request |
| `hidden` | boolean/expression | none | Hide component |

## Annotation Object

Each entry in `annotations` (or elements of the `annotationsExpression` array) must follow this structure:

**Static annotations** (used directly in `annotations`):
```json
{
  "id": "unique-id",
  "coordinate": { "latitude": 37.7749, "longitude": -122.4194 },
  "title": "Location Name",
  "subtitle": "Optional subtitle",
  "color": "#FF6B6B"
}
```

**Dynamic annotations** (elements of a variable array referenced by `annotationsExpression`): use flat top-level keys — `id`, `latitude`, `longitude`, `name` (used as title), `color`.

## Actions

| Trigger | Description |
|---------|-------------|
| `onAnnotationTap` | Fires when the user taps a pin. `{{item.id}}`, `{{item.title}}`, and other annotation fields are available in the action's value expressions. |

> Map triggers also accept an `analytics` binding for tracking — see [`../analytics.md`](../analytics.md).

## Example — Static Map Card

Fixed region with zoom and scroll disabled, one annotation:

```json
{
  "type": "map",
  "content": {
    "properties": {
      "mapType": "mutedStandard",
      "zoomEnabled": false,
      "scrollEnabled": false,
      "center": { "latitude": 37.7749, "longitude": -122.4194 },
      "span": { "latitudeDelta": 0.01, "longitudeDelta": 0.01 },
      "annotations": [
        {
          "id": "hq",
          "coordinate": { "latitude": 37.7749, "longitude": -122.4194 },
          "title": "Headquarters",
          "color": "#FF6B6B"
        }
      ]
    },
    "layout": {
      "width": 320,
      "height": 200,
      "constraints": [
        { "type": "centerX", "target": "superview" },
        { "type": "centerY", "target": "superview" }
      ]
    }
  }
}
```

## Example — Dynamic Pins

Annotations driven by a variable array:

```json
{
  "type": "map",
  "content": {
    "properties": {
      "center": { "latitude": 37.7749, "longitude": -122.4194 },
      "span": { "latitudeDelta": 0.05, "longitudeDelta": 0.05 },
      "annotationsExpression": "{{locations}}"
    },
    "layout": {
      "width": 320,
      "height": 300,
      "constraints": [
        { "type": "centerX", "target": "superview" },
        { "type": "top", "target": "superview", "constant": 20 }
      ]
    }
  }
}
```

## Example — Interactive Pins

Selected annotation ID written to a variable; tap action navigates to detail:

```json
{
  "type": "map",
  "content": {
    "properties": {
      "center": { "latitude": 37.7749, "longitude": -122.4194 },
      "span": { "latitudeDelta": 0.05, "longitudeDelta": 0.05 },
      "showUserLocation": true,
      "annotationsExpression": "{{locations}}",
      "selectedAnnotationBinding": "{{selectedId}}"
    },
    "actions": {
      "onAnnotationTap": [
        {
          "type": "updateVariable",
          "variableName": "selectedId",
          "value": "{{item.id}}"
        }
      ]
    },
    "layout": {
      "width": 320,
      "height": 400,
      "constraints": [
        { "type": "centerX", "target": "superview" },
        { "type": "centerY", "target": "superview" }
      ]
    }
  }
}
```
