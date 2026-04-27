# tkmcairo Changelog

## v0.1.1 (2026-04-27)

Maintenance release — visibility for Y2 axis (was implemented in 0.1
but undocumented), pageview robustness, dependency clarity, streaming
export to channels, and the `imageviewer` widget promoted from demo.

### New widget — `tkmcairo::imageviewer`

The image-viewer demo from 0.1.0 has been promoted to a real widget.
Same feature set as the demo (PNG/JPEG load via Img or tclmcairo
fallback, navigation through sibling files, zoom/pan, vector and PNG
export), but now reusable as a single command:

```tcl
package require tkmcairo::imageviewer
tkmcairo::imageviewer .iv
pack .iv -fill both -expand 1
.iv load /path/to/picture.png
```

Construction options: `-width`, `-height`, `-file`, `-background`,
`-toolbar` (0/1, default 1), `-zoom-min`, `-zoom-max`.

Widget commands: `load`, `open`, `prev`, `next`, `filelist`,
`fileindex`, `fit`, `zoom`, `zoom1`, `pan`, `info`, `export`
(file or `-chan`), `toolbar`, `configure`, `cget`.

The widget uses Tk Canvas internally for fast pan-without-Cairo-roundtrip;
a `tkmcairo::surface`-based variant is on the 0.3 roadmap. JPEG support
works without `Img` via tclmcairo's libjpeg binding (PPM bridge).

11 new tests (`imageviewer-1.0` to `-1.10`). The old
`demos/demo-imageviewer.tcl` (333 lines of application code) has been
replaced with a 50-line widget-usage demo.

### Channel export (`-chan`) for all exporting widgets

`tkmcairo::surface`, `plot`, `viewport`, `svgview`, and `pageview` now
all accept an open Tcl channel as export target — same API as
tclmcairo (since 0.3.2) and canvas2cairo:

```tcl
$w export filename.pdf                ;# unchanged — file destination
$w export -chan $ch -format png       ;# new — stream to channel
$w export -chan $ch -format pdf       ;# also for vector formats
```

How each widget streams:

- `surface` uses `tclmcairo save -chan` directly for PNG (since 0.3.2),
  with fallback to `topng + puts` for older tclmcairo. Vector formats
  go through a brief tempfile under `$::env(TMPDIR)` then `fcopy` —
  required because Cairo PDF/SVG/PS need seekable output.
- `plot`, `viewport`, `svgview` all delegate to `surface::_export`,
  so they inherit the channel API for free.
- `pageview` decodes the current page's Tk photo as PNG bytes (via
  `data -format png` + `binary decode base64`) and streams the bytes.
  Tk photo's `write` does not accept channels itself.

`scene` has no `export` of its own — render through the underlying
`surface` and use that widget's export instead.

The PNG path of `surface::export` to a file also no longer
allocates the PNG twice (Cairo internal + Tcl string): it now uses
`tclmcairo save` directly. Old code path is kept as a fallback for
tclmcairo < 0.3.2.

7 new tests (`surface-export-1.0` to `-1.3`, plus `plot-chan-1.0`,
`viewport-chan-1.0`, `pageview-chan-1.0`).

### Plot — secondary Y axis (now documented)

The Y2 axis, present in code since 0.1 but not surfaced in any doc, is
now first-class:

```tcl
.p y2axis -label "Growth (%)" -min 0 -max 25 -ticks 5
.p series line revenue -data {...} -color {0.2 0.4 0.85}
.p series line growth  -data {...} -color {0.85 0.3 0.2} -yaxis y2
```

- New demo: `demos/demo-plot-y2.tcl` — revenue vs growth-rate
- README documents the API and shows a usage example
- `make demo-plot-y2` target added
- 4 new tests (`plot-y2-1.0` to `-1.3`) covering range computation,
  series routing and `axis::drawY2` presence

### Pageview — robustness fixes

- **tmpdir** for cached PNGs now lives under the **system temp**
  (`$::env(TMPDIR)`, `/tmp`, `$::env(TEMP)` in that order) — was
  derived from `info script` which fails on read-only installs and
  caused permission issues during cleanup.
- Smoke tests added (`pageview-smoke-1.0` to `-1.3`) — package loads,
  backend detection works, opts dict initialised correctly.

### Dependencies — README clarity

The README now explicitly lists required vs optional dependencies
and what each one enables:

- `wish` (not plain `tclsh`)
- `tclmcairo` 0.3.5+ (with graceful fallback to older APIs)
- Optional: `Img`, `tDOM`, `pdfiumtcl` or `poppler-utils`,
  `scrollutil_tile`, `HAVE_LUNASVG` build of tclmcairo

### Modules

All 10 modules bumped to `0.1.1`:
- axis, coords, data, legend, pageview, plot, scene, surface,
  svgview, viewport

## v0.1.0 (2026-04-16)

Second iteration — adds viewport, scene graph, SVG viewer, PDF page viewer,
and integrates the new tclmcairo 0.3.5 image-buffer pool.

### New widgets

- **`tkmcairo::viewport-0.1`** — scrollable, zoomable wrapper around
  `surface`. Optional native `ttk::scrollbar` (`-scrollbars 1`).
  World-coordinate API: `zoom factor ?cx cy?`, `zoomfit`, `zoom1`,
  `pan dx dy`, `worldToScreen`, `screenToWorld`.
- **`tkmcairo::scene-0.1`** — retained-mode scene graph with dirty-flag
  tracking. Items: rect, oval, line, text, image, path, circle. Tag-based
  group operations, per-item `-visible` flag, only re-renders on change.
- **`tkmcairo::svgview-0.1`** — SVG viewer widget. Backends: `auto` /
  `luna` (lunasvg) / `svg2cairo` (tDOM). Zoom, pan, export.
- **`tkmcairo::pageview-0.1`** — PDF page-preview widget. Backends:
  pdfiumtcl (preferred) or poppler (`pdftoppm`/`pdfinfo`). Navigation,
  zoom, bookmarks panel, text search, export.

### Plot improvements

- `tkmcairo::plot` extended: pie series, time axis, interactive tooltip,
  interactive legend, secondary Y axis (`-y2`).

### Surface

- `surface-0.1` now uses `toppm` instead of `topng` for Tk photo
  updates — ~10× faster (no zlib round-trip).
- Backed by tclmcairo 0.3.5 image buffer pool: `image_load` / `image_blit`
  / `image_scale` / `image_free` / `image_info` / `image_load_surface`.

### Demos

- `demo-imageviewer.tcl` — rewritten on top of `imgtools` + Tk Canvas
  (Cairo only used for export). JPEG support via optional `Img` package.
  Pre-downscaling above 2× display size; pan via Canvas move, zoom via
  `imgtools::scale` with Lanczos3.
- `demo-svgview.tcl`, `demo-pageview.tcl`, `demo-viewport.tcl`,
  `demo-scene.tcl`, `demo-axis.tcl` — added.

### Dependencies

- tclmcairo 0.3.5 (image-pool + `toppm`)
- imgtools 0.3 (imageviewer scaling)
- Img (JPEG support in Tk, optional)
- pdfiumtcl 0.4 (pageview, preferred)
- tDOM (svgview via svg2cairo)

### Tests

39 tests pass.

---

## v0.1.0 (2026-04-12) — initial release

First public iteration. Two widgets, three demos.

### `tkmcairo::surface-0.1`

Cairo drawing surface as a Tk widget — the foundation of the library.

- ttk::frame + ttk::label hosting an off-screen Cairo context
- `-drawcommand` callback receives `$ctx $w $h`
- PNG / PDF / SVG / PS / EPS export via `$w export filename`
- Resize debounce (30 ms `after` with `pending` flag)
- Auto-redraw on resize (`-autoresize` toggle)

### `tkmcairo::plot-0.1`

Chart widget on top of `surface`. Series types: `line`, `area`, `scatter`,
`bar`. X/Y axes with labels, ticks, grid. Padding, title, font, background.

### Architecture

- Widget command via `rename` + `interp alias` — the original `ttk::frame`
  is renamed, then aliased to a dispatcher proc. Order matters:
  `interp alias` must not delete an existing command, or Tk destroys the
  window.
- Per-instance namespace `::tkmcairo::WIDGET::S_<path>` — `S_` prefix is
  required because dot in the widget path (`.p`) would otherwise look
  like a sub-namespace.
- Drawcommand for `plot` uses string-style: `[list $w]` substituted at
  definition time, `\$ctx \$w \$h` resolved at call time from globals.
- `_cmd` never calls `$w subcmd` — `$w` is the alias to `_cmd` itself,
  which would recurse infinitely. Always direct proc calls
  (`::tkmcairo::surface::_redraw $w` etc.).
- Coordinate transforms inside `plot` use `apply` lambdas instead of
  global procs, because plain procs lack closure over locals.

### Demos

- `demo-surface.tcl` — five demos (Shapes, Gradients, Text, Transparency,
  Animation) with export buttons via `tk_getSaveFile`.
- `demo-plot.tcl` — five charts plus PDF/SVG/PNG export.
- `demo-imageviewer.tcl` — PNG/JPEG viewer with zoom, pan and export.

### Known limitations (0.1)

- No clipping in plot series — points outside the plot area are drawn.
- No zoom/pan in `surface` (added in 0.1 follow-up via `viewport`).
- `text_extents` demo incomplete.
- Windows: requires MSYS2 Cairo DLLs alongside `tclmcairo`.
