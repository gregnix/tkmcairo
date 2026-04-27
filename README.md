# tkmcairo

Cairo-based Tk widgets for high-quality rendering.

> **Status: 0.1.1 — Early Preview**  
> API is subject to change. Not yet production-stable.  
> Feedback and bug reports welcome.

Built on [tclmcairo](https://github.com/gregnix/tclmcairo) —
no tkpath dependency, runs on all platforms where tclmcairo runs.

## Overview

tkmcairo provides Cairo-based drawing widgets for Tk applications.
The core idea: a `ttk::label` backed by an off-screen Cairo surface
renders to a Tk photo image via `topng`. This gives:

- Antialiased rendering on all platforms
- Vector export (PDF, SVG) from the same draw code
- No X11 surface required — works headless in `tclsh`
- Composable: small core API, specialized widgets on top

## Modules

| Module | Status | Description |
|--------|--------|-------------|
| `tkmcairo::surface` | **0.1 — available** | Core Cairo drawing widget |
| `tkmcairo::plot`    | **0.1 — available** | Chart widget (line, area, bar, scatter, pie, time-axis, **Y2-axis**) |
| `tkmcairo::coords`  | **0.1 — available** | Coordinate transform helpers |
| `tkmcairo::axis`    | **0.1 — available** | Axis drawing helpers (X, Y, Y2) |
| `tkmcairo::legend`  | **0.1 — available** | Interactive plot legend |
| `tkmcairo::data`    | **0.1 — available** | Data series helpers |
| `tkmcairo::viewport`| **0.1 — available** | Pan/zoom wrapper around `surface` |
| `tkmcairo::scene`   | **0.1 — available** | Retained-mode scene graph |
| `tkmcairo::svgview` | **0.1 — available** | SVG viewer widget |
| `tkmcairo::pageview`| **0.1 — available** | PDF page viewer (pdfiumtcl/poppler) |
| `tkmcairo::imageviewer` | **0.1.1 — available** | Image viewer widget (open, navigate, zoom, pan, export) |
| `tkmcairo::tilelayer` | planned 0.3 | OSM tile layer |
| `tkmcairo::mapview` | planned 0.3 | Map viewer (tilelayer + viewport) |
| `tkmcairo::widgets` | planned 0.2 | Cairo-rendered Tk widgets |

## Requirements

### Required

- **Tcl/Tk 8.6+** (run with `wish`, not plain `tclsh` — Tk widgets needed)
- **[tclmcairo](https://github.com/gregnix/tclmcairo) 0.3.5+** —
  the C-level Cairo binding. tkmcairo 0.1.1 uses `image_load_surface`,
  `toppm`, and `image_from_ppm` from tclmcairo 0.3.5/0.3.6 when
  available, with graceful fallback to older APIs when not.

### Optional

- **`scrollutil_tile`** — for `viewport -scrollbars 1` (auto-detected)
- **`imgtools`** — for high-quality scaling (lanczos3/2, catrom) in
  `imageviewer`. Without it, scaling falls back to plain Tk photo copy.
- **`Img`** — for native JPEG support in `imageviewer`
  (with fallback to `tclmcairo image_load` + `toppm`, no `Img` needed)
- **`tDOM`** — for `svgview` with the `svg2cairo` backend
- **PDF backends for `pageview`** (one of):
  - `pdfiumtcl` (preferred, private package — fastest)
  - **poppler-utils** providing `pdftoppm` and `pdfinfo` (common,
    works on most Linux distros via `apt install poppler-utils`)

### Optional Cairo-side

- **`HAVE_LUNASVG`** in tclmcairo — full SVG support in `svgview` and
  `pageview` SVG layers (built via `tclmcairo/buildlt.sh`)

## Quick Start

```tcl
package require tkmcairo::surface

tkmcairo::surface .s \
    -width 400 -height 300 \
    -drawcommand {myDraw $ctx $w $h}

pack .s -fill both -expand 1

proc myDraw {ctx w h} {
    $ctx gradient_linear bg 0 0 $w $h \
        {{0 0.1 0.3 0.6 1} {1 0.4 0.1 0.5 1}}
    $ctx rect 0 0 $w $h -fillname bg
    $ctx circle [expr {$w/2.0}] [expr {$h/2.0}] 80 \
        -fill {1 0.8 0.2 0.9} -stroke {1 1 1} -width 3
    $ctx text [expr {$w/2.0}] [expr {$h/2.0}] "tkmcairo" \
        -font "Sans Bold 20" -color {0.1 0.1 0.1} -anchor center
}
```

## tkmcairo::surface API

```tcl
tkmcairo::surface pathName ?options?

Options:
  -width       px       initial width  (default 400)
  -height      px       initial height (default 300)
  -drawcommand script   called as: script $ctx $w $h
  -background  {r g b}  background fill (default {1 1 1})
  -autoresize  0|1      redraw on resize (default 1)

Widget commands:
  $w redraw            force redraw
  $w export filename   save PNG / PDF / SVG / PS / EPS to a file
  $w export -chan $ch -format fmt   stream to an open channel  (0.1.1)
  $w ctx               current tclmcairo context object
  $w width / height    current size in pixels
  $w configure ...
  $w cget option
```

Draw command receives `ctx w h` as positional arguments:
```tcl
-drawcommand {myDraw $ctx $w $h}
proc myDraw {ctx w h} { ... }
```

## tkmcairo::plot API

```tcl
tkmcairo::plot pathName ?options?

Options: -width -height -title -background -font -padding {l t r b}

$p xaxis -label str -min n -max n -ticks n -format str -grid 0|1 -gridcolor {r g b}
$p yaxis ...same...
$p y2axis -label str -min n -max n -ticks n -format str
                                                 ;# secondary right-side Y axis

$p series line    name -data {x y ...} -color {r g b} -width n -alpha a
                       -dash list -marker circle|none -markersize n
                       -yaxis y1|y2          ;# default y1; y2 = right axis
$p series area    name -data {x y ...} -color {r g b} -alpha a -width n
$p series scatter name -data {x y ...} -color {r g b} -markersize n
$p series bar     name -data {label val ...} -color {r g b} -alpha a
$p series pie     name -data {label val ...} -colors {{r g b} ...}

$p clear / $p redraw / $p export file
$p export -chan $ch -format fmt   ;# stream to channel (0.1.1)
```

### Secondary Y axis (Y2)

Use Y2 for series whose values live on a different scale — e.g. revenue (€)
on the left axis and growth rate (%) on the right. Y2 has its own range,
ticks, and label, computed independently of Y1:

```tcl
.p y2axis -label "Growth (%)" -min 0 -max 100 -ticks 5
.p series line revenue -data {1 12500 2 13800 3 15200} \
    -color {0.2 0.4 0.85}                       ;# implicit Y1
.p series line growth  -data {1 4.2 2 5.8 3 6.1} \
    -color {0.85 0.3 0.2} -yaxis y2             ;# explicit Y2
```

See `demos/demo-plot-y2.tcl` for a full example.

## tkmcairo::imageviewer API

```tcl
tkmcairo::imageviewer pathName ?options?

Options: -width -height -file -background -toolbar -zoom-min -zoom-max

$iv load file                     load image (also seeds filelist from siblings)
$iv open                          tk_getOpenFile + load
$iv prev / $iv next               step through filelist (wraps)
$iv filelist ?list?               get/set navigation list
$iv fit                           zoom-fit to widget
$iv zoom1                         reset to 100 %
$iv zoom factor                   multiply current zoom
$iv pan dx dy                     shift displayed image
$iv info                          {file w h zoom}
$iv export filename               PDF/SVG/PS/EPS/PNG to file
$iv export -chan $ch -format fmt  stream to channel
$iv toolbar 0|1                   show/hide built-in toolbar at runtime
```

JPEG support works without `Img` — falls back to tclmcairo's libjpeg
binding via PPM. See `demos/demo-imageviewer.tcl` for keyboard shortcuts
and drag-and-drop integration.

## Demos

```bash
wish demos/demo-surface.tcl      # Shapes, Gradients, Text, Transparency, Animation
wish demos/demo-plot.tcl         # Line, Area, Scatter, Bar, Multi-Series
wish demos/demo-plot-y2.tcl      # Dual-scale chart (Y1 € + Y2 %)
wish demos/demo-imageviewer.tcl  # PNG/JPEG viewer with zoom, pan, export
wish demos/demo-svgview.tcl      # SVG viewer
wish demos/demo-pageview.tcl     # PDF page viewer
wish demos/demo-chan-export.tcl  # streaming export via -chan (3 patterns)
```

## Known Limitations (0.1.1)

- `tkmcairo::svgview` SVG renderer via svg2cairo lacks `<marker>`,
  `<use>`, gradient support — use `-renderer luna` for full SVG
- `tkmcairo::pageview` requires `pdfiumtcl` (private) or `poppler-utils`
  (`pdftoppm` + `pdfinfo`) on PATH for actual rendering
- `tkmcairo::imageviewer` keeps the original photo in RAM —
  not optimal for very large images; A3 photo bridge plus tclvips
  binding are roadmap items (0.3 / 0.4)
- Windows: requires MSYS2-built Cairo DLLs from a matching `tclmcairo`
  install (provided by tclmcairo's `build-win.bat`)

## Architecture

```
tkmcairo::surface
    ├── ttk::frame $w  +  ttk::label $w.lbl -image $photo
    ├── tclmcairo off-screen context → topng → Tk photo image
    └── Namespace ::tkmcairo::surface::S_$w

tkmcairo::plot
    ├── tkmcairo::surface (underlying widget)
    └── Namespace ::tkmcairo::plot::S_$w
```

Widget command trick (rename + interp alias):
```tcl
ttk::frame .s
rename .s ::tkmcairo::surface::_frame__s   ;# window survives rename
interp alias {} .s {} ::tkmcairo::surface::_cmd .s
```

For the deeper "why" — why `ttk::label` instead of `Tk Canvas`, which
Cairo backends are used and why, what the roadmap implies for layers
and the photo bridge — see `nogit/architektur-hintergrund.md`.

## Installation

### Linux

```bash
sudo make install              # → /usr/lib/tcltk/tkmcairo0.1.1/
make test                      # 75/75 expected
```

Adjust `INSTALL_DIR` and `TCLMCAIRO_DIR` in the Makefile if your
installation paths differ.

### Windows (BAWT)

tkmcairo is pure Tcl — no native code, no compilation. Installation is
just a copy. The supplied batch scripts use the BAWT default layout:

```cmd
install-win.bat 86             :: BAWT Tcl 8.6 default
install-win.bat 90             :: BAWT Tcl 9.0
install-win.bat 86 C:\MyTcl    :: custom Tcl install
```

`install-win.bat` copies `pkgIndex.tcl` plus all 11 `.tm` modules into
`<TCL_LIB>\tkmcairo0.1.1\` and checks for an existing `tclmcairo*`
install — tkmcairo needs `tclmcairo` 0.3.5 or newer (install that
first via its own `build-win.bat`).

Run tests after install:

```cmd
test-win.bat 86
```

Run a demo:

```cmd
demo-win.bat 86 imageviewer
demo-win.bat 86 plot-y2
demo-win.bat 86 chan-export
```

## License

BSD 2-Clause.

## Related

- [tclmcairo](https://github.com/gregnix/tclmcairo) — Cairo binding (C extension)
- [canvas2cairo](https://github.com/gregnix/tclmcairo) — Tk Canvas → Cairo export
