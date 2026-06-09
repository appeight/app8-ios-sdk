# Video

Looping background video — muted, autoplaying, seamlessly looping playback with no
playback chrome. Designed for onboarding and marketing screens where a short clip plays
behind or within the layout, behaving like an animated `image`.

> **Sources:** a `localAsset` bundled in the host app target (`.mp4` / `.mov` / `.m4v`),
> or a `remoteAsset` resolved at runtime through the data source (the host's prefetched
> asset cache) — exactly like `image`. Use `remoteAsset` for backend/uploaded videos;
> `localAsset` only works when the file is compiled into the app target.

## Content Properties

| Property | Type | Description |
|----------|------|-------------|
| `properties.type` | string | Source type: `localAsset`, `remoteAsset`, or `none` |
| `properties.name` | string | For `localAsset`: bundle resource name (`"intro"` / `"intro.mp4"`). For `remoteAsset`: the asset's name/filename as listed by the host (e.g. `assets.json`). |
| `properties.id` | string | `remoteAsset` only — the backend asset id. The data source resolves by `id` first, then `name`. |
| `properties.url` | string | `remoteAsset` only — an explicit URL to stream when the asset isn't in the data source. |
| `properties.autoplay` | boolean | Start playing when on-screen. Default `true` |
| `properties.loop` | boolean | Seamlessly loop playback. Default `true` |
| `properties.muted` | boolean | Mute audio. Default `true` |
| `style` | VideoStyle | Video styling |
| `layout` | Layout | Position and size |

The player automatically **pauses and releases** when the view leaves the screen (scrolled
off, recycled in a collection/table cell, or the app backgrounds) and resumes when it
returns — so a video inside an onboarding loop doesn't burn CPU/battery off-screen.

## Diagnostics

For a **`localAsset`**, the `name` must resolve to a file in the **app bundle** (the host
app target). If it doesn't, the video renders empty. App8 diagnostics flag this at
validation time:

> **WARNING [VID001]:** Video `"intro-video"` references local asset `"intro"` which was
> not found in the app bundle…

The check recurses into nested components; names containing `{{…}}` are skipped (resolved
at runtime). **`remoteAsset` videos are NOT subject to VID001** — they resolve at runtime
via the data source, not the bundle. At runtime a `remoteAsset` that can't be resolved
(no bytes from the data source and no usable `url`) is logged and renders nothing.

## Style: VideoStyle

| Property | Type | Description |
|----------|------|-------------|
| `contentMode` | ContentMode | How the video fills its frame (maps to video gravity) |
| `corner` | Corner | Corner radius |
| `material` | Material | Background material |
| `alpha` | number | Opacity |

## ContentMode → video gravity

| Value | Behavior |
|-------|----------|
| `scaleAspectFill` *(default)* | Fill the frame, cropping overflow |
| `scaleAspectFit` | Fit within the frame, letterboxed |
| `scaleToFill` | Stretch to fill, ignoring aspect ratio |

## Example

<!-- @dsl-type: Component -->
```json
{
  "type": "video",
  "id": "onboarding-loop",
  "content": {
    "properties": {
      "type": "localAsset",
      "name": "intro",
      "loop": true,
      "muted": true,
      "autoplay": true
    },
    "style": {
      "contentMode": "scaleAspectFill",
      "corner": { "radius": 16, "curve": "continuous" }
    },
    "layout": {
      "width": "100%",
      "height": 240
    }
  }
}
```

### Example — remoteAsset (backend/uploaded video)

Reference the asset by its `name` (the host's asset list / `assets.json`); add `id` when
you have the backend asset id so it resolves even if the name changes.

<!-- @dsl-type: Component -->
```json
{
  "type": "video",
  "id": "heroLoop",
  "content": {
    "properties": {
      "type": "remoteAsset",
      "name": "shutterAnimation",
      "loop": true,
      "muted": true,
      "autoplay": true
    },
    "style": {
      "contentMode": "scaleAspectFill",
      "corner": { "radius": 16, "curve": "continuous" }
    },
    "layout": { "width": "100%", "height": 240 }
  }
}
```
