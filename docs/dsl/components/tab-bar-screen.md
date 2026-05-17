# TabBarScreen

Tab-based navigation container.

## Content Properties

| Property | Type | Description |
|----------|------|-------------|
| `tabs` | Tab[] | Tab definitions |
| `initialTab` | string | Initial tab ID |
| `tintColor` | Color | Selected tab color |
| `unselectedColor` | Color | Unselected tab color |
| `hidden` | boolean/expression | Hide component |

## Tab Structure

| Property | Type | Description |
|----------|------|-------------|
| `id` | string | Unique tab identifier |
| `label` | string | Tab label text |
| `icon` | string | SF Symbol name |
| `screen` | string | Screen ID to display |

## Example

<!-- @dsl-type: Component -->
```json
{
  "type": "tabBarScreen",
  "content": {
    "tabs": [
      { "id": "home", "label": "Home", "icon": "house.fill", "screen": "homeScreen" },
      { "id": "search", "label": "Search", "icon": "magnifyingglass", "screen": "searchScreen" },
      { "id": "favorites", "label": "Favorites", "icon": "heart.fill", "screen": "favoritesScreen" },
      { "id": "profile", "label": "Profile", "icon": "person.fill", "screen": "profileScreen" }
    ],
    "initialTab": "home",
    "tintColor": "#007AFF",
    "unselectedColor": "#8E8E93"
  }
}
```
