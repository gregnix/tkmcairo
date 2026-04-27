# tkmcairo::plot 0.1
#
# Cairo-based plot/chart widget for Tk.
# Built on tkmcairo::surface — renders via Cairo for antialiased,
# export-ready charts (PDF, SVG, PNG).
#
# API:
#   tkmcairo::plot pathName ?options?
#
#   Widget options:
#     -width -height        size
#     -title string         chart title
#     -background {r g b}   background color (default {1 1 1})
#     -font  fontspec       base font (default "Sans 11")
#     -padding {l t r b}    plot area padding (default {60 40 20 50})
#
#   Axes:
#     $p xaxis ?options?   configure X axis
#     $p yaxis  ?options?  configure Y axis (links)
#     $p y2axis ?options?  configure zweite Y-Achse (rechts)
#       Additional option for series: -yaxis y1|y2
#       Axis options:
#         -label string    axis label
#         -min  number     minimum value (auto if omitted)
#         -max  number     maximum value (auto if omitted)
#         -ticks n         number of ticks (default 5)
#         -format string   tick format (default "%.4g")
#         -type   number|time  number=normal, time=Datum/Zeit X-Achse
#         -grid  0|1       show grid lines (default 0)
#         -gridcolor {r g b}
#
#   Series:
#     $p series type name ?options?
#       type: line | area | bar | scatter | pie
#       Series options (pie):
#         -data   list    flat label value ... pairs
#         -colors list    list of {r g b} per slice (default: auto)
#         -alpha  0..1    opacity (default 1.0)
#       Series options (line/area/scatter):
#         -data   list    flat x y x y ... pairs
#         -color  {r g b}
#         -width  n       line width (default 2)
#         -alpha  0..1    opacity (default 1.0)
#         -dash   list    dash pattern
#         -marker circle|square|none  (default none)
#         -markersize n
#       Series options (bar):
#         -data   list    flat label value ... pairs
#         -color  {r g b}
#         -alpha  0..1
#       Series options (pie):
#         -data   list    flat label value ... pairs
#         -colors list    list of {r g b} per slice
#
#   Legend:
#     $p legend ?-position ne|nw|se|sw|right?
#
#   Rendering:
#     $p redraw
#     $p export filename   PNG/PDF/SVG/PS/EPS
#     $p destroy
#
# Part of tkmcairo — https://github.com/gregnix/tkmcairo
# License: BSD 2-Clause

package provide tkmcairo::plot 0.1

package require Tk
package require tkmcairo::surface

namespace eval ::tkmcairo::plot {}

# ============================================================
# Constructor
# ============================================================
proc ::tkmcairo::plot {w args} {
    array set opts {
        -width      600
        -height     400
        -title      ""
        -background {1 1 1}
        -font       "Sans 11"
        -padding    {60 40 20 50}
    }
    foreach {k v} $args { set opts($k) $v }

    # Create surface widget
    tkmcairo::surface $w \
        -width   $opts(-width)  \
        -height  $opts(-height) \
        -background $opts(-background) \
        -drawcommand [list ::tkmcairo::plot::_drawentry $w]

    # State namespace
    namespace eval ::tkmcairo::plot::S_$w {
        variable xaxis
        variable yaxis
        variable series {}
        variable legend {-position ne}
        variable opts
    }
    set ns ::tkmcairo::plot::S_${w}
    set ${ns}::tooltip_x   -1
    set ${ns}::tooltip_y   -1
    set ${ns}::tooltip_txt ""
    set ${ns}::hidden_series {}

    array set ${ns}::opts [array get opts]
    array set ${ns}::xaxis {
        -label "" -min auto -max auto -ticks 5
        -format "%.4g" -grid 0 -gridcolor {0.88 0.88 0.88}
        -type number
    }
    array set ${ns}::yaxis {
        -label "" -min auto -max auto -ticks 5
        -format "%.4g" -grid 1 -gridcolor {0.88 0.88 0.88}
    }
    array set ${ns}::y2axis {
        -label "" -min auto -max auto -ticks 5
        -format "%.4g" -grid 0 -gridcolor {0.88 0.88 0.88}
        -visible 0
    }

    # Install widget command — rename surface alias, then install plot alias
    # (interp alias {} $w only deletes existing command if it exists; we
    #  remove the surface alias first by overwriting it here)
    interp alias {} $w {} ::tkmcairo::plot::_cmd $w

    bind $w <Destroy> [list namespace delete ::tkmcairo::plot::S_${w}]

    # Tooltip bindings
    bind $w.lbl <Motion>      [list ::tkmcairo::plot::_onMotion $w %x %y]
    bind $w.lbl <Leave>       [list ::tkmcairo::plot::_onLeave  $w]
    bind $w.lbl <ButtonPress-1> [list ::tkmcairo::plot::_onClick  $w %x %y]

    return $w
}

# ============================================================
# Widget command dispatcher
# ============================================================
proc ::tkmcairo::plot::_cmd {w subcmd args} {
    set ns ::tkmcairo::plot::S_${w}
    switch -- $subcmd {
        xaxis   {
            array set ${ns}::xaxis $args
            ::tkmcairo::surface::_redraw $w
        }
        yaxis   {
            array set ${ns}::yaxis $args
            ::tkmcairo::surface::_redraw $w
        }
        y2axis  {
            array set ${ns}::y2axis $args
            set ::tkmcairo::plot::S_${w}::y2axis(-visible) 1
            ::tkmcairo::surface::_redraw $w
        }
        series  {
            lassign $args type name
            set sopts [lrange $args 2 end]
            set slist [set ${ns}::series]
            # Remove existing series with same name
            set slist [lsearch -all -inline -not -index 1 $slist $name]
            lappend slist [list $type $name {*}$sopts]
            set ${ns}::series $slist
            ::tkmcairo::surface::_redraw $w
        }
        legend  {
            set ${ns}::legend $args
            ::tkmcairo::surface::_redraw $w
        }
        redraw  { ::tkmcairo::surface::_redraw $w }
        export  { ::tkmcairo::surface::_export $w {*}$args }
        configure {
            array set ${ns}::opts $args
            # Forward geometry options to surface, not $w (would recurse)
            set sopts {}
            foreach {k v} $args {
                if {$k in {-width -height -background}} {
                    lappend sopts $k $v
                }
            }
            if {$sopts ne {}} {
                ::tkmcairo::surface::_configure $w {*}$sopts
            }
            after idle [list catch [list ::tkmcairo::surface::_redraw $w]]
        }
        cget    { set ${ns}::opts($args) }
        clear   {
            set ${ns}::series {}
            ::tkmcairo::surface::_redraw $w
        }
        destroy { destroy $w }
        default { ::tkmcairo::surface::_cmd $w $subcmd {*}$args }
    }
}

# ============================================================
# Main draw proc — called by surface's drawcommand
# ============================================================
# Bridge proc: surface sets globals ctx/w/h, we forward to _draw
proc ::tkmcairo::plot::_drawentry {plotw} {
    global ctx w h
    ::tkmcairo::plot::_draw $plotw $ctx $w $h
}

proc ::tkmcairo::plot::_draw {w ctx pw ph} {
    set ns ::tkmcairo::plot::S_${w}
    if {![namespace exists $ns]} return

    array set opts  [array get ${ns}::opts]
    array set xa    [array get ${ns}::xaxis]
    array set ya    [array get ${ns}::yaxis]
    array set y2a   [array get ${ns}::y2axis]
    set series      [set ${ns}::series]
    set hasY2 [expr {[info exists y2a(-visible)] && $y2a(-visible)}]

    lassign $opts(-padding) padL padT padR padB
    if {$hasY2} { set padR [expr {max($padR, 60)}] }

    # Plot area in pixels
    set px0 $padL
    set py0 $padT
    set px1 [expr {$pw - $padR}]
    set py1 [expr {$ph - $padB}]
    set pW  [expr {$px1 - $px0}]
    set pH  [expr {$py1 - $py0}]

    if {$pW < 10 || $pH < 10} return

    # --- Auto-range from data ---
    lassign [_dataRange $series] dxmin dxmax dymin dymax

    set xmin [expr {$xa(-min) eq "auto" ? $dxmin : $xa(-min)}]
    set xmax [expr {$xa(-max) eq "auto" ? $dxmax : $xa(-max)}]
    set ymin [expr {$ya(-min) eq "auto" ? $dymin : $ya(-min)}]
    set ymax [expr {$ya(-max) eq "auto" ? $dymax : $ya(-max)}]

    # Fallback if no data
    if {$xmin eq "" || $xmin == $xmax} { set xmin 0; set xmax 10 }
    if {$ymin eq "" || $ymin == $ymax} { set ymin 0; set ymax 10 }

    # Nice range padding (5% margin)
    set xpad [expr {($xmax - $xmin) * 0.05}]
    set ypad [expr {($ymax - $ymin) * 0.05}]
    if {$xa(-min) eq "auto"} { set xmin [expr {$xmin - $xpad}] }
    if {$xa(-max) eq "auto"} { set xmax [expr {$xmax + $xpad}] }
    if {$ya(-min) eq "auto"} { set ymin [expr {$ymin - $ypad}] }
    if {$ya(-max) eq "auto"} { set ymax [expr {$ymax + $ypad}] }

    # Coord transforms
    set xscale [expr {$pW / double($xmax - $xmin)}]
    set yscale [expr {$pH / double($ymax - $ymin)}]

    # Y2-Achse Range
    if {$hasY2} {
        lassign [_dataRangeY2 $series] dy2min dy2max
        set y2min [expr {$y2a(-min) eq "auto" ? $dy2min : $y2a(-min)}]
        set y2max [expr {$y2a(-max) eq "auto" ? $dy2max : $y2a(-max)}]
        if {$y2min eq "" || $y2min == $y2max} { set y2min 0; set y2max 10 }
        set y2pad [expr {($y2max - $y2min) * 0.05}]
        if {$y2a(-min) eq "auto"} { set y2min [expr {$y2min - $y2pad}] }
        if {$y2a(-max) eq "auto"} { set y2max [expr {$y2max + $y2pad}] }
        set y2scale [expr {$pH / double($y2max - $y2min)}]
    } else {
        set y2min 0; set y2max 10; set y2scale 1.0
    }

    # Coord helpers inline in helpers

    # === Draw grid ===
    if {[array get xa -type] ne "" && $xa(-type) eq "time"} {
        set xticks [_niceTimeTicks $xmin $xmax $xa(-ticks)]
    } else {
        set xticks [_niceTicks $xmin $xmax $xa(-ticks)]
    }
    set yticks [_niceTicks $ymin $ymax $ya(-ticks)]

    if {$ya(-grid)} {
        lassign $ya(-gridcolor) gr gg gb
        foreach yv $yticks {
            set py [expr {$py1 - ($yv - $ymin) * $yscale}]
            if {$py < $py0 || $py > $py1} continue
            $ctx line $px0 $py $px1 $py \
                -color [list $gr $gg $gb 0.8] -width 0.5
        }
    }
    if {$xa(-grid)} {
        lassign $xa(-gridcolor) gr gg gb
        foreach xv $xticks {
            set px [expr {$px0 + ($xv - $xmin) * $xscale}]
            if {$px < $px0 || $px > $px1} continue
            $ctx line $px $py0 $px $py1 \
                -color [list $gr $gg $gb 0.8] -width 0.5
        }
    }

    # === Plot area border ===
    $ctx rect $px0 $py0 $pW $pH \
        -stroke {0.6 0.6 0.6} -width 1

    # === Draw series ===
    # Nicht-Pie-Serien: innerhalb clip_rect (Datenpunkte nicht ueber Rahmen)
    # Pie-Serien: ausserhalb clip (brauchen volle Plot-Flaeche)
    set hasPie    0
    set hasNonPie 0
    foreach s $series {
        if {[lindex $s 0] eq "pie"} { set hasPie 1 } else { set hasNonPie 1 }
    }

    if {$hasNonPie} {
        $ctx push
        $ctx clip_rect $px0 $py0 $pW $pH
        foreach s $series {
            set stype [lindex $s 0]
            if {$stype eq "pie"} continue
            set sname [lindex $s 1]
            if {$sname in [set ${ns}::hidden_series]} continue
            array set so {
                -data {} -color {0.2 0.5 0.9} -width 2
                -alpha 1.0 -dash {} -marker none -markersize 5
            }
            array set so [lrange $s 2 end]
            # Choose Y axis
            set useY2 [expr {$hasY2 && [array exists so] && [info exists so(-yaxis)] && $so(-yaxis) eq "y2"}]
            set _ymin   [expr {$useY2 ? $y2min   : $ymin}]
            set _ymax   [expr {$useY2 ? $y2max   : $ymax}]
            set _yscale [expr {$useY2 ? $y2scale : $yscale}]
            switch $stype {
                line    { _drawLine    $ctx $so(-data) so $px0 $py0 $px1 $py1 \
                                           $xmin $xmax $_ymin $_ymax $xscale $_yscale }
                area    { _drawArea    $ctx $so(-data) so $px0 $py0 $px1 $py1 \
                                           $xmin $xmax $_ymin $_ymax $xscale $_yscale }
                scatter { _drawScatter $ctx $so(-data) so $px0 $py0 $px1 $py1 \
                                           $xmin $xmax $_ymin $_ymax $xscale $_yscale }
                bar     { _drawBar     $ctx $so(-data) so $series $px0 $py0 $px1 $py1 \
                                           $xmin $xmax $_ymin $_ymax $pW $pH $xscale $_yscale }
            }
        }
        $ctx pop
    }

    if {$hasPie} {
        foreach s $series {
            if {[lindex $s 0] ne "pie"} continue
            array set so {-data {} -colors {} -alpha 1.0}
            array set so [lrange $s 2 end]
            _drawPie $ctx $so(-data) so $px0 $py0 $pW $pH $opts(-font)
        }
    }

    # === X/Y-Achsen (nur wenn nicht nur Pie-Serien) ===
    if {!$hasPie || $hasNonPie} {
    set lw 1.2
    $ctx line $px0 $py1 $px1 $py1 -color {0.3 0.3 0.3} -width $lw

    foreach xv $xticks {
        set px [expr {$px0 + ($xv - $xmin) * $xscale}]
        if {$px < $px0 - 1 || $px > $px1 + 1} continue
        $ctx line $px $py1 $px [expr {$py1 + 5}] -color {0.3 0.3 0.3} -width $lw
        if {[array get xa -type] ne "" && $xa(-type) eq "time"} {
            set fmt [expr {$xa(-format) eq "%.4g" ? "%d.%m\n%H:%M" : $xa(-format)}]
            set lbl [_timeLabel $xv $fmt]
        } else {
            set lbl [format $xa(-format) $xv]
        }
        set lines [split $lbl "\n"]
        if {[llength $lines] == 2} {
            $ctx text $px [expr {$py1 + 12}] [lindex $lines 0] \
                -font "$opts(-font)" -color {0.2 0.2 0.2} -anchor center
            $ctx text $px [expr {$py1 + 24}] [lindex $lines 1] \
                -font "$opts(-font)" -color {0.4 0.4 0.4} -anchor center
        } else {
            $ctx text $px [expr {$py1 + 18}] $lbl \
                -font "$opts(-font)" -color {0.2 0.2 0.2} -anchor center
        }
    }

    if {$xa(-label) ne ""} {
        $ctx text [expr {($px0+$px1)/2.0}] [expr {$ph - 8}] $xa(-label) \
            -font "$opts(-font) bold" -color {0.2 0.2 0.2} -anchor center
    }

    # === Y Axis ===
    $ctx line $px0 $py0 $px0 $py1 -color {0.3 0.3 0.3} -width $lw

    foreach yv $yticks {
        set py [expr {$py1 - ($yv - $ymin) * $yscale}]
        if {$py < $py0 - 1 || $py > $py1 + 1} continue
        $ctx line [expr {$px0 - 5}] $py $px0 $py -color {0.3 0.3 0.3} -width $lw
        set lbl [format $ya(-format) $yv]
        $ctx text [expr {$px0 - 8}] $py $lbl \
            -font "$opts(-font)" -color {0.2 0.2 0.2} -anchor e
    }

    if {$ya(-label) ne ""} {
        $ctx push
        $ctx transform -translate 16 [expr {($py0+$py1)/2.0}]
        $ctx transform -rotate -90
        $ctx text 0 0 $ya(-label) \
            -font "$opts(-font) bold" -color {0.2 0.2 0.2} -anchor center
        $ctx pop
    }

    } ;# end if !hasPie

    # === Y2-Achse rechts ===
    if {$hasY2} {
        set y2ticks [_niceTicks $y2min $y2max $y2a(-ticks)]
        $ctx line $px1 $py0 $px1 $py1 -color {0.5 0.3 0.1} -width $lw

        foreach yv $y2ticks {
            set py [expr {$py1 - ($yv - $y2min) * $y2scale}]
            if {$py < $py0 - 1 || $py > $py1 + 1} continue
            $ctx line $px1 $py [expr {$px1 + 5}] $py -color {0.5 0.3 0.1} -width $lw
            set lbl [format $y2a(-format) $yv]
            $ctx text [expr {$px1 + 8}] $py $lbl                 -font "$opts(-font)" -color {0.4 0.2 0.0} -anchor w
        }

        if {$y2a(-label) ne ""} {
            $ctx push
            $ctx transform -translate [expr {$pw - 14}] [expr {($py0+$py1)/2.0}]
            $ctx transform -rotate 90
            $ctx text 0 0 $y2a(-label)                 -font "$opts(-font) bold" -color {0.4 0.2 0.0} -anchor center
            $ctx pop
        }
    }

        # === Title ===
    if {$opts(-title) ne ""} {
        $ctx text [expr {$pw/2.0}] [expr {$padT/2.0}] $opts(-title) \
            -font "$opts(-font) bold 14" -color {0.1 0.1 0.1} -anchor center
    }

    # === Tooltip ===
    set ttxt [set ${ns}::tooltip_txt]
    set ttx  [set ${ns}::tooltip_x]
    set tty  [set ${ns}::tooltip_y]
    if {$ttxt ne "" && $ttx >= 0} {
        set tw [expr {[string length $ttxt] * 7 + 16}]
        set th 22
        set tx $ttx
        set ty [expr {$tty - 30}]
        if {$tx + $tw > $pw - 5} { set tx [expr {$pw - $tw - 5}] }
        if {$ty < 5} { set ty [expr {$tty + 15}] }
        $ctx rect $tx $ty $tw $th -fill {0.1 0.1 0.1 0.85} -radius 4
        $ctx text [expr {$tx + 8}] [expr {$ty + 14}] $ttxt \
            -font "$opts(-font)" -color {1 1 1} -anchor w
    }

    # === Legend ===
    set hidden [set ${ns}::hidden_series]
    _drawLegend $ctx $series $pw $ph $padL $padT $padR $padB $opts(-font) $hidden
}

# ============================================================
# Series drawing helpers
# ============================================================
proc ::tkmcairo::plot::_drawLine {ctx data soArr px0 py0 px1 py1
                                   xmin xmax ymin ymax xscale yscale} {
    upvar $soArr so
    if {[llength $data] < 4} return
    lassign $so(-color) r g b
    set alpha $so(-alpha)

    $ctx push

    set path ""
    set first 1
    foreach {xv yv} $data {
        set px [expr {$px0 + ($xv - $xmin) * $xscale}]
        set py [expr {$py1 - ($yv - $ymin) * $yscale}]
        if {$first} {
            append path "M $px $py "
            set first 0
        } else {
            append path "L $px $py "
        }
    }
    set dashopt [expr {$so(-dash) ne {} ? [list -dash $so(-dash)] : {}}]
    $ctx path $path -stroke [list $r $g $b $alpha] \
        -width $so(-width) {*}$dashopt -linecap round -linejoin round

    # Markers
    if {$so(-marker) ne "none"} {
        set ms $so(-markersize)
        foreach {xv yv} $data {
            set px [expr {$px0 + ($xv - $xmin) * $xscale}]
            set py [expr {$py1 - ($yv - $ymin) * $yscale}]
            $ctx circle $px $py $ms \
                -fill [list $r $g $b $alpha] \
                -stroke {1 1 1} -width 1.5
        }
    }
    $ctx pop
}

proc ::tkmcairo::plot::_drawArea {ctx data soArr px0 py0 px1 py1
                                   xmin xmax ymin ymax xscale yscale} {
    upvar $soArr so
    if {[llength $data] < 4} return
    lassign $so(-color) r g b
    set alpha $so(-alpha)

    $ctx push

    # Area fill path (close to baseline)
    set path ""
    set firstpx ""; set firstpy ""
    foreach {xv yv} $data {
        set px [expr {$px0 + ($xv - $xmin) * $xscale}]
        set py [expr {$py1 - ($yv - $ymin) * $yscale}]
        if {$path eq ""} {
            append path "M $px $py1 L $px $py "
            set firstpx $px
        } else {
            append path "L $px $py "
        }
        set lastpx $px
    }
    append path "L $lastpx $py1 Z"

    # Gradient fill
    set fpath $path
    $ctx gradient_linear _areag $px0 $py0 $px0 $py1 \
        [list [list 0 $r $g $b [expr {$alpha*0.5}]] \
              [list 1 $r $g $b [expr {$alpha*0.05}]]]
    $ctx path $fpath -fillname _areag

    # Line on top
    set lpath ""
    foreach {xv yv} $data {
        set px [expr {$px0 + ($xv - $xmin) * $xscale}]
        set py [expr {$py1 - ($yv - $ymin) * $yscale}]
        if {$lpath eq ""} { append lpath "M $px $py " } \
        else              { append lpath "L $px $py " }
    }
    $ctx path $lpath -stroke [list $r $g $b $alpha] \
        -width $so(-width) -linecap round -linejoin round

    $ctx pop
}

proc ::tkmcairo::plot::_drawScatter {ctx data soArr px0 py0 px1 py1
                                      xmin xmax ymin ymax xscale yscale} {
    upvar $soArr so
    if {[llength $data] < 2} return
    lassign $so(-color) r g b
    set alpha $so(-alpha)
    set ms [expr {$so(-markersize) > 0 ? $so(-markersize) : 4}]

    $ctx push
    foreach {xv yv} $data {
        set px [expr {$px0 + ($xv - $xmin) * $xscale}]
        set py [expr {$py1 - ($yv - $ymin) * $yscale}]
        $ctx circle $px $py $ms \
            -fill [list $r $g $b $alpha] \
            -stroke {1 1 1 0.7} -width 1
    }
    $ctx pop
}

proc ::tkmcairo::plot::_drawBar {ctx data soArr seriesList px0 py0 px1 py1
                                  xmin xmax ymin ymax pW pH xscale yscale} {
    upvar $soArr so
    if {[llength $data] < 2} return
    lassign $so(-color) r g b
    set alpha $so(-alpha)

    # Count total bars (number of pairs)
    set n [expr {[llength $data] / 2}]
    if {$n == 0} return

    # Bar positions: evenly distributed across x range
    set barW [expr {$pW / double($n) * 0.7}]
    set step [expr {$pW / double($n)}]

    set i 0
    foreach {lbl val} $data {
        set bx [expr {$px0 + $step * $i + $step * 0.15}]
        set by [expr {$py1 - ($val - $ymin) * $yscale}]
        set by0 [expr {$py1 - ($ymin - $ymin) * $yscale}]
        if {$val < 0} {
            set bh [expr {$by0 - $by}]
            set byt $by
        } else {
            set bh [expr {$by0 - $by}]
            set byt [expr {$by0 - $bh}]
        }
        set bh [expr {abs($bh)}]
        if {$bh < 1} { set bh 1 }

        # Gradient fill
        $ctx gradient_linear _barg $bx $byt $bx [expr {$byt + $bh}] \
            [list [list 0 [expr {min(1,$r*1.2)}] [expr {min(1,$g*1.2)}] [expr {min(1,$b*1.2)}] $alpha] \
                  [list 1 $r $g $b $alpha]]
        $ctx rect $bx $byt $barW $bh \
            -fillname _barg -stroke {1 1 1 0.5} -width 0.5 -radius 2

        # Label below
        $ctx text [expr {$bx + $barW/2.0}] [expr {$py1 + 16}] $lbl \
            -font "Sans 9" -color {0.3 0.3 0.3} -anchor center

        incr i
    }
}


# ============================================================
# Pie Chart
# ============================================================
proc ::tkmcairo::plot::_drawPie {ctx data soArr px0 py0 pW pH font} {
    upvar $soArr so
    if {[llength $data] < 2} return

    # Zentrum und Radius
    set cx  [expr {$px0 + $pW / 2.0}]
    set cy  [expr {$py0 + $pH / 2.0}]
    set rad [expr {min($pW, $pH) * 0.38}]

    # Summe
    set total 0.0
    foreach {lbl val} $data { set total [expr {$total + abs($val)}] }
    if {$total <= 0} return

    # Default-Farben (10 gut unterscheidbare Farben)
    set defaultColors {
        {0.22 0.48 0.85} {0.95 0.55 0.15} {0.28 0.72 0.38}
        {0.85 0.25 0.25} {0.58 0.38 0.78} {0.18 0.72 0.82}
        {0.92 0.82 0.18} {0.52 0.28 0.18} {0.72 0.55 0.25}
        {0.35 0.62 0.55}
    }
    set colors [expr {
        [array get soArr -colors] ne {} && $so(-colors) ne {}
            ? $so(-colors) : $defaultColors
    }]
    set alpha $so(-alpha)

    set pi  3.14159265358979323846
    set deg [expr {$pi / 180.0}]
    set startDeg -90.0   ;# Startpunkt oben

    set ci 0
    foreach {lbl val} $data {
        set angle  [expr {abs($val) / $total * 360.0}]
        set endDeg [expr {$startDeg + $angle}]

        set sr [expr {$startDeg * $deg}]
        set er [expr {$endDeg   * $deg}]

        # Punkte auf dem Kreis
        set x1 [expr {$cx + $rad * cos($sr)}]
        set y1 [expr {$cy + $rad * sin($sr)}]
        set x2 [expr {$cx + $rad * cos($er)}]
        set y2 [expr {$cy + $rad * sin($er)}]

        # large-arc-flag: 1 wenn Winkel > 180
        set large [expr {$angle > 180 ? 1 : 0}]

        # Farbe
        set col [lindex $colors [expr {$ci % [llength $colors]}]]
        lassign $col cr cg cb

        # Segment als SVG-Path: M Zentrum L Startpunkt A ... Endpunkt Z
        # sweep=1 (im Uhrzeigersinn) — funktioniert in nanosvg
        set d "M $cx $cy L $x1 $y1 A $rad $rad 0 $large 1 $x2 $y2 Z"
        $ctx path $d             -fill   [list $cr $cg $cb $alpha]             -stroke {1 1 1} -width 1.5

        # Prozentzahl innerhalb des Segments
        set midDeg [expr {($startDeg + $endDeg) / 2.0}]
        set midRad [expr {$midDeg * $deg}]
        set lr  [expr {$rad * 0.62}]
        set lx  [expr {$cx + $lr * cos($midRad)}]
        set ly  [expr {$cy + $lr * sin($midRad)}]
        set pct [format "%.0f%%" [expr {abs($val) / $total * 100.0}]]
        if {$angle > 15} {
            $ctx text $lx $ly $pct                 -font "$font 10" -color {1 1 1} -anchor center
        }

        # Label ausserhalb (nur wenn Platz)
        if {$angle > 8} {
            set olr [expr {$rad * 1.15}]
            set olx [expr {$cx + $olr * cos($midRad)}]
            set oly [expr {$cy + $olr * sin($midRad)}]
            # Anchor je nach Position
            if     {$olx < $cx - 5} { set anc e  }             elseif {$olx > $cx + 5} { set anc w  }             else                    { set anc center }
            $ctx text $olx $oly $lbl                 -font "$font 9" -color {0.2 0.2 0.2} -anchor $anc
        }

        set startDeg $endDeg
        incr ci
    }
}


# ============================================================
# Legende interaktiv — click to hide/show
# ============================================================
proc ::tkmcairo::plot::_onClick {w mx my} {
    set ns ::tkmcairo::plot::S_${w}
    if {![namespace exists $ns]} return

    array set opts  [array get ${ns}::opts]
    set series      [set ${ns}::series]

    lassign $opts(-padding) padL padT padR padB
    set pw [winfo width  $w]
    set ph [winfo height $w]
    set lw 120
    set lx [expr {$pw - $padR - 10}]
    set ly [expr {$padT + 10}]

    # Klick innerhalb der Legende?
    if {$mx < $lx - $lw || $mx > $lx} return
    if {$my < $ly} return

    # Welche Zeile?
    set row [expr {int(($my - $ly - 5) / 20)}]
    if {$row < 0 || $row >= [llength $series]} return

    set sname [lindex [lindex $series $row] 1]
    set hidden [set ${ns}::hidden_series]

    if {$sname in $hidden} {
        set hidden [lsearch -all -inline -not -exact $hidden $sname]
    } else {
        lappend hidden $sname
    }
    set ${ns}::hidden_series $hidden
    ::tkmcairo::surface::_redraw $w
}

# ============================================================
# Tooltip — hover over a data point
# ============================================================
proc ::tkmcairo::plot::_onMotion {w mx my} {
    set ns ::tkmcairo::plot::S_${w}
    if {![namespace exists $ns]} return

    array set opts  [array get ${ns}::opts]
    array set xa    [array get ${ns}::xaxis]
    array set ya    [array get ${ns}::yaxis]
    array set y2a   [array get ${ns}::y2axis]
    set series      [set ${ns}::series]
    set hasY2 [expr {[info exists y2a(-visible)] && $y2a(-visible)}]

    lassign $opts(-padding) padL padT padR padB
    set pw [winfo width  $w]
    set ph [winfo height $w]
    set px0 $padL
    set py0 $padT
    set px1 [expr {$pw - $padR}]
    set py1 [expr {$ph - $padB}]
    set pW  [expr {$px1 - $px0}]
    set pH  [expr {$py1 - $py0}]

    # Ausserhalb Plot-Bereich
    if {$mx < $px0 || $mx > $px1 || $my < $py0 || $my > $py1} {
        if {[set ${ns}::tooltip_txt] ne ""} {
            set ${ns}::tooltip_txt ""
            ::tkmcairo::surface::_redraw $w
        }
        return
    }

    # Weltkoordinaten berechnen
    lassign [_dataRange $series] dxmin dxmax dymin dymax
    set xmin [expr {$xa(-min) eq "auto" ? $dxmin : $xa(-min)}]
    set xmax [expr {$xa(-max) eq "auto" ? $dxmax : $xa(-max)}]
    set ymin [expr {$ya(-min) eq "auto" ? $dymin : $ya(-min)}]
    set ymax [expr {$ya(-max) eq "auto" ? $dymax : $ya(-max)}]
    if {$xmin eq "" || $xmin == $xmax} { set xmin 0; set xmax 10 }
    if {$ymin eq "" || $ymin == $ymax} { set ymin 0; set ymax 10 }
    set xscale [expr {$pW / double($xmax - $xmin)}]
    set yscale [expr {$pH / double($ymax - $ymin)}]

    set wx [expr {($mx - $px0) / $xscale + $xmin}]
    set wy [expr {($py1 - $my) / $yscale + $ymin}]

    # Find the nearest data point (any line/area/scatter series)
    set best_d  1e9
    set best_txt ""
    set threshold [expr {15.0 / $xscale}]   ;# 15 Pixel Toleranz

    foreach s $series {
        set stype [lindex $s 0]
        set sname [lindex $s 1]
        if {$stype ni {line area scatter}} continue
        array set so {-data {}}
        array set so [lrange $s 2 end]
        foreach {xv yv} $so(-data) {
            set dx [expr {abs($xv - $wx)}]
            set dy [expr {abs($yv - $wy)}]
            set d  [expr {hypot($dx * $xscale, $dy * $yscale)}]
            if {$d < $best_d && $d < 20} {
                set best_d $d
                set useY2 [expr {$hasY2 && [info exists so(-yaxis)] && $so(-yaxis) eq "y2"}]
                set _ymin2   [expr {$useY2 ? $y2min   : $ymin}]
                set _ymax2   [expr {$useY2 ? $y2max   : $ymax}]
                set _yscale2 [expr {$useY2 ? $y2scale : $yscale}]
                if {$xa(-type) eq "time"} {
                    set xl [clock format [expr {int($xv)}] -format "%d.%m.%Y %H:%M"]
                } else {
                    set xl [format "%.4g" $xv]
                }
                set best_txt "$sname: ($xl, [format %.4g $yv])"
            }
        }
    }

    set ${ns}::tooltip_txt $best_txt
    set ${ns}::tooltip_x   $mx
    set ${ns}::tooltip_y   $my
    ::tkmcairo::surface::_redraw $w
}

proc ::tkmcairo::plot::_onLeave {w} {
    set ns ::tkmcairo::plot::S_${w}
    if {![namespace exists $ns]} return
    if {[set ${ns}::tooltip_txt] ne ""} {
        set ${ns}::tooltip_txt ""
        ::tkmcairo::surface::_redraw $w
    }
}

# ============================================================
# Legend
# ============================================================
proc ::tkmcairo::plot::_drawLegend {ctx series pw ph padL padT padR padB font {hidden {}}} {
    if {[llength $series] == 0} return

    set lx [expr {$pw - $padR - 10}]
    set ly [expr {$padT + 10}]
    set lh [expr {[llength $series] * 20 + 10}]
    set lw 120

    # Legend box
    $ctx rect [expr {$lx - $lw}] $ly $lw $lh \
        -fill {1 1 1 0.9} -stroke {0.7 0.7 0.7} -width 0.8 -radius 3

    set y [expr {$ly + 15}]
    foreach s $series {
        set sname [lindex $s 1]
        set isHidden [expr {$sname in $hidden}]
        array set so {-color {0.5 0.5 0.5} -alpha 1.0}
        array set so [lrange $s 2 end]
        lassign $so(-color) r g b

        # Hover-Hintergrund (Reihe klickbar)
        if {$isHidden} {
            $ctx rect [expr {$lx - $lw + 2}] [expr {$y - 8}] [expr {$lw - 4}] 18 \
                -fill {0.93 0.93 0.93} -radius 2
        }

        # Color swatch (ausgegraut wenn hidden)
        set sa [expr {$isHidden ? 0.25 : $so(-alpha)}]
        $ctx rect [expr {$lx - $lw + 8}] [expr {$y - 6}] 16 10 \
            -fill [list $r $g $b $sa] -radius 2

        # Durchgestrichen wenn hidden
        if {$isHidden} {
            $ctx line [expr {$lx - $lw + 8}] [expr {$y - 1}] \
                      [expr {$lx - $lw + 24}] [expr {$y - 1}] \
                      -color {0.5 0.5 0.5} -width 1
        }

        # Name (grau wenn hidden)
        set tc [expr {$isHidden ? {0.6 0.6 0.6} : {0.2 0.2 0.2}}]
        $ctx text [expr {$lx - $lw + 30}] $y $sname \
            -font "Sans 9" -color $tc -anchor w
        incr y 20
    }
}

# ============================================================
# Helpers
# ============================================================


# ============================================================
# Time ticks for the time axis
# ============================================================
proc ::tkmcairo::plot::_niceTimeTicks {tmin tmax n} {
    set span [expr {$tmax - $tmin}]
    if {$span <= 0} { return [list $tmin] }

    # Nice time intervals in seconds
    set intervals {
        60       1min
        300      5min
        600      10min
        1800     30min
        3600     1h
        10800    3h
        21600    6h
        43200    12h
        86400    1d
        172800   2d
        604800   1w
        2592000  1mon
        7776000  3mon
        31536000 1y
    }

    # Ziel: ~n Ticks
    set target [expr {$span / double($n)}]
    set chosen 60
    foreach {secs name} $intervals {
        set chosen $secs
        if {$secs >= $target} break
    }

    # Ersten Tick runden
    set first [expr {ceil($tmin / double($chosen)) * $chosen}]
    set ticks {}
    set v $first
    while {$v <= $tmax + $chosen * 0.01} {
        lappend ticks $v
        set v [expr {$v + $chosen}]
    }
    return $ticks
}

proc ::tkmcairo::plot::_timeLabel {epoch fmt} {
    # fmt may contain \n for two-line labels
    # Wir splitten an \n und zeichnen zwei Zeilen
    clock format [expr {int($epoch)}] -format $fmt
}


# Compute data range for Y2 series only
proc ::tkmcairo::plot::_dataRangeY2 {series} {
    set ymin ""; set ymax ""
    foreach s $series {
        set stype [lindex $s 0]
        if {$stype eq "pie"} continue
        array set so {-data {} -yaxis y1}
        set extra [lrange $s 2 end]
        if {[llength $extra] % 2 == 0} { array set so $extra }
        if {$so(-yaxis) ne "y2"} continue
        foreach {xv yv} $so(-data) {
            if {$ymin eq "" || $yv < $ymin} { set ymin $yv }
            if {$ymax eq "" || $yv > $ymax} { set ymax $yv }
        }
    }
    list $ymin $ymax
}

# Compute nice tick values
proc ::tkmcairo::plot::_niceTicks {mn mx n} {
    if {$mx == $mn} { return [list $mn] }
    set range  [expr {abs($mx - $mn)}]
    set rough  [expr {$range / double($n)}]
    set mag    [expr {pow(10, floor(log10($rough)))}]
    set norm   [expr {$rough / $mag}]
    if      {$norm < 1.5} { set step [expr {1 * $mag}] } \
    elseif  {$norm < 3.5} { set step [expr {2 * $mag}] } \
    elseif  {$norm < 7.5} { set step [expr {5 * $mag}] } \
    else                  { set step [expr {10 * $mag}] }

    set first [expr {ceil($mn / $step) * $step}]
    set ticks {}
    set v $first
    while {$v <= $mx + $step * 0.01} {
        lappend ticks [expr {round($v / $step) * $step}]
        set v [expr {$v + $step}]
    }
    return $ticks
}

# Compute data range across all series
proc ::tkmcairo::plot::_dataRange {series} {
    set xmin ""; set xmax ""; set ymin ""; set ymax ""
    foreach s $series {
        set stype [lindex $s 0]
        if {$stype eq "pie"} continue
        array set so {-data {} -yaxis y1}
        # lrange sicher: nur wenn gerade Anzahl
        set extra [lrange $s 2 end]
        if {[llength $extra] % 2 == 0} { array set so $extra }
        set isY2 [expr {[info exists so(-yaxis)] && $so(-yaxis) eq "y2"}]
        foreach {xv yv} $so(-data) {
            if {$xmin eq "" || $xv < $xmin} { set xmin $xv }
            if {$xmax eq "" || $xv > $xmax} { set xmax $xv }
            # Y range only for Y1 series
            if {!$isY2} {
                if {$ymin eq "" || $yv < $ymin} { set ymin $yv }
                if {$ymax eq "" || $yv > $ymax} { set ymax $yv }
            }
        }
    }
    list $xmin $xmax $ymin $ymax
}
