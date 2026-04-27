# tkmcairo Changelog

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
