# Video

Muted, autoplaying video with no playback chrome — designed for onboarding and marketing
screens where a short clip plays behind or within the layout, behaving like an animated
`image`. Supports seamless looping, posters, end behaviors, timing controls
(`startDelay` / `startTime` / `rate`), and playback events.

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
| `properties.endBehavior` | string | What happens when a non-looping clip ends: `freezeLastFrame` *(default)*, `loop`, `showPoster`, `hidePoster`. See [End behavior](#end-behavior). |
| `properties.startDelay` | number | Seconds to wait before playback starts (the poster stays up during the delay). Default `0` |
| `properties.startTime` | number | Seek offset in seconds — playback begins at this point in the clip. Default `0` |
| `properties.rate` | number | Playback rate (`0.5` = half speed, `2.0` = double). Default `1.0` |
| `properties.poster` | PosterSource | Still shown before the first frame paints (and during `startDelay`). See [Posters](#posters). |
| `properties.endPoster` | PosterSource | Still shown after completion when `endBehavior` is `showPoster` (falls back to `poster`). |
| `properties.marks` | Mark[] | Named time points that fire `onTimeMark` as playback crosses them. See [Time marks](#time-marks). |
| `style` | VideoStyle | Video styling |
| `layout` | Layout | Position and size |

> `loop: true` and `endBehavior: "loop"` are equivalent — either makes the clip repeat.

The player automatically **pauses and releases** when the view leaves the screen (scrolled
off, recycled in a collection/table cell, or the app backgrounds) and resumes when it
returns — so a video inside an onboarding loop doesn't burn CPU/battery off-screen.

Playback startup (seek, `startDelay`, `rate`) is **gated on the item becoming ready**, so
those settings apply reliably rather than being dropped against a not-yet-loaded item.

## End behavior

When a non-looping clip reaches its end, `endBehavior` decides what's shown:

| Value | Behavior |
|-------|----------|
| `freezeLastFrame` *(default)* | Hold the final frame. |
| `loop` | Restart from the top (same as `loop: true`). |
| `showPoster` | Reveal `endPoster` (or `poster` if no `endPoster`). |
| `hidePoster` | Hide the player layer entirely. |

## Posters

A `poster` is a still shown before playback starts and held during `startDelay`; it fades
out when the first frame begins to play. `endPoster` is shown after completion under
`endBehavior: "showPoster"`. Both are a `PosterSource` object:

| `type` | Fields | Source |
|--------|--------|--------|
| `firstFrame` | — | The clip's frame at `t=0`, generated on device. |
| `frameAtTime` | `time` (seconds) | A generated frame at the given time. |
| `remoteAsset` | `name` / `id` | An image resolved through the data source (host's asset cache), like `image`. |
| `url` | `url` | An image loaded from an explicit URL. |
| `localAsset` | `name` | An image bundled in the app target (`UIImage(named:)`). |

## Timing

- `startDelay` — keep the poster up for N seconds before playback begins.
- `startTime` — begin playback partway into the clip (seek offset).
- `rate` — play slower/faster than real time (`0.5`–`2.0` are typical).

## Time marks

`marks` is a list of `{ "id": string, "time": number }`. As playback crosses each time the
engine fires `onTimeMark` with the crossed mark's id available to actions as `{{$markId}}`.
Marks re-arm on each loop cycle.

## Playback events

Wire actions / analytics to playback lifecycle via these triggers (see
[`actions.md`](../actions.md)): `onVideoReady`, `onVideoStart`, `onVideoPause`,
`onVideoComplete`, `onVideoLoop` (overlay `$loopCount`), `onVideoStall`, `onVideoError`
(overlay `$error`), and `onTimeMark` (overlay `$markId`). Overlays are referenced from
action expressions like any variable, e.g. `"value": "{{$markId}}"`.

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

### Example — poster, end behavior, timing & events

A non-looping clip that holds a poster during a start delay, plays at half speed, freezes
on its last frame, and updates a screen variable as it crosses a time mark.

<!-- @dsl-type: Component -->
```json
{
  "type": "video",
  "id": "featureClip",
  "content": {
    "properties": {
      "type": "remoteAsset",
      "name": "feature.mp4",
      "autoplay": true,
      "loop": false,
      "muted": true,
      "startDelay": 1.5,
      "rate": 0.5,
      "endBehavior": "freezeLastFrame",
      "poster": { "type": "firstFrame" },
      "marks": [ { "id": "midpoint", "time": 2.5 } ]
    },
    "style": { "contentMode": "scaleAspectFill" },
    "layout": { "width": "100%", "height": 240 },
    "actions": {
      "onVideoComplete": [
        { "type": "updateVariable", "variableName": "status", "value": "done" }
      ],
      "onTimeMark": [
        { "type": "updateVariable", "variableName": "lastMark", "value": "{{$markId}}" }
      ]
    }
  }
}
```
