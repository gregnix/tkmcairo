#!/usr/bin/env wish
# demo-surface.tcl — tkmcairo::surface demonstration
#
# Shows tkmcairo::surface as a pure Cairo drawing widget.
# Demonstrates: gradients, text, shapes, transparency, export

package require Tk

set _dir [file dirname [file normalize [info script]]]
# tcl::tm::path add [file join $_dir .. tcl]
# tkmcairo/ subdir auto-discovered by tm system
tcl::tm::path add [file join $_dir .. tcl]
if {[info exists env(TCLMCAIRO_LIBDIR)]} {
    lappend auto_path $env(TCLMCAIRO_LIBDIR)
    tcl::tm::path add $env(TCLMCAIRO_LIBDIR)
}

package require tkmcairo::surface

wm title . "tkmcairo::surface Demo"
wm geometry . 700x500

# Toolbar
ttk::frame .tb
pack .tb -fill x -padx 4 -pady 4

ttk::label .tb.l -text "Demo:"
ttk::combobox .tb.demo -width 16 -state readonly \
    -values {Shapes Gradients Text Transparency Animation}
.tb.demo set Shapes
ttk::button .tb.show   -text "Show"       -command showDemo
ttk::button .tb.pdf    -text "Export PDF" -command {surfaceExport pdf}
ttk::button .tb.svg    -text "Export SVG" -command {surfaceExport svg}
ttk::button .tb.png    -text "Export PNG" -command {surfaceExport png}

foreach w {l demo show pdf svg png} { pack .tb.$w -side left -padx 3 }

proc surfaceExport {fmt} {
    set file [tk_getSaveFile         -defaultextension .$fmt         -filetypes [list             [list "[string toupper $fmt] Files" .$fmt]             {"All Files" *}]         -title "Export as [string toupper $fmt]"]
    if {$file eq ""} return
    .s export $file
    tk_messageBox -message "Exported:
$file" -title "Export" -type ok
}

# Surface widget
tkmcairo::surface .s \
    -width 680 -height 420 \
    -drawcommand {drawDemo $ctx $w $h}

pack .s -fill both -expand 1 -padx 4 -pady 4

# ============================================================
set currentDemo "Shapes"

proc showDemo {} {
    global currentDemo
    set currentDemo [.tb.demo get]
    .s redraw
}

proc drawDemo {ctx w h} {
    global currentDemo
    switch $currentDemo {
        Shapes       { drawShapes       $ctx $w $h }
        Gradients    { drawGradients    $ctx $w $h }
        Text         { drawText         $ctx $w $h }
        Transparency { drawTransparency $ctx $w $h }
        Animation    { drawAnimation    $ctx $w $h }
    }
}

# --- Shapes ---
proc drawShapes {ctx w h} {
    $ctx clear 0.12 0.12 0.18 1

    $ctx text [expr {$w/2.0}] 28 "Cairo Shapes — tkmcairo::surface" \
        -font "Sans Bold 16" -color {0.9 0.9 0.9} -anchor center

    # Rounded rect
    $ctx rect 30 60 180 120 \
        -fill {0.2 0.5 0.85 0.9} -stroke {0.5 0.8 1 1} \
        -width 2 -radius 12
    $ctx text 120 125 "rounded rect" \
        -font "Sans 10" -color {0.7 0.9 1} -anchor center

    # Circle
    $ctx circle 300 120 60 \
        -fill {0.85 0.35 0.15 0.9} -stroke {1 0.7 0.5 1} -width 2
    $ctx text 300 195 "circle" \
        -font "Sans 10" -color {1 0.7 0.5} -anchor center

    # Ellipse
    $ctx ellipse 500 120 100 55 \
        -fill {0.25 0.7 0.35 0.9} -stroke {0.6 1 0.6 1} -width 2
    $ctx text 500 185 "ellipse" \
        -font "Sans 10" -color {0.6 1 0.6} -anchor center

    # Polygon (star-ish)
    set pts {}
    for {set i 0} {$i < 8} {incr i} {
        set a [expr {$i * 3.14159 / 4.0 - 3.14159/8}]
        set r [expr {($i % 2 == 0) ? 60 : 30}]
        lappend pts \
            [expr {130 + cos($a)*$r}] \
            [expr {320 + sin($a)*$r}]
    }
    $ctx poly {*}$pts \
        -fill {0.85 0.75 0.1 0.9} -stroke {1 0.95 0.5 1} -width 2
    $ctx text 130 390 "polygon" \
        -font "Sans 10" -color {1 0.95 0.5} -anchor center

    # Arc
    $ctx arc 330 310 70 30 270 \
        -stroke {0.7 0.4 0.9 1} -width 4 -linecap round
    $ctx text 330 390 "arc" \
        -font "Sans 10" -color {0.7 0.4 0.9} -anchor center

    # SVG path (arrow)
    $ctx path "M 510 260 L 560 260 L 560 240 L 610 280 L 560 320 L 560 300 L 510 300 Z" \
        -fill {0.3 0.75 0.85 0.9} -stroke {0.5 0.9 1 1} -width 1.5
    $ctx text 560 340 "svg path" \
        -font "Sans 10" -color {0.5 0.9 1} -anchor center
}

# --- Gradients ---
proc drawGradients {ctx w h} {
    $ctx clear 0.08 0.08 0.12 1

    $ctx text [expr {$w/2.0}] 28 "Cairo Gradients" \
        -font "Sans Bold 16" -color {0.9 0.9 0.9} -anchor center

    # Linear horizontal
    $ctx gradient_linear hgrad 30 70 280 70 \
        [list {0 0.9 0.1 0.1 1} {0.5 0.9 0.8 0.1 1} {1 0.1 0.8 0.2 1}]
    $ctx rect 30 60 250 80 -fillname hgrad -radius 8
    $ctx text 155 155 "linear (3 stops)" -font "Sans 10" -color {0.8 0.8 0.8} -anchor center

    # Linear vertical
    $ctx gradient_linear vgrad 320 60 320 140 \
        [list {0 0.1 0.4 0.9 1} {1 0.6 0.1 0.8 1}]
    $ctx rect 320 60 250 80 -fillname vgrad -radius 8
    $ctx text 445 155 "linear vertical" -font "Sans 10" -color {0.8 0.8 0.8} -anchor center

    # Radial
    $ctx gradient_radial rgrad 155 280 20 \
        [list {0 1 1 1 1} {0.5 0.2 0.6 0.9 0.9} {1 0.05 0.05 0.15 1}]
    $ctx circle 155 280 110 -fillname rgrad
    $ctx text 155 400 "radial gradient" -font "Sans 10" -color {0.8 0.8 0.8} -anchor center

    # Radial with stroke
    $ctx gradient_radial rgrad2 445 280 15 \
        [list {0 1 0.9 0.2 1} {0.6 0.8 0.3 0.1 0.8} {1 0.1 0.2 0.4 0}]
    $ctx circle 445 280 110 -fillname rgrad2 \
        -stroke {0.6 0.6 0.8 0.5} -width 2
    $ctx text 445 400 "radial + alpha" -font "Sans 10" -color {0.8 0.8 0.8} -anchor center
}

# --- Text ---
proc drawText {ctx w h} {
    $ctx clear 0.98 0.98 1.0 1

    $ctx text [expr {$w/2.0}] 30 "Cairo Text — text_extents demo"         -font "Sans Bold 16" -color {0.1 0.1 0.35} -anchor center

    # --- Font samples ---
    set fonts   {"Sans 12"  "Sans Bold 14"  "Sans Italic 12"  "Serif 14"  "Monospace 12"}
    set labels  {"Sans 12"  "Sans Bold 14"  "Sans Italic 12"  "Serif 14"  "Monospace 12"}
    set y 58
    foreach f $fonts lbl $labels {
        $ctx text 40 $y "The quick brown fox jumps" -font $f -color {0.1 0.1 0.2}
        $ctx text [expr {$w - 30}] $y "← $lbl"             -font "Sans 9" -color {0.55 0.55 0.55} -anchor e
        incr y 32
    }

    # --- Separator ---
    set y [expr {$y + 6}]
    $ctx rect 30 $y [expr {$w - 60}] 1 -fill {0.75 0.78 0.88}
    incr y 14

    # --- text_extents demo ---
    $ctx text 40 [expr {$y + 4}] "text_extents — alle 9 Felder:"         -font "Sans Bold 11" -color {0.15 0.15 0.55}
    incr y 26

    set sample "tkmcairo"
    set font   "Sans Bold 28"
    set ext    [$ctx text_extents $sample -font $font]

    set tw   [dict get $ext width]
    set th   [dict get $ext height]
    set xb   [dict get $ext x_bearing]
    set yb   [dict get $ext y_bearing]
    set xa   [dict get $ext x_advance]
    set ya   [dict get $ext y_advance]
    set asc  [dict get $ext ascent]
    set desc [dict get $ext descent]
    set lh   [dict get $ext line_height]

    # Textposition: Baseline bei y+asc
    set tx  40
    set bly [expr {$y + $asc}]   ;# Baseline-Y

    # Hintergrundbox (Bounding-Box = x_bearing, y_bearing Offset)
    set bbx [expr {$tx + $xb}]
    set bby [expr {$bly + $yb}]
    $ctx rect $bbx $bby $tw $th         -fill {0.88 0.93 1.0 0.85} -stroke {0.5 0.65 0.9 0.8} -width 1

    # Ascent-Linie (oben, blau)
    set ascy [expr {$bly - $asc}]
    $ctx line [expr {$tx - 5}] $ascy [expr {$tx + $tw + 30}] $ascy         -color {0.2 0.5 0.9 0.6} -width 1 -dash {6 3}

    # Baseline (rot)
    $ctx line [expr {$tx - 5}] $bly [expr {$tx + $tw + 30}] $bly         -color {0.85 0.25 0.25 0.8} -width 1.5 -dash {4 3}

    # Descent line (green)
    set descy [expr {$bly + $desc}]
    $ctx line [expr {$tx - 5}] $descy [expr {$tx + $tw + 30}] $descy         -color {0.2 0.7 0.35 0.6} -width 1 -dash {6 3}

    # x_advance Pfeil
    set arx [expr {$tx + $xa}]
    $ctx line $tx [expr {$bly + $desc + 8}] $arx [expr {$bly + $desc + 8}]         -color {0.6 0.3 0.7 0.8} -width 1.5
    $ctx circle $arx [expr {$bly + $desc + 8}] 3 -fill {0.6 0.3 0.7 0.9}

    # Text zeichnen
    $ctx text $tx $bly $sample -font $font -color {0.1 0.1 0.35}

    # Beschriftungen rechts
    set rx [expr {$tx + $tw + 38}]
    set ry [expr {$ascy + 5}]
    set dy 14
    set labels [list         [format "ascent     = %.1f" $asc]  {0.2 0.5 0.9}         [format "baseline   (y = %.0f)" $bly] {0.85 0.25 0.25}         [format "descent    = %.1f" $desc] {0.2 0.7 0.35}         [format "width      = %.1f" $tw]   {0.3 0.3 0.3}         [format "height     = %.1f" $th]   {0.3 0.3 0.3}         [format "x_bearing  = %.1f" $xb]   {0.3 0.3 0.3}         [format "x_advance  = %.1f" $xa]   {0.6 0.3 0.7}         [format "line_height= %.1f" $lh]   {0.3 0.3 0.3} ]

    foreach {lbl col} $labels {
        $ctx text $rx $ry $lbl             -font "Monospace 10" -color $col -anchor w
        incr ry $dy
    }
}

# --- Transparency ---
proc drawTransparency {ctx w h} {
    $ctx clear 0.15 0.15 0.2 1

    $ctx text [expr {$w/2.0}] 28 "Cairo Alpha / Transparency" \
        -font "Sans Bold 16" -color {0.9 0.9 0.9} -anchor center

    # Background pattern
    for {set i 0} {$i < 20} {incr i} {
        set x [expr {$i * 40}]
        $ctx line $x 50 $x $h -color {0.3 0.3 0.35 0.4} -width 0.5
    }

    # Overlapping circles with transparency
    set cx [expr {$w/2.0}]
    set cy [expr {$h/2.0 + 20}]
    set r  90

    foreach {dx dy col} {
        -70 -40 {0.9 0.2 0.2}
         70 -40 {0.2 0.8 0.2}
          0  60 {0.2 0.2 0.9}
    } {
        $ctx circle [expr {$cx+$dx}] [expr {$cy+$dy}] $r \
            -fill [list {*}$col 0.45] \
            -stroke [list {*}$col 0.9] -width 1.5
    }
    $ctx text $cx [expr {$cy+155}] "Overlapping circles α=0.45" \
        -font "Sans 11" -color {0.8 0.8 0.8} -anchor center
}

# --- Animation (redraw counter) ---
set anim_t 0
proc drawAnimation {ctx w h} {
    global anim_t
    set t [expr {$anim_t * 0.05}]

    $ctx clear 0.05 0.05 0.1 1

    $ctx text [expr {$w/2.0}] 28 "Animation via redraw" \
        -font "Sans Bold 16" -color {0.9 0.9 0.9} -anchor center

    set cx [expr {$w/2.0}]
    set cy [expr {$h/2.0 + 20}]

    for {set i 0} {$i < 12} {incr i} {
        set a  [expr {$i * 3.14159 / 6.0 + $t}]
        set r  [expr {80 + sin($t * 2 + $i) * 30}]
        set px [expr {$cx + cos($a) * $r}]
        set py [expr {$cy + sin($a) * $r}]
        set rc [expr {8 + abs(sin($t + $i)) * 12}]
        set col [list \
            [expr {(sin($t+$i*0.5)+1)/2.0}] \
            [expr {(cos($t*1.3+$i*0.4)+1)/2.0}] \
            [expr {(sin($t*0.7-$i*0.3)+1)/2.0}] \
            0.85]
        $ctx circle $px $py $rc -fill $col
    }

    $ctx text $cx [expr {$h - 20}] \
        "Frame $anim_t — click 'Show' to advance" \
        -font "Sans 10" -color {0.6 0.6 0.7} -anchor center

    incr anim_t
    after 50 {.s redraw}
}

# Start
showDemo
