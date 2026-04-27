#!/usr/bin/env wish
# demo-viewport.tcl — tkmcairo::viewport Demo
#
# Zeigt: Zoom (Mausrad), Pan (Mitteltaste), Zoom-Buttons, Export
# Drawcommand erhält zusätzlich $zoom als Variable

package require Tk

set _dir [file dirname [file normalize [info script]]]
tcl::tm::path add [file join $_dir .. tcl]
if {[info exists env(TCLMCAIRO_LIBDIR)]} {
    lappend auto_path $env(TCLMCAIRO_LIBDIR)
    tcl::tm::path add $env(TCLMCAIRO_LIBDIR)
}

package require tkmcairo::viewport

wm title . "tkmcairo::viewport Demo"
wm geometry . 900x620

# Toolbar
ttk::frame .tb
pack .tb -fill x -padx 4 -pady 4

ttk::button .tb.fit  -text "Fit"       -command {.vp zoomfit}
ttk::button .tb.z1   -text "1:1"       -command {.vp zoom1}
ttk::button .tb.zin  -text "Zoom +"    -command {.vp zoom 1.25}
ttk::button .tb.zout -text "Zoom −"    -command {.vp zoom 0.8}
ttk::separator .tb.s1 -orient vertical
ttk::label .tb.zl    -text "Zoom:"
ttk::label .tb.zv    -textvariable ::zoomLabel -width 6
ttk::separator .tb.s2 -orient vertical
ttk::button .tb.epdf -text "Export PDF" -command {vpExport pdf}
ttk::button .tb.esvg -text "Export SVG" -command {vpExport svg}
ttk::button .tb.epng -text "Export PNG" -command {vpExport png}

foreach w {fit z1 zin zout s1 zl zv s2 epdf esvg epng} {
    pack .tb.$w -side left -padx 2 -pady 2
}

# Viewport
tkmcairo::viewport .vp \
    -width       860 \
    -height      540 \
    -worldwidth  1200 \
    -worldheight 900 \
    -background  {0.95 0.95 0.98} \
    -drawcommand {drawWorld $ctx $w $h}

pack .vp -fill both -expand 1 -padx 4 -pady 4

# Status
ttk::label .status -text "Mausrad = Zoom | Mitteltaste = Pan" -anchor w
pack .status -fill x -padx 6

# Zoom-Label aktualisieren
proc updateZoomLabel {} {
    global zoomLabel
    set zoomLabel [format "%.0f%%" [expr {[.vp zoomlevel] * 100}]]
    after 200 updateZoomLabel
}
after 100 updateZoomLabel

# ============================================================
# Draw-Proc — zeichnet in Weltkoordinaten 0..1200 x 0..900
# ============================================================
proc drawWorld {ctx w h} {
    # Weltkoordinaten: 1200 x 900

    # Hintergrund-Grid
    for {set x 0} {$x <= 1200} {incr x 100} {
        $ctx line $x 0 $x 900 -color {0.8 0.82 0.88 0.6} -width 0.5
    }
    for {set y 0} {$y <= 900} {incr y 100} {
        $ctx line 0 $y 1200 $y -color {0.8 0.82 0.88 0.6} -width 0.5
    }

    # Weltrahmen
    $ctx rect 0 0 1200 900 -stroke {0.5 0.5 0.7} -width 1.5

    # Grosse Shapes mit Gradients
    $ctx gradient_radial sunbg 400 300 50 \
        [list {0 1.0 0.95 0.7 1} {1 0.95 0.85 0.4 0}]
    $ctx circle 400 300 180 -fillname sunbg

    $ctx gradient_linear oceanbg 600 400 600 900 \
        [list {0 0.3 0.6 0.9 0.9} {1 0.1 0.3 0.6 0.9}]
    $ctx rect 0 500 1200 400 -fillname oceanbg -fill {0.2 0.5 0.8 0.3}

    # Shapes
    $ctx circle 400 300 80 \
        -fill {1.0 0.85 0.2 0.9} -stroke {0.9 0.7 0.1} -width 3

    $ctx ellipse 800 250 120 60 \
        -fill {0.3 0.7 0.4 0.8} -stroke {0.2 0.5 0.3} -width 2

    $ctx rect 100 600 200 150 \
        -fill {0.8 0.3 0.3 0.8} -stroke {0.6 0.2 0.2} \
        -width 2 -radius 12

    $ctx rect 950 400 200 200 \
        -fill {0.5 0.3 0.8 0.8} -stroke {0.4 0.2 0.6} \
        -width 2 -radius 8

    # SVG-Pfad (Stern)
    set cx 700; set cy 650; set r1 80; set r2 35
    set path ""
    for {set i 0} {$i < 10} {incr i} {
        set a [expr {$i * 3.14159 * 2 / 10 - 3.14159/2}]
        set r [expr {($i % 2 == 0) ? $r1 : $r2}]
        set px [expr {$cx + cos($a)*$r}]
        set py [expr {$cy + sin($a)*$r}]
        if {$i == 0} { append path "M $px $py " } \
        else         { append path "L $px $py " }
    }
    append path "Z"
    $ctx path $path -fill {1.0 0.8 0.1 0.9} -stroke {0.8 0.6 0.0} -width 2

    # Labels
    $ctx text 400 300 "Sonne" \
        -font "Sans Bold 16" -color {0.5 0.35 0} -anchor center
    $ctx text 800 250 "Wiese" \
        -font "Sans 12" -color {0.1 0.4 0.1} -anchor center
    $ctx text 200 680 "Haus" \
        -font "Sans 12" -color {0.9 0.9 0.9} -anchor center
    $ctx text 1050 500 "Berg" \
        -font "Sans 12" -color {0.9 0.9 0.9} -anchor center
    $ctx text 700 650 "★" \
        -font "Sans Bold 14" -color {0.5 0.35 0} -anchor center

    # Koordinaten-Achsen (Ursprung)
    $ctx line 0 0 60 0  -color {0.8 0.2 0.2} -width 2 -linecap round
    $ctx line 0 0 0  60 -color {0.2 0.6 0.2} -width 2 -linecap round
    $ctx text 65 5 "X" -font "Sans Bold 10" -color {0.8 0.2 0.2}
    $ctx text 5 68 "Y" -font "Sans Bold 10" -color {0.2 0.6 0.2}

    # Welt-Größe
    $ctx text 1190 890 "1200 × 900" \
        -font "Sans 9" -color {0.5 0.5 0.6} -anchor se
}

proc vpExport {fmt} {
    set f [tk_getSaveFile \
        -defaultextension .$fmt \
        -filetypes [list \
            [list "[string toupper $fmt] Files" .$fmt] \
            {"All Files" *}] \
        -title "Export as [string toupper $fmt]"]
    if {$f eq ""} return
    .vp export $f
    .status configure -text "Exported: $f"
}

# Fit beim Start
after 200 {.vp zoomfit}
