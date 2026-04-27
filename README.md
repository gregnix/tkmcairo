# tkmcairo

Cairo-based Tk widgets for high-quality rendering.

> **Status: 0.1.0 — Early Preview**  
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
| `tkmcairo::plot`    | **0.1 — available** | Chart widget (line, area, bar, scatter) |
| `tkmcairo::coords`  | planned 0.2 | Coordinate transform helpers |
| `tkmcairo::axis`    | planned 0.2 | Axis drawing helpers |
| `tkmcairo::viewport`| planned 0.2 | Scrollable/zoomable surface |
| `tkmcairo::scene`   | planned 0.2 | Retained-mode scene graph |
| `tkmcairo::widgets` | planned 0.2 | Cairo-rendered Tk widgets |

## Requirements

- Tcl/Tk 8.6+
- [tclmcairo](https://github.com/gregnix/tclmcairo) 0.3.3+
- `scrollutil_tile` (optional, for viewport in 0.2)

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
  $w export filename   save PNG / PDF / SVG / PS / EPS
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

$p series line    name -data {x y ...} -color {r g b} -width n -alpha a
                       -dash list -marker circle|none -markersize n
$p series area    name -data {x y ...} -color {r g b} -alpha a -width n
$p series scatter name -data {x y ...} -color {r g b} -markersize n
$p series bar     name -data {label val ...} -color {r g b} -alpha a

$p clear / $p redraw / $p export file
```

## Demos

```bash
wish demos/demo-surface.tcl      # Shapes, Gradients, Text, Transparency, Animation
wish demos/demo-plot.tcl         # Line, Area, Scatter, Bar, Multi-Series
wish demos/demo-imageviewer.tcl  # PNG/JPEG viewer with zoom, pan, export
```

## Known Limitations (0.1)

- No clipping in plot series — data points outside plot area are drawn
- No zoom/pan (planned for `tkmcairo::viewport` in 0.2)
- `text_extents` demo incomplete
- Windows: requires MSYS2 Cairo DLLs alongside `tclmcairo`

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

## License

BSD 2-Clause — see [`LICENSE`](LICENSE).

## Related

- [tclmcairo](https://github.com/gregnix/tclmcairo) — Cairo binding (C extension)
- [canvas2cairo](https://github.com/gregnix/tclmcairo) — Tk Canvas → Cairo export
