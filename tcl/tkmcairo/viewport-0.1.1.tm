# tkmcairo::viewport 0.1
#
# Scrollbares/zoombares Cairo-Widget.
# Baut auf tkmcairo::surface und scrollutil::scrollarea auf.
#
# API:
#   tkmcairo::viewport pathName ?options?
#
#   Options (zusätzlich zu surface-Optionen):
#     -worldwidth  n    Welt-Breite in Pixeln (default 2000)
#     -worldheight n    Welt-Höhe in Pixeln (default 2000)
#     -minzoom     f    Minimaler Zoom-Faktor (default 0.1)
#     -maxzoom     f    Maximaler Zoom-Faktor (default 10.0)
#     -drawcommand script  wie bei surface: $ctx $w $h
#     -scrollbars  0|1  Scrollbalken anzeigen (default 0)
#                        Kein scrollutil nötig — native ttk::scrollbar
#
#   Widget-Commands:
#     $vp zoom factor ?cx cy?  Zoom um Bildschirm-Mittelpunkt oder cx/cy
#     $vp zoomfit               Zoom auf ganzes Weltkoordinaten-System
#     $vp zoom1                 Zoom auf 1:1
#     $vp pan dx dy             Verschiebung in Pixel
#     $vp zoomlevel             aktueller Zoom-Faktor
#     $vp worldToScreen x y     Weltkoord → Pixel
#     $vp screenToWorld px py   Pixel → Weltkoord
#     $vp redraw
#     $vp export filename                     save to file (format from extension)
#     $vp export -chan $ch -format fmt        stream to channel (PNG/PDF/SVG/PS/EPS)
#     $vp configure ...
#     $vp cget option
#
# Requirements: tkmcairo::surface, scrollutil_tile (optional)
#
# Part of tkmcairo — https://github.com/gregnix/tkmcairo
# License: BSD 2-Clause

package provide tkmcairo::viewport 0.1.1

package require Tk
package require tkmcairo::surface

namespace eval ::tkmcairo::viewport {}

# ============================================================
# Konstruktor
# ============================================================
proc ::tkmcairo::viewport {w args} {
    array set opts {
        -worldwidth  2000
        -worldheight 2000
        -minzoom     0.05
        -maxzoom     10.0
        -drawcommand ""
        -background  {1 1 1}
        -width       600
        -height      400
        -scrollbars  0
    }
    foreach {k v} $args { set opts($k) $v }

    # Äußerer Frame
    ttk::frame $w
    rename $w ::tkmcairo::viewport::_frame_[string map {. _ : _} $w]
    interp alias {} $w {} ::tkmcairo::viewport::_cmd $w

    # State-Namespace
    namespace eval ::tkmcairo::viewport::S_$w {
        variable zoom    1.0
        variable panx    0.0
        variable pany    0.0
        variable hbar    ""
        variable vbar    ""
        variable dragx   0
        variable dragy   0
        variable dragging 0
        variable opts
    }
    set ns ::tkmcairo::viewport::S_${w}
    array set ${ns}::opts [array get opts]

    # surface direkt im frame — viewport verwaltet Zoom/Pan selbst
    # (scrollutil::scrollarea ist nicht kompatibel mit ttk::label)
    tkmcairo::surface $w.surf \
        -width  $opts(-width) \
        -height $opts(-height) \
        -background $opts(-background) \
        -drawcommand [list ::tkmcairo::viewport::_drawentry $w]
    set ${ns}::surfpath $w.surf

    if {$opts(-scrollbars)} {
        # Scrollbalken erstellen
        ttk::scrollbar $w.vbar -orient vertical   -command [list ::tkmcairo::viewport::_vscroll $w]
        ttk::scrollbar $w.hbar -orient horizontal -command [list ::tkmcairo::viewport::_hscroll $w]
        set ${ns}::hbar $w.hbar
        set ${ns}::vbar $w.vbar

        grid $w.surf -row 0 -column 0 -sticky nsew
        grid $w.vbar -row 0 -column 1 -sticky ns
        grid $w.hbar -row 1 -column 0 -sticky ew
        grid columnconfigure $w 0 -weight 1
        grid rowconfigure    $w 0 -weight 1
    } else {
        pack $w.surf -fill both -expand 1
    }

    # Bindings: Mausrad = Zoom, Mitteltaste = Pan
    set surf [set ${ns}::surfpath]
    set surflbl $surf.lbl
    bind $surflbl <MouseWheel>      [list ::tkmcairo::viewport::_wheel $w %D %x %y]
    bind $surflbl <Button-4>        [list ::tkmcairo::viewport::_wheel $w  120 %x %y]
    bind $surflbl <Button-5>        [list ::tkmcairo::viewport::_wheel $w -120 %x %y]
    bind $surflbl <ButtonPress-2>   [list ::tkmcairo::viewport::_panStart $w %x %y]
    bind $surflbl <B2-Motion>       [list ::tkmcairo::viewport::_panMove  $w %x %y]
    bind $surflbl <ButtonRelease-2> [list set ::tkmcairo::viewport::S_${w}::dragging 0]
    # Linke Maustaste auch für Pan (optional)
    bind $surflbl <ButtonPress-1>   [list ::tkmcairo::viewport::_panStart $w %x %y]
    bind $surflbl <B1-Motion>       [list ::tkmcairo::viewport::_panMove  $w %x %y]
    bind $surflbl <ButtonRelease-1> [list set ::tkmcairo::viewport::S_${w}::dragging 0]

    bind $w <Destroy> [list namespace delete ::tkmcairo::viewport::S_${w}]

    # Initial redraw
    after idle [list catch [list ::tkmcairo::surface::_redraw [set ${ns}::surfpath]]]

    return $w
}

# ============================================================
# Drawcommand bridge
# ============================================================
proc ::tkmcairo::viewport::_drawentry {vp} {
    global ctx w h
    ::tkmcairo::viewport::_draw $vp $ctx $w $h
}

proc ::tkmcairo::viewport::_draw {vp ctx pw ph} {
    if {![namespace exists ::tkmcairo::viewport::S_${vp}]} return
    set ns ::tkmcairo::viewport::S_${vp}
    set cmd [set ${ns}::opts(-drawcommand)]
    if {$cmd eq ""} return

    set zoom [set ${ns}::zoom]
    set px   [set ${ns}::panx]
    set py   [set ${ns}::pany]

    # Transform anwenden: translate + scale
    $ctx push
    $ctx transform -translate $px $py
    $ctx transform -scale $zoom $zoom

    # Drawcommand aufrufen
    uplevel #0 [list set ctx $ctx]
    uplevel #0 [list set w   $pw]
    uplevel #0 [list set h   $ph]
    uplevel #0 [list set zoom $zoom]
    catch {uplevel #0 $cmd}

    $ctx pop
}

# ============================================================
# Widget-Command
# ============================================================
proc ::tkmcairo::viewport::_cmd {w subcmd args} {
    set ns ::tkmcairo::viewport::S_${w}
    switch -- $subcmd {
        zoom    {
            set factor [lindex $args 0]
            set cx [expr {[lindex $args 1] ne "" ? [lindex $args 1] : [winfo width  [set ${ns}::surfpath]]/2}]
            set cy [expr {[lindex $args 2] ne "" ? [lindex $args 2] : [winfo height [set ${ns}::surfpath]]/2}]
            _zoom $w $factor $cx $cy
        }
        zoomfit { _zoomfit $w }
        zoom1   {
            set ${ns}::zoom 1.0
            set ${ns}::panx 0.0
            set ${ns}::pany 0.0
            ::tkmcairo::surface::_redraw [set ${ns}::surfpath]
        }
        pan     { _pan $w [lindex $args 0] [lindex $args 1] }
        zoomlevel { set ${ns}::zoom }
        worldToScreen {
            set x [lindex $args 0]; set y [lindex $args 1]
            set z [set ${ns}::zoom]
            list [expr {$x * $z + [set ${ns}::panx]}] \
                 [expr {$y * $z + [set ${ns}::pany]}]
        }
        screenToWorld {
            set px [lindex $args 0]; set py [lindex $args 1]
            set z [set ${ns}::zoom]
            list [expr {($px - [set ${ns}::panx]) / $z}] \
                 [expr {($py - [set ${ns}::pany]) / $z}]
        }
        redraw  { ::tkmcairo::surface::_redraw [set ${ns}::surfpath] }
        export  { ::tkmcairo::surface::_export [set ${ns}::surfpath] {*}$args }
        configure {
            foreach {k v} $args {
                set ${ns}::opts($k) $v
            }
            ::tkmcairo::surface::_redraw [set ${ns}::surfpath]
        }
        cget    { set ${ns}::opts([lindex $args 0]) }
        destroy { destroy $w }
        default {
            set fc ::tkmcairo::viewport::_frame_[string map {. _ : _} $w]
            $fc $subcmd {*}$args
        }
    }
}

# ============================================================
# Zoom
# ============================================================
proc ::tkmcairo::viewport::_zoom {w factor cx cy} {
    set ns ::tkmcairo::viewport::S_${w}
    set zoom [set ${ns}::zoom]
    set newzoom [expr {$zoom * $factor}]
    set minz [set ${ns}::opts(-minzoom)]
    set maxz [set ${ns}::opts(-maxzoom)]
    if {$newzoom < $minz} { set newzoom $minz }
    if {$newzoom > $maxz} { set newzoom $maxz }

    # Pan so anpassen dass Bildschirmpunkt $cx/$cy stabil bleibt
    set px [set ${ns}::panx]
    set py [set ${ns}::pany]
    set ${ns}::panx [expr {$cx - ($cx - $px) * ($newzoom / $zoom)}]
    set ${ns}::pany [expr {$cy - ($cy - $py) * ($newzoom / $zoom)}]
    set ${ns}::zoom $newzoom

    ::tkmcairo::viewport::_updateScrollbars $w
    ::tkmcairo::surface::_redraw [set ${ns}::surfpath]
}

proc ::tkmcairo::viewport::_zoomfit {w} {
    set ns ::tkmcairo::viewport::S_${w}
    set surf [set ${ns}::surfpath]
    set sw [winfo width  $surf]
    set sh [winfo height $surf]
    if {$sw < 10} { set sw [set ${ns}::opts(-width)] }
    if {$sh < 10} { set sh [set ${ns}::opts(-height)] }
    set ww [set ${ns}::opts(-worldwidth)]
    set wh [set ${ns}::opts(-worldheight)]
    set zx [expr {$sw / double($ww)}]
    set zy [expr {$sh / double($wh)}]
    set ${ns}::zoom [expr {min($zx, $zy) * 0.95}]
    set ${ns}::panx 0.0
    set ${ns}::pany 0.0
    ::tkmcairo::viewport::_updateScrollbars $w
    ::tkmcairo::surface::_redraw $surf
}

# ============================================================
# Pan
# ============================================================
proc ::tkmcairo::viewport::_pan {w dx dy} {
    set ns ::tkmcairo::viewport::S_${w}
    set ${ns}::panx [expr {[set ${ns}::panx] + $dx}]
    set ${ns}::pany [expr {[set ${ns}::pany] + $dy}]
    ::tkmcairo::viewport::_updateScrollbars $w
    ::tkmcairo::surface::_redraw [set ${ns}::surfpath]
}

proc ::tkmcairo::viewport::_panStart {w x y} {
    set ns ::tkmcairo::viewport::S_${w}
    set ${ns}::dragx    $x
    set ${ns}::dragy    $y
    set ${ns}::dragging 1
}

proc ::tkmcairo::viewport::_panMove {w x y} {
    set ns ::tkmcairo::viewport::S_${w}
    if {![set ${ns}::dragging]} return
    set dx [expr {$x - [set ${ns}::dragx]}]
    set dy [expr {$y - [set ${ns}::dragy]}]
    set ${ns}::dragx $x
    set ${ns}::dragy $y
    _pan $w $dx $dy
}

proc ::tkmcairo::viewport::_wheel {w delta x y} {
    set factor [expr {$delta > 0 ? 1.15 : 0.87}]
    _zoom $w $factor $x $y
}

# ============================================================
# Scrollbar-Unterstützung
# ============================================================
proc ::tkmcairo::viewport::_updateScrollbars {w} {
    set ns ::tkmcairo::viewport::S_${w}
    set hbar [set ${ns}::hbar]
    set vbar [set ${ns}::vbar]
    if {$hbar eq "" || ![winfo exists $hbar]} return

    set surf [set ${ns}::surfpath]
    set sw   [winfo width  $surf]
    set sh   [winfo height $surf]
    if {$sw < 1 || $sh < 1} return

    set zoom [set ${ns}::zoom]
    set panx [set ${ns}::panx]
    set pany [set ${ns}::pany]
    set ww   [set ${ns}::opts(-worldwidth)]
    set wh   [set ${ns}::opts(-worldheight)]

    set totalW [expr {$ww * $zoom}]
    set totalH [expr {$wh * $zoom}]

    # Sichtbarer Anteil (0..1)
    set visW [expr {$totalW > 0 ? min(1.0, $sw / $totalW) : 1.0}]
    set visH [expr {$totalH > 0 ? min(1.0, $sh / $totalH) : 1.0}]

    # Position (0..1-vis)
    set posX [expr {$totalW > 0 ? -$panx / $totalW : 0.0}]
    set posY [expr {$totalH > 0 ? -$pany / $totalH : 0.0}]

    $hbar set $posX [expr {$posX + $visW}]
    $vbar set $posY [expr {$posY + $visH}]
}

proc ::tkmcairo::viewport::_hscroll {w cmd args} {
    set ns ::tkmcairo::viewport::S_${w}
    set surf [set ${ns}::surfpath]
    set zoom [set ${ns}::zoom]
    set ww   [set ${ns}::opts(-worldwidth)]
    set totalW [expr {$ww * $zoom}]
    set sw [winfo width $surf]

    set pos [expr {-[set ${ns}::panx] / $totalW}]
    set vis [expr {$totalW > 0 ? $sw / $totalW : 1.0}]

    switch $cmd {
        moveto { set pos [lindex $args 0] }
        scroll {
            set n    [lindex $args 0]
            set unit [lindex $args 1]
            set step [expr {$unit eq "pages" ? $vis : $vis * 0.1}]
            set pos  [expr {$pos + $n * $step}]
        }
    }
    set pos [expr {max(0.0, min($pos, 1.0 - $vis))}]
    set ${ns}::panx [expr {-$pos * $totalW}]
    ::tkmcairo::viewport::_updateScrollbars $w
    ::tkmcairo::surface::_redraw $surf
}

proc ::tkmcairo::viewport::_vscroll {w cmd args} {
    set ns ::tkmcairo::viewport::S_${w}
    set surf [set ${ns}::surfpath]
    set zoom [set ${ns}::zoom]
    set wh   [set ${ns}::opts(-worldheight)]
    set totalH [expr {$wh * $zoom}]
    set sh [winfo height $surf]

    set pos [expr {-[set ${ns}::pany] / $totalH}]
    set vis [expr {$totalH > 0 ? $sh / $totalH : 1.0}]

    switch $cmd {
        moveto { set pos [lindex $args 0] }
        scroll {
            set n    [lindex $args 0]
            set unit [lindex $args 1]
            set step [expr {$unit eq "pages" ? $vis : $vis * 0.1}]
            set pos  [expr {$pos + $n * $step}]
        }
    }
    set pos [expr {max(0.0, min($pos, 1.0 - $vis))}]
    set ${ns}::pany [expr {-$pos * $totalH}]
    ::tkmcairo::viewport::_updateScrollbars $w
    ::tkmcairo::surface::_redraw $surf
}
