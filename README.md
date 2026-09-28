# Downloads

Recent downloads, pictures and videos, one click from the Omarchy bar —
and every row is a drag handle, so a file goes straight into the upload field,
chat window, or editor that needs it.

The bar button carries a badge counting the files that arrived in the last few
minutes, so a finished download is visible without opening anything.

![Recent files with an image preview](screenshots/recent-files.png)

The **Recent files** panel merges your XDG Downloads, Pictures and Videos
folders, newest first. **All / Downloads / Images / Videos** switches between
the combined list, the download source, and image/video types across all three
sources. Opening the panel starts on All; the time filter keeps its selection.
Right-click Downloads, Images or Videos to open its configured source folder.
Right-click All gives a tiny nudge because it has no single folder.

The panel keeps its compact width and row height. Hover an image or video row
to preview it beside the list, on whichever side has more room. Every row stays
visible and reachable. Images fit a stable 4:3 canvas with a background sampled
from the image, and fade between files without an initial hover delay. Moving
quickly to another row replaces the pending preview with the latest selection.
GIF previews remain still.

Videos show a thumbnail and duration in the list, and play silently on a loop
when hovered. Leaving the row pauses playback; closing the panel or dragging
releases the player. Previews dismiss on pointer exit, scrolling or pressing
to drag, and never intercept input.

## Dependencies

- **Python 3** for folder scanning and media helpers.
- **Qt 6 Multimedia QML module** (`qt6-multimedia` on Arch) for video playback.
- **ffmpeg and ffprobe** (`ffmpeg` on Arch) for video thumbnails, durations and
  image-derived background colours. Without them, thumbnails use file icons
  and preview backgrounds use the theme colour. Video playback uses Qt Multimedia.

## A panel you can drag out of

The list opens as a layer-shell panel anchored to its bar button. It stays
out of the tiling layout and closes with Esc or a click outside it. No
Hyprland window rules are needed.

During a file drag, the panel limits its input region to the visible card
and removes outside-click surfaces on other monitors. This lets the
application under the pointer receive the drop. After the drag finishes or
is cancelled, outside-click dismissal is restored.

## Installing

```bash
omarchy plugin add https://github.com/jankeesvw/omarchy-downloads
omarchy plugin enable jankeesvw.downloads
omarchy bar move jankeesvw.downloads --section right
```

If upgrading from the floating-window version, the old rules matching
`org.quickshell` with title `Downloads` can be removed from your Hyprland
configuration; this panel does not use them.

### A key for it

```lua
o.bind("SUPER + D", "Downloads", "omarchy-shell shell toggle jankeesvw.downloads")
```

## Using it

| | |
|---|---|
| Click the bar button | open and close the list |
| Right-click the bar button | open the folder in your file manager |
| Drag a row | hand the file to whatever is under the cursor |
| Double-click a row | open the file |
| `N minutes` / `All time` | show only what just arrived, or the whole folder |
| `Esc` or click outside | close |

Downloaded folders appear alongside files, sorted by modification time. They
use a folder icon; double-click opens them in your file manager, and dragging
hands over the folder. Contents are not scanned recursively. Pictures and Videos contribute only
matching media files, so logs and other sidecar files stay out of those sources.

## Settings

Set these on the plugin's entry in `~/.config/omarchy/shell.json`:

| Setting | Default | What it does |
|---|---|---|
| `freshMinutes` | `5` | How recent a file counts as "just arrived" — drives the badge, the accent, and the first filter |
| `folder` | XDG download dir | Download source, as an absolute path |
| `picturesFolder` | XDG pictures dir | Image source, as an absolute path |
| `videosFolder` | XDG videos dir | Video source, as an absolute path |

```json
{ "id": "jankeesvw.downloads", "freshMinutes": 10 }
```

## Refresh and limits

- Partial downloads and hidden files are excluded. The active Omarchy screen
  recording is withheld while `/tmp/omarchy-screenrecord-filename` names it;
  it becomes available after Omarchy finalizes and clears that marker.
- Folder scans run in a separate process. Small folders also use a Qt folder
  watcher to trigger debounced scans after arrivals/removals. A periodic scan
  updates changed sizes and finished recordings: every 3 seconds while open,
  every 20 seconds while closed. Opening always refreshes.
- Each source scans at most 5000 entries and retains at most 200 per media
  category. The displayed filter caps at 200 rows. If a scan reaches the
  ceiling, the panel explicitly says it is partial; it cannot promise that
  the newest files outside that scan were seen. The hidden-file count applies
  to the selected source/type and time filters; older files do not inflate the
  count in the recent view.
- Duplicate paths appear once. Dragging freezes list replacement until the
  gesture ends, so background updates cannot destroy a row mid-drag.
- Video thumbnails are generated sequentially, only when rows are created in
  the open panel. Versioned thumbnails live in
  `$XDG_CACHE_HOME/omarchy-downloads/thumbnails` (normally `~/.cache/...`), with
  a limit of 256 thumbnails. Failed/unsupported media keep a file icon.
- Image background colours are decoded separately and cached in the sibling
  `colors` directory (up to 256 entries). The sampled colour is darkened by 30%.

## Verification

```sh
python3 -m unittest discover -s tests -v
node tests/test_filters.js
qmllint -I /usr/share/omarchy/shell *.qml
```

Node.js is needed only for the filter regression tests.

For UI verification, open each filter, hover first and last visible rows,
scroll through videos, drag into another app, and check double-click and Esc.
The panel should retain the previous compact width and row height.

## Removing it

```bash
omarchy plugin remove jankeesvw.downloads
```

The plugin keeps its list state in memory. Its private thumbnail and colour caches
can be removed separately from `~/.cache/omarchy-downloads` (or the matching
location under your custom `XDG_CACHE_HOME`). Original files are never changed.

If you added Hyprland window rules for an older version, remove those
separately from your Hyprland configuration.

## Privacy

Filenames never leave your machine. There is no network access, no telemetry,
and no remote thumbnail service. Local helpers list directories and decode video frames.
Filenames are rendered as `Text.PlainText` throughout, so a file named to look
like markup cannot make the shell fetch a remote image.

## License

MIT — see [LICENSE](LICENSE).
