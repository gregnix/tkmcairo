#!/usr/bin/env wish
# demo-axis.tcl — tkmcairo::coords + axis + legend + data Demo

package require Tk

set _dir [file dirname [file normalize [info script]]]
tcl::tm::path add [file join $_dir .. tcl]
if {[info exists env(TCLMCAIRO_LIBDIR)]} {
    lappend auto_path $env(TCLMCAIRO_LIBDIR)
    tcl::tm::path add $env(TCLMCAIRO_LIBDIR)
}

package require tkmcairo::surface
package require tkmcairo::coords
package require tkmcairo::axis
package require tkmcairo::legend
package require tkmcairo::data

wm title . "tkmcairo — coords + axis + legend + data"
wm geometry . 860x560

ttk::notebook .nb
pack .nb -fill both -expand 1

# ============================================================
# Tab 1: Linien-Chart mit Achsen + Legende
# ============================================================
ttk::frame .nb.line
.nb add .nb.line -text "Line Chart"

tkmcairo::surface .nb.line.s \
    -width 820 -height 500 \
    -background {0.97 0.97 1.0} \
    -drawcommand {drawLine $ctx $w $h}
pack .nb.line.s -fill both -expand 1

proc drawLine {ctx w h} {
    $ctx clear 0.97 0.97 1.0 1

    # Margins
    set ml 70; set mr 30; set mt 40; set mb 50

    # Daten
    set s1x {0 1 2 3 4 5 6 7 8 9 10}
    set s1y {2 5 3 8 6 9 7 11 8 12 10}
    set s2x {0 1 2 3 4 5 6 7 8 9 10}
    set s2y {8 6 9 5 10 4 11 5 9 6 8}

    # Datenbereich ermitteln
    set allx [concat $s1x $s2x]
    set ally [concat $s1y $s2y]
    set xmin [tcl::mathfunc::min {*}$allx]
    set xmax [tcl::mathfunc::max {*}$allx]
    set ymin 0
    set ymax [expr {[tcl::mathfunc::max {*}$ally] * 1.1}]

    # Koordinaten-Transform
    set tr [tkmcairo::coords::transform new \
        -xmin $xmin -xmax $xmax \
        -ymin $ymin -ymax $ymax \
        -px0 $ml -py0 $mt \
        -px1 [expr {$w - $mr}] \
        -py1 [expr {$h - $mb}]]

    # Plot-Hintergrund
    lassign [$tr pixelBounds] px0 py0 px1 py1
    $ctx rect $px0 $py0 [expr {$px1-$px0}] [expr {$py1-$py0}] \
        -fill {1 1 1 1} -stroke {0.8 0.8 0.85} -width 0.5

    # Achsen
    tkmcairo::axis::drawX $ctx $tr \
        -grid 1 -gridcolor {0.9 0.9 0.93} \
        -label "X-Achse" -ticks 6 -color {0.3 0.3 0.4}
    tkmcairo::axis::drawY $ctx $tr \
        -grid 1 -gridcolor {0.9 0.9 0.93} \
        -label "Werte" -ticks 6 -color {0.3 0.3 0.4}

    # Titel
    $ctx text [expr {int($w/2)}] 22 "Line Chart — coords + axis + legend" \
        -font "Sans Bold 13" -color {0.1 0.1 0.3} -anchor center

    # Serie 1 — Linie + Punkte
    set col1 {0.2 0.5 0.9}
    set pts1 {}
    foreach x $s1x y $s1y {
        lappend pts1 [$tr toPixelX $x] [$tr toPixelY $y]
    }
    # Linie
    for {set i 0} {$i < [llength $pts1]-2} {incr i 2} {
        $ctx line [lindex $pts1 $i] [lindex $pts1 $i+1] \
                  [lindex $pts1 $i+2] [lindex $pts1 $i+3] \
            -color [list {*}$col1 1] -width 2
    }
    # Punkte
    foreach {px py} $pts1 {
        $ctx circle $px $py 4 \
            -fill [list {*}$col1 1] -stroke {1 1 1} -width 1
    }

    # Serie 2 — Linie gestrichelt + Punkte
    set col2 {0.9 0.4 0.2}
    set pts2 {}
    foreach x $s2x y $s2y {
        lappend pts2 [$tr toPixelX $x] [$tr toPixelY $y]
    }
    for {set i 0} {$i < [llength $pts2]-2} {incr i 2} {
        $ctx line [lindex $pts2 $i] [lindex $pts2 $i+1] \
                  [lindex $pts2 $i+2] [lindex $pts2 $i+3] \
            -color [list {*}$col2 1] -width 2 -dash {6 3}
    }
    foreach {px py} $pts2 {
        $ctx circle $px $py 4 \
            -fill [list {*}$col2 1] -stroke {1 1 1} -width 1
    }

    # Legende
    set series [list \
        [dict create name "Serie A" color $col1 type line] \
        [dict create name "Serie B" color $col2 type line]]
    tkmcairo::legend::draw $ctx $series \
        -position ne -pw [expr {$w-$mr}] -ph [expr {$h-$mb}] \
        -font "Sans 10"

    $tr destroy
}

# ============================================================
# Tab 2: Bar Chart
# ============================================================
ttk::frame .nb.bar
.nb add .nb.bar -text "Bar Chart"

tkmcairo::surface .nb.bar.s \
    -width 820 -height 500 \
    -background {0.97 0.97 1.0} \
    -drawcommand {drawBar $ctx $w $h}
pack .nb.bar.s -fill both -expand 1

proc drawBar {ctx w h} {
    $ctx clear 0.97 0.97 1.0 1

    set ml 70; set mr 30; set mt 40; set mb 50

    set labels {Jan Feb Mär Apr Mai Jun Jul Aug Sep Okt Nov Dez}
    set vals   {42 38 55 61 70 85 92 88 74 63 48 35}

    set n  [llength $vals]
    set ymax [expr {[tcl::mathfunc::max {*}$vals] * 1.15}]

    set tr [tkmcairo::coords::transform new \
        -xmin -0.5 -xmax [expr {$n - 0.5}] \
        -ymin 0    -ymax $ymax \
        -px0 $ml -py0 $mt \
        -px1 [expr {$w-$mr}] -py1 [expr {$h-$mb}]]

    lassign [$tr pixelBounds] px0 py0 px1 py1
    $ctx rect $px0 $py0 [expr {$px1-$px0}] [expr {$py1-$py0}] \
        -fill {1 1 1} -stroke {0.8 0.8 0.85} -width 0.5

    # Y-Achse + Grid
    tkmcairo::axis::drawY $ctx $tr \
        -grid 1 -gridcolor {0.9 0.9 0.93} \
        -label "Einheiten" -ticks 6 -color {0.3 0.3 0.4}

    # Titel
    $ctx text [expr {int($w/2)}] 22 "Bar Chart — Monatswerte" \
        -font "Sans Bold 13" -color {0.1 0.1 0.3} -anchor center

    # Balken
    set bw [expr {($px1-$px0) / $n * 0.6}]
    set colors [list \
        {0.2 0.5 0.9} {0.3 0.7 0.4} {0.9 0.5 0.2} \
        {0.7 0.3 0.8} {0.2 0.7 0.8} {0.9 0.8 0.2}]

    set i 0
    foreach lbl $labels val $vals {
        set cx [$tr toPixelX $i]
        set by [$tr toPixelY 0]
        set ty [$tr toPixelY $val]
        set col [lindex $colors [expr {$i % 6}]]

        $ctx rect [expr {$cx - $bw/2.0}] $ty \
                  $bw [expr {$by - $ty}] \
            -fill [list {*}$col 0.85] \
            -stroke [list [expr {[lindex $col 0]*0.7}] \
                          [expr {[lindex $col 1]*0.7}] \
                          [expr {[lindex $col 2]*0.7}]] \
            -width 0.8 -radius 2

        # X-Label
        $ctx text $cx [expr {$by + 14}] $lbl \
            -font "Sans 9" -color {0.3 0.3 0.4} -anchor center

        # Wert oben
        $ctx text $cx [expr {$ty - 6}] $val \
            -font "Sans Bold 9" -color {0.2 0.2 0.5} -anchor center

        incr i
    }

    # X-Achsenlinie
    $ctx line $px0 $py1 $px1 $py1 -color {0.5 0.5 0.6} -width 1.2

    $tr destroy
}

# ============================================================
# Tab 3: Scatter + data::smooth
# ============================================================
ttk::frame .nb.scatter
.nb add .nb.scatter -text "Scatter + Smooth"

tkmcairo::surface .nb.scatter.s \
    -width 820 -height 500 \
    -background {0.97 0.97 1.0} \
    -drawcommand {drawScatter $ctx $w $h}
pack .nb.scatter.s -fill both -expand 1

proc drawScatter {ctx w h} {
    $ctx clear 0.97 0.97 1.0 1

    set ml 70; set mr 30; set mt 40; set mb 50

    # Zufallsdaten mit Seed
    expr {srand(42)}
    set rawx {}; set rawy {}
    for {set i 0} {$i < 60} {incr i} {
        lappend rawx [expr {$i / 6.0}]
        lappend rawy [expr {sin($i/6.0) * 4 + rand()*3 + 5}]
    }
    set xydata [concat {*}[lmap x $rawx y $rawy {list $x $y}]]

    # Smooth
    set smoothed [tkmcairo::data::smooth $xydata 7]

    lassign [tkmcairo::data::range $xydata] xmin xmax ymin ymax

    set tr [tkmcairo::coords::transform new \
        -xmin $xmin -xmax $xmax \
        -ymin [expr {$ymin - 0.5}] -ymax [expr {$ymax + 0.5}] \
        -px0 $ml -py0 $mt \
        -px1 [expr {$w-$mr}] -py1 [expr {$h-$mb}]]

    lassign [$tr pixelBounds] px0 py0 px1 py1
    $ctx rect $px0 $py0 [expr {$px1-$px0}] [expr {$py1-$py0}] \
        -fill {1 1 1} -stroke {0.8 0.8 0.85} -width 0.5

    tkmcairo::axis::drawX $ctx $tr \
        -grid 1 -gridcolor {0.9 0.9 0.93} -ticks 6 -color {0.3 0.3 0.4}
    tkmcairo::axis::drawY $ctx $tr \
        -grid 1 -gridcolor {0.9 0.9 0.93} -ticks 6 -color {0.3 0.3 0.4}

    $ctx text [expr {int($w/2)}] 22 "Scatter + data::smooth (Moving Average n=7)" \
        -font "Sans Bold 13" -color {0.1 0.1 0.3} -anchor center

    # Scatter Punkte
    foreach {x y} $xydata {
        $ctx circle [$tr toPixelX $x] [$tr toPixelY $y] 3 \
            -fill {0.4 0.6 0.9 0.5} -stroke {0.3 0.5 0.8 0.7} -width 0.5
    }

    # Glättungslinie
    set pts {}
    foreach {x y} $smoothed {
        lappend pts [$tr toPixelX $x] [$tr toPixelY $y]
    }
    for {set i 0} {$i < [llength $pts]-2} {incr i 2} {
        $ctx line [lindex $pts $i]   [lindex $pts $i+1] \
                  [lindex $pts $i+2] [lindex $pts $i+3] \
            -color {0.85 0.3 0.2 0.9} -width 2.5
    }

    # Legende
    set series [list \
        [dict create name "Messwerte" color {0.4 0.6 0.9} type scatter] \
        [dict create name "Glättung n=7" color {0.85 0.3 0.2} type line]]
    tkmcairo::legend::draw $ctx $series \
        -position ne -pw [expr {$w-$mr}] -ph [expr {$h-$mb}]

    $tr destroy
}
