# tkmcairo — Technical Documentation

Status: 2026-04-12 | Version: 0.1.0

---

## Architecture overview

```
Tk application
      |
tkmcairo::surface     (ttk::frame + ttk::label + Tk photo image)
      |
tclmcairo             (off-screen Cairo context)
      |
Cairo                 (2D vector graphics, C library)
      |
     topng → PNG bytes → Tk photo image → ttk::label
```

---

## tkmcairo::surface — implementation

### Widget command trick: rename + interp alias

Tk destroys a window when its Tcl command is deleted.
`interp alias {} .w {} handler` first deletes the existing command,
which destroys the window.

**Correct order:**
```tcl
ttk::frame $w
# 1. First rename — the command moves, the window stays
rename $w ::tkmcairo::surface::_frame_[string map {. _ : _} $w]
# 2. Then alias — $w no longer exists as a command, so nothing is deleted
interp alias {} $w {} ::tkmcairo::surface::_cmd $w
```

The internal frame command is stored in `_frameCmd($w)` so the
`default` branch of `_cmd` can forward to it.

### Namespace convention

State namespace: `::tkmcairo::surface::S_$w`

The `S_` prefix is required because the widget path contains a dot:
`.s` → `S_.s`. Namespace names that start with a dot would be problematic.

```tcl
namespace eval ::tkmcairo::surface::S_$w {
    variable ctx      ""   ;# tclmcairo context object
    variable photo    ""   ;# Tk photo image name
    variable width    0    ;# current width
    variable height   0    ;# current height
    variable pending  0    ;# debounce flag
    variable opts          ;# option array
}
```

### Drawcommand convention

Surface sets three global variables and then evaluates the script:

```tcl
uplevel #0 [list set ctx $ctx]   ;# tclmcairo context object
uplevel #0 [list set w   $pw]    ;# width in pixels
uplevel #0 [list set h   $ph]    ;# height in pixels
catch {uplevel #0 $cmd}
```

**Script style (for end users):**
```tcl
-drawcommand {myDraw $ctx $w $h}

proc myDraw {ctx w h} {
    $ctx clear 1 1 1 1
    $ctx circle [expr {$w/2.0}] [expr {$h/2.0}] 50 -fill {0.2 0.5 0.9}
}
```

**Proc-reference style (for internal use, e.g. plot):**
```tcl
-drawcommand [list ::mypkg::_drawentry .w]

proc ::mypkg::_drawentry {self} {
    global ctx w h   ;# set as globals by surface
    ::mypkg::_draw $self $ctx $w $h
}
```

Both styles work because `uplevel #0` evaluates in the global context,
where `$ctx`, `$w`, `$h` are accessible.

### Resize debounce

`<Configure>` fires for every pixel during a resize. 30 ms debounce:

```tcl
proc ::tkmcairo::surface::_onConfigure {w nw nh} {
    ...
    if {[set ${ns}::pending]} return
    set ${ns}::pending 1
    after 30 [list catch [list ::tkmcairo::surface::_redraw $w]]
}
```

### Context lifecycle

For each redraw:
1. Destroy the previous context (if any)
2. Create a new context: `tclmcairo::new $pw $ph`
3. Fill the background
4. Evaluate the drawcommand
5. `$ctx topng` → PNG bytes
6. `$photo put $pngdata -format png`

The context is kept in `${ns}::ctx` for `$w ctx` queries.
**Important:** always call `$ctx destroy`. `MAX_CTX = 256`.

### PNG export

`$ctx save $file` is not implemented for raster contexts.
Correct approach:

```tcl
set fh [open $file wb]
fconfigure $fh -translation binary
puts -nonewline $fh [$ctx topng]
close $fh
```

### Vector export (PDF/SVG/PS/EPS)

A new vector context, then re-run the drawcommand:

```tcl
set ctx [tclmcairo::new $pw $ph -mode pdf -file $file]
# ... background + drawcommand ...
catch {$ctx finish}
catch {$ctx destroy}
```

---

## tkmcairo::plot — implementation

### Layering: plot on top of surface

`plot` internally creates a `tkmcairo::surface` under the same widget
path `$w`. The surface installs its command at `$w` via
`rename` + `interp alias`. `plot` then overwrites that alias:

```tcl
tkmcairo::surface $w ...      ;# installs alias .p → surface::_cmd
interp alias {} $w {} ::tkmcairo::plot::_cmd $w  ;# overwrites
```

Because surface has already run `rename`, the second `interp alias`
call only deletes the surface alias — the Tk window survives.

### _cmd must never call $w

`$w` is the alias to `_cmd` itself, so `$w subcmd` would recurse
infinitely. All forwarding goes directly to internal procs:

```tcl
# WRONG — recursive:
redraw { $w redraw }

# RIGHT — direct proc calls:
redraw { ::tkmcairo::surface::_redraw $w }
export { ::tkmcairo::surface::_export $w {*}$args }
default { ::tkmcairo::surface::_cmd $w $subcmd {*}$args }
```

### Drawcommand bridge

`plot` registers a proc reference with surface:
```tcl
-drawcommand [list ::tkmcairo::plot::_drawentry $w]
```

`_drawentry` reads the globals set by surface:
```tcl
proc ::tkmcairo::plot::_drawentry {plotw} {
    global ctx w h
    ::tkmcairo::plot::_draw $plotw $ctx $w $h
}
```

### Coordinate transform

`apply` lambdas with explicit parameters (no closure issues):

```tcl
set toX [list apply [list {v px0 xmin xscale} {
    expr {$px0 + ($v - $xmin) * $xscale}
}]]
set px [{*}$toX $xval $px0 $xmin $xscale]
```

**Why not plain procs?**
Plain procs have no closure over local variables.
```tcl
# WRONG — $px0 is undefined at call time:
proc _X {v} [list expr "\$px0 + (\$v - $xmin) * $xscale"]
```

### Clipping — known limitation

`$ctx rect x y w h -fill ...` fills and then clears the path.
A subsequent `$ctx clip` clips on an empty path, so every following
draw call is invisible.

→ clipping is disabled in series procs. Data points outside the plot
area are drawn. Fix planned for 0.2.

---

## Known limitations (0.1)

| Issue | Cause | Fix |
|-------|-------|-----|
| No clipping in plot series | Cairo rect clears the path | 0.2 |
| `text_extents` demo incomplete | ctx object not OO-transparent | 0.2 |
| No zoom/pan | no viewport widget | 0.2 |

---

## File layout

```
tkmcairo/
├── README.md
├── CHANGELOG.md
├── docs/
│   ├── tkmcairo-technical.md    ← this document
│   ├── tkmcairo-concept.md      ← architectural vision
│   └── tkmcairo-roadmap.md      ← version planning
├── nogit/
│   ├── TODO.md
│   ├── ROADMAP.md
│   └── uebergabe-0.1.md
├── tcl/tkmcairo/
│   ├── surface-0.1.tm           ← core widget
│   └── plot-0.1.tm              ← chart widget
└── demos/
    ├── demo-surface.tcl
    ├── demo-plot.tcl
    └── demo-imageviewer.tcl
```
