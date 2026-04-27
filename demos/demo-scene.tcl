#!/usr/bin/env wish
# demo-scene.tcl — tkmcairo::scene Demo
#
# Zeigt: Items hinzufügen, bewegen, löschen, Bindings, Z-Order

package require Tk

set _dir [file dirname [file normalize [info script]]]
tcl::tm::path add [file join $_dir .. tcl]
if {[info exists env(TCLMCAIRO_LIBDIR)]} {
    lappend auto_path $env(TCLMCAIRO_LIBDIR)
    tcl::tm::path add $env(TCLMCAIRO_LIBDIR)
}

package require tkmcairo::surface
package require tkmcairo::scene

wm title . "tkmcairo::scene Demo"
wm geometry . 800x560

# Toolbar
ttk::frame .tb
pack .tb -fill x -padx 4 -pady 4

ttk::button .tb.add   -text "Add Shape"  -command sceneAddRandom
ttk::button .tb.del   -text "Delete Last" -command sceneDeleteLast
ttk::button .tb.raise -text "Raise"       -command sceneRaiseSelected
ttk::button .tb.anim  -text "Animate"     -command sceneAnimate
ttk::label  .tb.info  -textvariable ::sceneInfo -anchor w
foreach w {add del raise anim info} { pack .tb.$w -side left -padx 3 }

# Surface + Scene
tkmcairo::surface .s \
    -width 780 -height 480 \
    -background {0.12 0.12 0.18}

pack .s -fill both -expand 1 -padx 4 -pady 4

set scene [tkmcairo::scene::new .s -background {0.12 0.12 0.18}]

# ============================================================
# Initiales Layout
# ============================================================

# Hintergrund-Rects
$scene add rect 20 20 380 220 \
    -fill {0.18 0.22 0.32} -stroke {0.35 0.45 0.65} -width 1.5 -radius 8
$scene add rect 400 20 760 220 \
    -fill {0.22 0.18 0.28} -stroke {0.55 0.35 0.65} -width 1.5 -radius 8
$scene add rect 20 240 760 460 \
    -fill {0.15 0.22 0.18} -stroke {0.35 0.55 0.45} -width 1.5 -radius 8

# Labels
$scene add text 200 40 0 0 -text "Shapes" \
    -font "Sans Bold 13" -stroke {0.7 0.8 1.0} -anchor center
$scene add text 580 40 0 0 -text "Gradients (via surface)" \
    -font "Sans Bold 13" -stroke {0.8 0.7 1.0} -anchor center
$scene add text 390 260 0 0 -text "Interactive Items — click to raise" \
    -font "Sans Bold 13" -stroke {0.7 1.0 0.8} -anchor center

# Shapes
$scene add circle 100 130 60 \
    -fill {0.9 0.5 0.2 0.85} -stroke {1.0 0.7 0.3} -width 2
$scene add text 100 130 0 0 -text "circle" \
    -font "Sans 10" -stroke {1 1 1} -anchor center

$scene add rect 180 80 340 190 \
    -fill {0.2 0.6 0.9 0.8} -stroke {0.4 0.8 1.0} -width 2 -radius 10
$scene add text 260 135 0 0 -text "rect" \
    -font "Sans 10" -stroke {1 1 1} -anchor center

$scene add oval 450 70 700 190 \
    -fill {0.6 0.3 0.8 0.8} -stroke {0.8 0.5 1.0} -width 2
$scene add text 575 130 0 0 -text "oval" \
    -font "Sans 10" -stroke {1 1 1} -anchor center

# Interactive Items
set colors [list \
    {0.9 0.3 0.3} {0.3 0.7 0.9} {0.9 0.8 0.2} \
    {0.3 0.9 0.5} {0.8 0.3 0.9} {0.9 0.6 0.2}]

set ::selectedItem ""
set ::sceneInfo "Klick auf Item zum Auswählen"

for {set i 0} {$i < 6} {incr i} {
    set col [lindex $colors $i]
    set x [expr {60 + $i * 120}]
    set y 340
    set iid [$scene add rect [expr {$x-45}] [expr {$y-45}] \
                              [expr {$x+45}] [expr {$y+45}] \
        -fill $col -stroke {1 1 1 0.5} -width 1 -radius 6]

    $scene add text $x $y 0 0 -text "Item $i" \
        -font "Sans 10" -stroke {1 1 1} -anchor center

    # Binding
    $scene bind $iid button "sceneSelect $iid"
}

# ============================================================
# Interaktion
# ============================================================
proc sceneSelect {iid} {
    global scene sceneInfo selectedItem
    set selectedItem $iid
    set sceneInfo "Ausgewählt: Item $iid"
    $scene raise $iid
    $scene render
}

proc sceneRaiseSelected {} {
    global scene sceneInfo selectedItem
    if {$selectedItem eq ""} {
        set sceneInfo "Kein Item ausgewählt"
        return
    }
    $scene raise $selectedItem
    $scene forcerender
}

proc sceneAddRandom {} {
    global scene
    set x [expr {int(rand() * 700 + 30)}]
    set y [expr {int(rand() * 400 + 30)}]
    set r [expr {20 + int(rand() * 40)}]
    set col [list [expr {rand()}] [expr {rand()}] [expr {rand()}] 0.85]
    set iid [$scene add circle [expr {$x-$r}] [expr {$y-$r}] \
                                [expr {$x+$r}] [expr {$y+$r}] \
        -fill $col -stroke {1 1 1 0.5} -width 1]
    $scene bind $iid button "sceneSelect $iid"
    $scene render
}

proc sceneDeleteLast {} {
    global scene
    set items [$scene items]
    if {[llength $items] == 0} return
    $scene delete [lindex $items end]
    $scene render
}

set ::animating 0
proc sceneAnimate {} {
    global scene animating
    set animating [expr {!$animating}]
    if {$animating} {
        .tb.anim configure -text "Stop"
        sceneAnimStep
    } else {
        .tb.anim configure -text "Animate"
    }
}

set ::animAngle 0
proc sceneAnimStep {} {
    global scene animating animAngle
    if {!$animating} return
    set animAngle [expr {$animAngle + 0.05}]
    set items [$scene items]
    # Ersten 3 interaktiven Items animieren
    foreach iid [lrange $items 10 15] {
        if {![catch {$scene bbox $iid} bb]} {
            lassign $bb x1 y1 x2 y2
            set cx [expr {($x1+$x2)/2.0}]
            set cy [expr {($y1+$y2)/2.0}]
            set r  [expr {($x2-$x1)/2.0}]
            # Pulsieren
            set nr [expr {$r + sin($animAngle + $iid * 0.5) * 5}]
            $scene coords $iid \
                [expr {$cx-$nr}] [expr {$cy-$nr}] \
                [expr {$cx+$nr}] [expr {$cy+$nr}]
        }
    }
    $scene forcerender
    after 30 sceneAnimStep
}

# Initial render
$scene render
