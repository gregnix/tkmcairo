# tkmcairo::axis 0.1
#
# Achsen zeichnen mit tclmcairo. Nutzt tkmcairo::coords für Transformation.
#
# API:
#   tkmcairo::axis::drawX $ctx $tr ?options?
#   tkmcairo::axis::drawY $ctx $tr ?options?
#   tkmcairo::axis::drawY2 $ctx $tr ?options?  (rechte Achse)
#
#   Optionen:
#     -label    string      Achsen-Beschriftung
#     -ticks    n           Anzahl Ticks (default 5)
#     -format   string      Tick-Format (default "%.4g")
#     -grid     0|1         Gitternetz (default 0)
#     -gridcolor {r g b}    Gitterfarbe (default {0.88 0.88 0.88})
#     -color    {r g b}     Achsen-/Tick-Farbe (default {0.3 0.3 0.3})
#     -font     fontspec    Tick-Font (default "Sans 10")
#     -labelfont fontspec   Label-Font (default "Sans 11 bold")
#     -ticklen  n           Tick-Länge in Pixel (default 5)
#     -width    n           Linienbreite (default 1.2)
#
#   tkmcairo::axis::niceTicks min max n -> Tick-Werte
#
# Part of tkmcairo — https://github.com/gregnix/tkmcairo
# License: BSD 2-Clause

package provide tkmcairo::axis 0.1.1

package require tkmcairo::coords

namespace eval ::tkmcairo::axis {}

# ============================================================
# X-Achse
# ============================================================
proc ::tkmcairo::axis::drawX {ctx tr args} {
    array set opts {
        -label "" -ticks 5 -format "%.4g"
        -grid 0 -gridcolor {0.88 0.88 0.88}
        -color {0.3 0.3 0.3} -font "Sans 10"
        -labelfont "Sans 11 bold" -ticklen 5 -width 1.2
    }
    foreach {k v} $args { set opts($k) $v }

    lassign [$tr pixelBounds] px0 py0 px1 py1
    lassign [$tr worldBounds] xmin xmax ymin ymax
    lassign $opts(-color) r g b
    set lw $opts(-width)

    # Achsenlinie
    $ctx line $px0 $py1 $px1 $py1 -color [list $r $g $b 1] -width $lw

    # Ticks + Labels + Grid
    set ticks [niceTicks $xmin $xmax $opts(-ticks)]
    foreach xv $ticks {
        set px [$tr toPixelX $xv]
        if {$px < $px0 - 1 || $px > $px1 + 1} continue

        # Grid
        if {$opts(-grid)} {
            lassign $opts(-gridcolor) gr gg gb
            $ctx line $px $py0 $px $py1 \
                -color [list $gr $gg $gb 1] -width 0.5
        }
        # Tick
        $ctx line $px $py1 $px [expr {$py1 + $opts(-ticklen)}] \
            -color [list $r $g $b 1] -width $lw

        # Label
        set lbl [format $opts(-format) $xv]
        $ctx text $px [expr {$py1 + $opts(-ticklen) + 14}] $lbl \
            -font $opts(-font) -color [list $r $g $b 1] -anchor center
    }

    # Achsen-Label
    if {$opts(-label) ne ""} {
        set lx [expr {($px0 + $px1) / 2.0}]
        set ly [expr {$py1 + $opts(-ticklen) + 30}]
        $ctx text $lx $ly $opts(-label) \
            -font $opts(-labelfont) -color [list $r $g $b 1] -anchor center
    }
}

# ============================================================
# Y-Achse (links)
# ============================================================
proc ::tkmcairo::axis::drawY {ctx tr args} {
    array set opts {
        -label "" -ticks 5 -format "%.4g"
        -grid 0 -gridcolor {0.88 0.88 0.88}
        -color {0.3 0.3 0.3} -font "Sans 10"
        -labelfont "Sans 11 bold" -ticklen 5 -width 1.2
    }
    foreach {k v} $args { set opts($k) $v }

    lassign [$tr pixelBounds] px0 py0 px1 py1
    lassign [$tr worldBounds] xmin xmax ymin ymax
    lassign $opts(-color) r g b
    set lw $opts(-width)

    # Achsenlinie
    $ctx line $px0 $py0 $px0 $py1 -color [list $r $g $b 1] -width $lw

    # Ticks + Labels + Grid
    set ticks [niceTicks $ymin $ymax $opts(-ticks)]
    foreach yv $ticks {
        set py [$tr toPixelY $yv]
        if {$py < $py0 - 1 || $py > $py1 + 1} continue

        # Grid
        if {$opts(-grid)} {
            lassign $opts(-gridcolor) gr gg gb
            $ctx line $px0 $py $px1 $py \
                -color [list $gr $gg $gb 1] -width 0.5
        }
        # Tick
        $ctx line [expr {$px0 - $opts(-ticklen)}] $py $px0 $py \
            -color [list $r $g $b 1] -width $lw

        # Label
        set lbl [format $opts(-format) $yv]
        $ctx text [expr {$px0 - $opts(-ticklen) - 4}] $py $lbl \
            -font $opts(-font) -color [list $r $g $b 1] -anchor e
    }

    # Achsen-Label (rotiert)
    if {$opts(-label) ne ""} {
        set ly [expr {($py0 + $py1) / 2.0}]
        set lx [expr {$px0 - $opts(-ticklen) - 30}]
        $ctx push
        $ctx transform -translate $lx $ly
        $ctx transform -rotate -90
        $ctx text 0 0 $opts(-label) \
            -font $opts(-labelfont) -color [list $r $g $b 1] -anchor center
        $ctx pop
    }
}

# ============================================================
# Y2-Achse (rechts) — zweite Y-Achse mit eigenem transform
# ============================================================
proc ::tkmcairo::axis::drawY2 {ctx tr args} {
    array set opts {
        -label "" -ticks 5 -format "%.4g"
        -color {0.8 0.3 0.2} -font "Sans 10"
        -labelfont "Sans 11 bold" -ticklen 5 -width 1.2
    }
    foreach {k v} $args { set opts($k) $v }

    lassign [$tr pixelBounds] px0 py0 px1 py1
    lassign [$tr worldBounds] xmin xmax ymin ymax
    lassign $opts(-color) r g b
    set lw $opts(-width)

    # Achsenlinie rechts
    $ctx line $px1 $py0 $px1 $py1 -color [list $r $g $b 1] -width $lw

    set ticks [niceTicks $ymin $ymax $opts(-ticks)]
    foreach yv $ticks {
        set py [$tr toPixelY $yv]
        if {$py < $py0 - 1 || $py > $py1 + 1} continue

        $ctx line $px1 $py [expr {$px1 + $opts(-ticklen)}] $py \
            -color [list $r $g $b 1] -width $lw

        set lbl [format $opts(-format) $yv]
        $ctx text [expr {$px1 + $opts(-ticklen) + 4}] $py $lbl \
            -font $opts(-font) -color [list $r $g $b 1] -anchor w
    }

    if {$opts(-label) ne ""} {
        set ly [expr {($py0 + $py1) / 2.0}]
        set lx [expr {$px1 + $opts(-ticklen) + 30}]
        $ctx push
        $ctx transform -translate $lx $ly
        $ctx transform -rotate 90
        $ctx text 0 0 $opts(-label) \
            -font $opts(-labelfont) -color [list $r $g $b 1] -anchor center
        $ctx pop
    }
}

# ============================================================
# Zeitachse X (Datum/Uhrzeit)
# ============================================================
proc ::tkmcairo::axis::drawTimeX {ctx tr args} {
    array set opts {
        -label "" -format "%d.%m"
        -ticks monthly -color {0.3 0.3 0.3}
        -font "Sans 9" -labelfont "Sans 11 bold"
        -ticklen 5 -width 1.2 -grid 0
        -gridcolor {0.88 0.88 0.88}
    }
    foreach {k v} $args { set opts($k) $v }

    lassign [$tr pixelBounds] px0 py0 px1 py1
    lassign [$tr worldBounds] xmin xmax ymin ymax
    lassign $opts(-color) r g b

    # Achsenlinie
    $ctx line $px0 $py1 $px1 $py1 -color [list $r $g $b 1] -width $opts(-width)

    # Ticks generieren (Epoch-Sekunden → Tage/Monate)
    set ticks [_timeTicks $xmin $xmax $opts(-ticks)]
    foreach {tv lbl} $ticks {
        set px [$tr toPixelX $tv]
        if {$px < $px0 - 1 || $px > $px1 + 1} continue

        if {$opts(-grid)} {
            lassign $opts(-gridcolor) gr gg gb
            $ctx line $px $py0 $px $py1 \
                -color [list $gr $gg $gb 1] -width 0.5
        }
        $ctx line $px $py1 $px [expr {$py1 + $opts(-ticklen)}] \
            -color [list $r $g $b 1] -width $opts(-width)
        $ctx text $px [expr {$py1 + $opts(-ticklen) + 12}] $lbl \
            -font $opts(-font) -color [list $r $g $b 1] -anchor center
    }

    if {$opts(-label) ne ""} {
        $ctx text [expr {($px0+$px1)/2.0}] [expr {$py1 + $opts(-ticklen) + 28}] \
            $opts(-label) -font $opts(-labelfont) \
            -color [list $r $g $b 1] -anchor center
    }
}

# ============================================================
# Hilfsfunktionen
# ============================================================

# Schöne runde Tick-Werte — aus plotchart/plotaxis.tcl adaptiert
# (Arjen Markus, Tcl-Lizenz)
proc ::tkmcairo::axis::niceTicks {mn mx n} {
    if {$mx == $mn || $n <= 0} { return [list $mn] }
    set range  [expr {abs($mx - $mn)}]
    set rough  [expr {$range / double($n)}]
    set mag    [expr {pow(10, floor(log10($rough)))}]
    set norm   [expr {$rough / $mag}]
    if      {$norm < 1.5} { set step [expr {1   * $mag}] } \
    elseif  {$norm < 3.5} { set step [expr {2   * $mag}] } \
    elseif  {$norm < 7.5} { set step [expr {5   * $mag}] } \
    else                  { set step [expr {10  * $mag}] }

    set first [expr {ceil($mn / $step) * $step}]
    set ticks {}
    set v $first
    while {$v <= $mx + $step * 0.01} {
        lappend ticks [expr {round($v / $step) * $step}]
        set v [expr {$v + $step}]
    }
    return $ticks
}

# Zeitachsen-Ticks (Epoch → Label-Paare)
proc ::tkmcairo::axis::_timeTicks {tmin tmax mode} {
    set result {}
    set secday 86400
    set secmon [expr {30 * $secday}]

    switch $mode {
        monthly {
            # Jeden Monatsersten
            set t $tmin
            while {$t <= $tmax} {
                set lbl [clock format [expr {int($t)}] -format "%b %y"]
                lappend result $t $lbl
                set t [expr {$t + $secmon}]
            }
        }
        weekly {
            set t [expr {$tmin - fmod($tmin, 7*$secday)}]
            while {$t <= $tmax} {
                set lbl [clock format [expr {int($t)}] -format "%d.%m"]
                lappend result $t $lbl
                set t [expr {$t + 7*$secday}]
            }
        }
        daily {
            set t $tmin
            while {$t <= $tmax} {
                set lbl [clock format [expr {int($t)}] -format "%d.%m"]
                lappend result $t $lbl
                set t [expr {$t + $secday}]
            }
        }
        default {
            # Numerisch als Fallback
            foreach v [niceTicks $tmin $tmax 5] {
                lappend result $v [format "%.0f" $v]
            }
        }
    }
    return $result
}

# Datums-String → Epoch (Hilfsfunktion für Anwender)
proc ::tkmcairo::axis::timeToNum {datestr} {
    clock scan $datestr
}
