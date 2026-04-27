# tkmcairo::coords 0.1
#
# Coordinate transform between data world and Cairo pixels.
# Building block for tkmcairo::plot, tkmcairo::axis, tkmcairo::viewport.
#
# API:
#   set tr [tkmcairo::coords::transform new ?options?]
#
#   Options:
#     -xmin -xmax -ymin -ymax     data-world bounds
#     -px0 -py0 -px1 -py1         pixel bounds (plot area)
#     -flipy  0|1                 invert Y axis (default 1, top = max)
#
#   Methods:
#     $tr toPixelX  xval          -> pixel X
#     $tr toPixelY  yval          -> pixel Y
#     $tr toPixel   xval yval     -> {px py}
#     $tr toWorldX  px            -> data X
#     $tr toWorldY  py            -> data Y
#     $tr toWorld   px py         -> {xval yval}
#
#     $tr configure ?opts?        -> update (recompute)
#     $tr cget option             -> read a value
#     $tr bounds                  -> {xmin xmax ymin ymax px0 py0 px1 py1}
#     $tr pixelBounds             -> {px0 py0 px1 py1}
#     $tr worldBounds             -> {xmin xmax ymin ymax}
#     $tr plotW                   -> pixel width of the plot area
#     $tr plotH                   -> pixel height of the plot area
#
#     $tr zoom  factor cx cy      -> zoom around a pixel centre
#     $tr pan   dpx dpy           -> shift in pixels
#     $tr reset                   -> restore the original bounds
#
#     $tr destroy
#
# Part of tkmcairo — https://github.com/gregnix/tkmcairo
# License: BSD 2-Clause

package provide tkmcairo::coords 0.1

namespace eval ::tkmcairo::coords {}

# ============================================================
# Constructor
# ============================================================
proc ::tkmcairo::coords::transform {subcmd args} {
    if {$subcmd ne "new"} {
        error "usage: tkmcairo::coords::transform new ?options?"
    }

    # Defaults
    array set opts {
        -xmin 0   -xmax 100
        -ymin 0   -ymax 100
        -px0  0   -py0  0
        -px1  400 -py1  300
        -flipy 1
    }
    foreach {k v} $args { set opts($k) $v }

    # Unique name
    variable _count
    if {![info exists _count]} { set _count 0 }
    set id "::tkmcairo::coords::T[incr _count]"

    namespace eval $id {
        variable opts
        variable orig   ;# original bounds for reset
    }

    array set ${id}::opts [array get opts]
    array set ${id}::orig [array get opts]

    # OO-style command: calls forwarded to _cmd
    interp alias {} $id {} ::tkmcairo::coords::_cmd $id

    return $id
}

# ============================================================
# Dispatcher
# ============================================================
proc ::tkmcairo::coords::_cmd {id subcmd args} {
    switch -- $subcmd {
        toPixelX    { _toPixelX $id [lindex $args 0] }
        toPixelY    { _toPixelY $id [lindex $args 0] }
        toPixel     { list [_toPixelX $id [lindex $args 0]] \
                           [_toPixelY $id [lindex $args 1]] }
        toWorldX    { _toWorldX $id [lindex $args 0] }
        toWorldY    { _toWorldY $id [lindex $args 0] }
        toWorld     { list [_toWorldX $id [lindex $args 0]] \
                           [_toWorldY $id [lindex $args 1]] }
        configure   { _configure $id {*}$args }
        cget        { set ${id}::opts([lindex $args 0]) }
        bounds      {
            array set o [array get ${id}::opts]
            list $o(-xmin) $o(-xmax) $o(-ymin) $o(-ymax) \
                 $o(-px0)  $o(-py0)  $o(-px1)  $o(-py1)
        }
        pixelBounds {
            array set o [array get ${id}::opts]
            list $o(-px0) $o(-py0) $o(-px1) $o(-py1)
        }
        worldBounds {
            array set o [array get ${id}::opts]
            list $o(-xmin) $o(-xmax) $o(-ymin) $o(-ymax)
        }
        plotW {
            array set o [array get ${id}::opts]
            expr {$o(-px1) - $o(-px0)}
        }
        plotH {
            array set o [array get ${id}::opts]
            expr {$o(-py1) - $o(-py0)}
        }
        zoom        { _zoom $id [lindex $args 0] [lindex $args 1] [lindex $args 2] }
        pan         { _pan  $id [lindex $args 0] [lindex $args 1] }
        reset       { array set ${id}::opts [array get ${id}::orig] }
        destroy     {
            rename $id {}
            namespace delete $id
        }
        default     { error "tkmcairo::coords: unknown subcommand: $subcmd" }
    }
}

# ============================================================
# Kern-Transformationen
# ============================================================
proc ::tkmcairo::coords::_toPixelX {id xval} {
    array set o [array get ${id}::opts]
    set xrange [expr {$o(-xmax) - $o(-xmin)}]
    if {$xrange == 0} { return $o(-px0) }
    expr {$o(-px0) + ($xval - $o(-xmin)) / double($xrange) * ($o(-px1) - $o(-px0))}
}

proc ::tkmcairo::coords::_toPixelY {id yval} {
    array set o [array get ${id}::opts]
    set yrange [expr {$o(-ymax) - $o(-ymin)}]
    if {$yrange == 0} { return $o(-py0) }
    if {$o(-flipy)} {
        # Y axis inverted: higher values on top (Cairo: y=0 is top)
        expr {$o(-py1) - ($yval - $o(-ymin)) / double($yrange) * ($o(-py1) - $o(-py0))}
    } else {
        expr {$o(-py0) + ($yval - $o(-ymin)) / double($yrange) * ($o(-py1) - $o(-py0))}
    }
}

proc ::tkmcairo::coords::_toWorldX {id px} {
    array set o [array get ${id}::opts]
    set prange [expr {$o(-px1) - $o(-px0)}]
    if {$prange == 0} { return $o(-xmin) }
    expr {$o(-xmin) + ($px - $o(-px0)) / double($prange) * ($o(-xmax) - $o(-xmin))}
}

proc ::tkmcairo::coords::_toWorldY {id py} {
    array set o [array get ${id}::opts]
    set prange [expr {$o(-py1) - $o(-py0)}]
    if {$prange == 0} { return $o(-ymin) }
    if {$o(-flipy)} {
        expr {$o(-ymin) + ($o(-py1) - $py) / double($prange) * ($o(-ymax) - $o(-ymin))}
    } else {
        expr {$o(-ymin) + ($py - $o(-py0)) / double($prange) * ($o(-ymax) - $o(-ymin))}
    }
}

# ============================================================
# Configure
# ============================================================
proc ::tkmcairo::coords::_configure {id args} {
    foreach {k v} $args {
        set ${id}::opts($k) $v
    }
}

# ============================================================
# Zoom um Pixel-Mittelpunkt
# ============================================================
proc ::tkmcairo::coords::_zoom {id factor cx cy} {
    array set o [array get ${id}::opts]
    # Pixel-Mittelpunkt → Weltkoordinaten
    set wx [_toWorldX $id $cx]
    set wy [_toWorldY $id $cy]
    # Weltgrenzen um diesen Punkt skalieren
    set xrange [expr {($o(-xmax) - $o(-xmin)) / $factor}]
    set yrange [expr {($o(-ymax) - $o(-ymin)) / $factor}]
    # Anteil des Mittelpunkts in der alten Range
    set xfrac [expr {($wx - $o(-xmin)) / ($o(-xmax) - $o(-xmin))}]
    set yfrac [expr {($wy - $o(-ymin)) / ($o(-ymax) - $o(-ymin))}]

    set ${id}::opts(-xmin) [expr {$wx - $xfrac * $xrange}]
    set ${id}::opts(-xmax) [expr {$wx + (1 - $xfrac) * $xrange}]
    set ${id}::opts(-ymin) [expr {$wy - $yfrac * $yrange}]
    set ${id}::opts(-ymax) [expr {$wy + (1 - $yfrac) * $yrange}]
}

# ============================================================
# Pan: Verschiebung in Pixel
# ============================================================
proc ::tkmcairo::coords::_pan {id dpx dpy} {
    array set o [array get ${id}::opts]
    set pW [expr {$o(-px1) - $o(-px0)}]
    set pH [expr {$o(-py1) - $o(-py0)}]
    if {$pW == 0 || $pH == 0} return

    set dxw [expr {$dpx / double($pW) * ($o(-xmax) - $o(-xmin))}]
    set dyw [expr {$dpy / double($pH) * ($o(-ymax) - $o(-ymin))}]

    if {$o(-flipy)} { set dyw [expr {-$dyw}] }

    set ${id}::opts(-xmin) [expr {$o(-xmin) - $dxw}]
    set ${id}::opts(-xmax) [expr {$o(-xmax) - $dxw}]
    set ${id}::opts(-ymin) [expr {$o(-ymin) - $dyw}]
    set ${id}::opts(-ymax) [expr {$o(-ymax) - $dyw}]
}
