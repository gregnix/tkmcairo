# tkmcairo — Concept and Architectural Vision

Status: 2026-04-12

---

## Goal

tkmcairo is **not** a Canvas extension and not a Canvas clone.
It is a Cairo-based rendering platform for Tk — with two layers:

1. **Rendering building blocks** — reusable helpers for coordinates,
   axes, legend, data
2. **Ready-made widgets** — surface, plot, viewport, scene

Third parties can build their own chart types or visualizations
without knowing Cairo internals — they just use the building blocks.

---

## Architecture overview

```
Application / custom algorithms
        |
tkmcairo::plot          ready-made charts (line, area, bar, scatter, pie ...)
        |
tkmcairo::helpers       rendering building blocks (coords, axis, legend, data)
        |
tkmcairo::surface       Cairo drawing surface as a Tk widget
        |
tclmcairo               low-level Cairo binding (C extension)
        |
Cairo 1.18+             2D vector graphics
```

---

## Module structure (current + planned)

```
tcl/tkmcairo/
  surface-0.1.tm     (0.1) ← core widget: ttk::label + tclmcairo
  plot-0.1.tm        (0.1) ← ready-made charts: line, area, scatter, bar

  coords-0.1.tm      (0.2) ← coordinate transform
  axis-0.1.tm        (0.2) ← axis drawing (X, Y, time)
  legend-0.1.tm      (0.2) ← legend
  data-0.1.tm        (0.2) ← data helpers

  viewport-0.1.tm    (0.2) ← scrollable / zoomable surface
  scene-0.1.tm       (0.2) ← retained-mode scene graph
  widgets-0.1.tm     (0.2) ← Cairo-rendered Tk widgets

  pageview-0.1.tm    (0.3) ← PDF page display
```

---

## Rendering building blocks (helpers) — detailed plan

### tkmcairo::coords

Coordinate transform between data world and Cairo pixels.
The basis for every chart type.

```tcl
# Create a transform object
set tr [tkmcairo::coords::transform new \
    -xmin 0 -xmax 12 -ymin -15 -ymax 45 \
    -px0 60 -py0 40 -px1 580 -py1 360]

# Convert coordinates
set px [$tr toPixelX 6.5]
set py [$tr toPixelY 22.3]
lassign [$tr toPixel 6.5 22.3] px py
lassign [$tr toWorld $px $py] xv yv

# Pan + Zoom
$tr zoom  1.5 $cx $cy   ;# zoom around a centre point
$tr pan   20  -10        ;# shift in pixels
$tr reset               ;# back to origin

# Queries
lassign [$tr worldBounds] xmin xmax ymin ymax
lassign [$tr pixelBounds] px0 py0 px1 py1
```

### tkmcairo::axis

Draws axes with Cairo. Uses a coords transform internally.

```tcl
tkmcairo::axis::drawX $ctx $tr \
    -label "Month" \
    -format "%.0f" \
    -ticks 12 \
    -grid 1 \
    -gridcolor {0.88 0.88 0.88} \
    -ticklen 5 \
    -font "Sans 10"

tkmcairo::axis::drawY $ctx $tr \
    -label "°C" \
    -format "%.1f" \
    -ticks 5 \
    -grid 1

# Time axis (date / time)
tkmcairo::axis::drawTimeX $ctx $tr \
    -start "2026-01-01" \
    -end   "2026-12-31" \
    -format "%b" \
    -ticks monthly

# Secondary Y axis on the right
tkmcairo::axis::drawY2 $ctx $tr2 -label "%" -color {0.8 0.3 0.2}
```

### tkmcairo::legend

Draw a legend.

```tcl
tkmcairo::legend::draw $ctx $series \
    -position ne \
    -font "Sans 10" \
    -background {1 1 1 0.85} \
    -border {0.7 0.7 0.7}
```

### tkmcairo::data

Data helpers.

```tcl
# Value range from a data list
lassign [tkmcairo::data::range $xydata] xmin xmax ymin ymax

# Timestamp → numeric value
set t [tkmcairo::data::timeToNum "2026-06-15"]

# Smoothing (moving average)
set smooth [tkmcairo::data::smooth $xydata 3]

# Boxplot statistics
lassign [tkmcairo::data::boxstats $values] q0 q1 median q3 q4

# Histogram aggregation
set bins [tkmcairo::data::histogram $values -bins 10 -min 0 -max 100]
```

---

## Building your own chart types

To build a new chart type (e.g. boxplot, Gantt, radar) you only need
the building blocks — no Cairo knowledge required:

```tcl
package require tkmcairo::surface
package require tkmcairo::coords
package require tkmcairo::axis
package require tkmcairo::legend

tkmcairo::surface .p -width 600 -height 400 \
    -drawcommand {drawBoxplot $ctx $w $h $mydata}

proc drawBoxplot {ctx w h data} {
    # 1. Coordinate transform
    set tr [tkmcairo::coords::transform new \
        -xmin 0 -xmax [llength $data] \
        -ymin 0 -ymax 100 \
        -px0 60 -py0 20 -px1 [expr {$w-20}] -py1 [expr {$h-40}]]

    # 2. Axes
    tkmcairo::axis::drawX $ctx $tr -ticks [llength $data]
    tkmcairo::axis::drawY $ctx $tr -grid 1

    # 3. Custom algorithm — only Cairo from here on
    set i 0
    foreach {lbl values} $data {
        lassign [tkmcairo::data::boxstats $values] q0 q1 med q3 q4
        set px [$tr toPixelX $i]
        # ... draw with Cairo ...
        incr i
    }
}
```

---

## Widget hierarchy

```
tkmcairo::surface          core widget (done)
    |
    ├── tkmcairo::plot      ready-made charts (done, growing)
    |
    ├── tkmcairo::viewport  scrollbars + zoom/pan (0.2)
    |       |
    |       └── tkmcairo::pageview  PDF display (0.3)
    |
    └── tkmcairo::scene     retained-mode scene graph (0.2)
            |
            └── tkmcairo::widgets  Cairo widgets (0.2)
```

---

## Scope and relationships

| Project | Purpose | Relationship |
|---------|---------|--------------|
| tkpath | Cairo Canvas extension | needs a display, different goal |
| tclmcairo | Cairo C binding | foundation of tkmcairo |
| BLT | chart widgets | no export, no antialiasing |

---

## Core principles

**Composability** — small modules that build on each other.
Nobody has to import everything.

**Tk philosophy** — widget paths, geometry-manager-compatible,
no separate event loop.

**Drawcommand pattern** — the same script for screen and export.
`$ctx $w $h` as parameters — easy to extend.

**Cairo quality** — antialiasing, gradients, alpha, vector export.
This is the main advantage over Canvas-based solutions.
