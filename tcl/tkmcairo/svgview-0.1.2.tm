# tkmcairo::svgview 0.1.2
#
# SVG-Viewer Widget — zeigt SVG-Dateien via tcllunasvg oder svg2cairo.
# Unterstützt Zoom, Pan, Export.
#
# API:
#   tkmcairo::svgview pathName ?options?
#
#   Options:
#     -width  n          Breite in Pixeln (default 600)
#     -height n          Höhe in Pixeln (default 400)
#     -file   filename   SVG-Datei (optional, auch später via load)
#     -background {r g b}  Hintergrundfarbe (default {1 1 1})
#     -renderer auto|luna|svg2cairo
#                        auto: tcllunasvg wenn verfügbar, sonst svg2cairo
#                        luna: tcllunasvg explizit (Paket muss installiert sein)
#
#   Widget-Commands:
#     $sv load filename   SVG-Datei laden
#     $sv reload          Aktuelle Datei neu laden
#     $sv zoom factor     Zoom-Faktor multiplizieren
#     $sv zoomfit         An Fenstergröße anpassen
#     $sv zoom1           1:1 Originalgröße
#     $sv pan dx dy       Verschieben
#     $sv file            Aktueller Dateiname
#     $sv svgsize         SVG-Originalgröße {w h}
#     $sv export filename                     save to file (format from extension)
#     $sv export -chan $ch -format fmt        stream to channel (PNG/PDF/SVG/PS/EPS)
#     $sv redraw
#     $sv configure ...
#     $sv cget option
#     $sv destroy
#
# Requirements:
#   - tkmcairo::surface, tclmcairo 0.4.0+
#   - optional: tcllunasvg 0.1.0+ (für -renderer luna / auto-Bevorzugung)
#   - optional: svg2cairo + tdom (Fallback-Renderer)
#
# Migration 0.1.1 -> 0.1.2:
#   tclmcairo 0.4.0 hat die internen svg_*_luna-Befehle entfernt. Das Widget
#   ruft jetzt tcllunasvg::load direkt auf und nutzt image_from_argb32 zum
#   Einblenden in den Cairo-Kontext.
#
# Part of tkmcairo — https://github.com/gregnix/tkmcairo
# License: BSD 2-Clause

package provide tkmcairo::svgview 0.1.2

package require Tk
package require tclmcairo
package require tkmcairo::surface

namespace eval ::tkmcairo::svgview {}

# ============================================================
# Konstruktor
# ============================================================
proc ::tkmcairo::svgview {w args} {
    array set opts {
        -width      600
        -height     400
        -file       ""
        -background {1 1 1}
        -renderer   auto
    }
    foreach {k v} $args { set opts($k) $v }

    # Renderer ermitteln
    set renderer [::tkmcairo::svgview::_detectRenderer $opts(-renderer)]

    # Surface Widget
    tkmcairo::surface $w \
        -width      $opts(-width) \
        -height     $opts(-height) \
        -background $opts(-background) \
        -drawcommand "::tkmcairo::svgview::_draw [list $w] \$ctx \$w \$h"

    # State
    namespace eval ::tkmcairo::svgview::S_$w {
        variable file     ""
        variable svgW     0
        variable svgH     0
        variable zoom     1.0
        variable panX     0.0
        variable panY     0.0
        variable dragging 0
        variable dragX    0
        variable dragY    0
        variable renderer ""
        variable redrawJob ""
    }
    set ns ::tkmcairo::svgview::S_${w}
    set ${ns}::renderer $renderer

    # Widget-Command installieren
    interp alias {} $w {} ::tkmcairo::svgview::_cmd $w
    bind $w <Destroy> [list namespace delete ::tkmcairo::svgview::S_${w}]

    # Mouse-Bindings
    bind $w.lbl <ButtonPress-1>   [list ::tkmcairo::svgview::_dragStart $w %x %y]
    bind $w.lbl <B1-Motion>       [list ::tkmcairo::svgview::_dragMotion $w %x %y]
    bind $w.lbl <ButtonRelease-1> [list set ::tkmcairo::svgview::S_${w}::dragging 0]
    bind $w.lbl <MouseWheel>      [list ::tkmcairo::svgview::_wheelZoom $w %D %x %y]
    bind $w.lbl <Button-4>        [list ::tkmcairo::svgview::_wheelZoom $w  120 %x %y]
    bind $w.lbl <Button-5>        [list ::tkmcairo::svgview::_wheelZoom $w -120 %x %y]

    # Initiale Datei laden
    if {$opts(-file) ne ""} {
        ::tkmcairo::svgview::_load $w $opts(-file)
    }

    return $w
}

# ============================================================
# Renderer-Erkennung
# ============================================================
proc ::tkmcairo::svgview::_detectRenderer {pref} {
    if {$pref eq "luna"} { return luna }
    if {$pref eq "svg2cairo"} { return svg2cairo }
    if {$pref eq "nanosvg"}   { return nanosvg }
    # auto: tcllunasvg testen (Paket-Check, kein Probe-Aufruf nötig)
    if {![catch {package require tcllunasvg}]} { return luna }
    # Fallback: svg2cairo
    if {![catch {package require svg2cairo}]} { return svg2cairo }
    return nanosvg
}

# ============================================================
# Widget-Command Dispatcher
# ============================================================
proc ::tkmcairo::svgview::_cmd {w subcmd args} {
    set ns ::tkmcairo::svgview::S_${w}
    switch -- $subcmd {
        load      { _load $w {*}$args }
        reload    {
            set f [set ${ns}::file]
            if {$f ne ""} { _load $w $f }
        }
        zoom      { _zoom $w {*}$args }
        zoomfit   { _zoomfit $w }
        zoom1     {
            set ${ns}::zoom 1.0
            set ${ns}::panX 0.0
            set ${ns}::panY 0.0
            ::tkmcairo::surface::_redraw $w
        }
        pan       {
            lassign $args dx dy
            set ${ns}::panX [expr {[set ${ns}::panX] + $dx}]
            set ${ns}::panY [expr {[set ${ns}::panY] + $dy}]
            ::tkmcairo::surface::_redraw $w
        }
        file      { return [set ${ns}::file] }
        svgsize   { return [list [set ${ns}::svgW] [set ${ns}::svgH]] }
        renderer  { return [set ${ns}::renderer] }
        export    { ::tkmcairo::surface::_export $w {*}$args }
        redraw    { ::tkmcairo::surface::_redraw $w }
        configure {
            foreach {k v} $args {
                switch $k {
                    -file       { _load $w $v }
                    -renderer   { set ${ns}::renderer [::tkmcairo::svgview::_detectRenderer $v] }
                    -width - -height - -background {
                        ::tkmcairo::surface::_configure $w $k $v
                    }
                }
            }
        }
        cget      { return [::tkmcairo::surface::_cmd $w cget {*}$args] }
        destroy   { destroy $w }
        default   { ::tkmcairo::surface::_cmd $w $subcmd {*}$args }
    }
    return ""
}

# ============================================================
# Laden
# ============================================================
proc ::tkmcairo::svgview::_load {w file} {
    set ns ::tkmcairo::svgview::S_${w}
    if {![file exists $file]} {
        tk_messageBox -message "File not found: $file" -type ok -icon error
        return
    }
    set ${ns}::file $file

    # SVG-Größe ermitteln
    set r [set ${ns}::renderer]
    set sw 0; set sh 0
    if {$r eq "luna"} {
        # tcllunasvg liefert size direkt aus dem geladenen Dokument
        if {![catch {package require tcllunasvg}]} {
            if {![catch {tcllunasvg::load file $file} doc]} {
                catch {lassign [$doc size] sw sh}
                catch {$doc destroy}
            }
        }
    }
    if {($sw == 0 || $sh == 0)} {
        if {![catch {package require svg2cairo}]} {
            catch {lassign [svg2cairo::size $file] sw sh}
        }
    }
    if {$sw == 0 || $sh == 0} { set sw 400; set sh 300 }

    set ${ns}::svgW $sw
    set ${ns}::svgH $sh
    set ${ns}::panX 0.0
    set ${ns}::panY 0.0

    _zoomfit $w
}

# ============================================================
# Zoom
# ============================================================
proc ::tkmcairo::svgview::_zoom {w factor {cx -1} {cy -1}} {
    set ns ::tkmcairo::svgview::S_${w}
    set oldz [set ${ns}::zoom]
    set newz [expr {max(0.05, min(20.0, $oldz * $factor))}]
    set ${ns}::zoom $newz

    # Zoom um Cursor-Punkt
    if {$cx >= 0 && $cy >= 0} {
        set sw [winfo width  $w]
        set sh [winfo height $w]
        set svgW [set ${ns}::svgW]
        set svgH [set ${ns}::svgH]
        set px [set ${ns}::panX]
        set py [set ${ns}::panY]
        set ox [expr {($sw - $svgW * $oldz) / 2.0 + $px}]
        set oy [expr {($sh - $svgH * $oldz) / 2.0 + $py}]
        set wx [expr {($cx - $ox) / $oldz}]
        set wy [expr {($cy - $oy) / $oldz}]
        set ${ns}::panX [expr {$cx - $wx * $newz - ($sw - $svgW * $newz) / 2.0}]
        set ${ns}::panY [expr {$cy - $wy * $newz - ($sh - $svgH * $newz) / 2.0}]
    }
    ::tkmcairo::surface::_redraw $w
}

proc ::tkmcairo::svgview::_zoomfit {w} {
    set ns ::tkmcairo::svgview::S_${w}
    set sw [winfo width  $w]
    set sh [winfo height $w]
    if {$sw < 10} { set sw [set [array get [set ${ns}::opts] -width]] }
    set svgW [set ${ns}::svgW]
    set svgH [set ${ns}::svgH]
    if {$svgW <= 0 || $svgH <= 0} return
    if {$sw < 10} { set sw 600 }
    if {$sh < 10} { set sh 400 }
    set zw [expr {($sw - 10) / double($svgW)}]
    set zh [expr {($sh - 10) / double($svgH)}]
    set ${ns}::zoom [expr {min($zw, $zh, 4.0)}]
    set ${ns}::panX 0.0
    set ${ns}::panY 0.0
    ::tkmcairo::surface::_redraw $w
}

# ============================================================
# Draw
# ============================================================
proc ::tkmcairo::svgview::_draw {plotw ctx pw ph} {
    set ns ::tkmcairo::svgview::S_${plotw}
    if {![namespace exists $ns]} return

    set file [set ${ns}::file]
    set svgW [set ${ns}::svgW]
    set svgH [set ${ns}::svgH]
    set z    [set ${ns}::zoom]
    set panX [set ${ns}::panX]
    set panY [set ${ns}::panY]
    set r    [set ${ns}::renderer]

    if {$file eq ""} {
        $ctx text [expr {$pw/2.0}] [expr {$ph/2.0}] \
            "Drop SVG file here or use \$sv load" \
            -font "Sans 16" -color {0.5 0.5 0.5} -anchor center
        return
    }

    # Position: zentriert + Pan
    set dw [expr {int($svgW * $z)}]
    set dh [expr {int($svgH * $z)}]
    set x  [expr {int(($pw - $dw) / 2.0 + $panX)}]
    set y  [expr {int(($ph - $dh) / 2.0 + $panY)}]

    if {$dw < 1} { set dw 1 }
    if {$dh < 1} { set dh 1 }

    # SVG rendern
    switch $r {
        luna {
            # Render-Pipeline: tcllunasvg -> ARGB32 -> tclmcairo image_from_argb32 -> image_blit
            set ok 0
            if {![catch {package require tcllunasvg}]} {
                if {![catch {
                    set doc [tcllunasvg::load file $file]
                    set pix [$doc to_argb32 -width $dw -height $dh]
                    $doc destroy
                    set img [$ctx image_from_argb32 \
                        [dict get $pix data] \
                        [dict get $pix width] \
                        [dict get $pix height] \
                        [dict get $pix stride]]
                    $ctx image_blit $img $x $y
                    $ctx image_free $img
                    set ok 1
                } err]} {
                    # Aufräumen falls Dokument noch lebt
                    catch {$doc destroy}
                }
            }
            if {!$ok} {
                # Fallback wie früher
                if {![catch {package require svg2cairo}]} {
                    $ctx push
                    $ctx transform -translate $x $y
                    svg2cairo::render $ctx $file -scale $z
                    $ctx pop
                } else {
                    $ctx svg_file $file $x $y -width $dw -height $dh
                }
            }
        }
        svg2cairo {
            if {![catch {package require svg2cairo}]} {
                $ctx push
                $ctx transform -translate $x $y
                svg2cairo::render $ctx $file -scale $z
                $ctx pop
            } else {
                $ctx svg_file $file $x $y -width $dw -height $dh
            }
        }
        default {
            $ctx svg_file $file $x $y -width $dw -height $dh
        }
    }

    # Info-Overlay
    set info [format "%s  |  %.0f × %.0f  |  %.0f%%" \
        [file tail $file] $svgW $svgH [expr {$z * 100}]]
    set bw [expr {[string length $info] * 7 + 16}]
    $ctx rect 6 [expr {$ph-28}] $bw 20 \
        -fill {0 0 0 0.5} -radius 3
    $ctx text 14 [expr {$ph-14}] $info \
        -font "Sans 10" -color {0.95 0.95 0.95} -anchor w
}

# ============================================================
# Mouse-Interaktion
# ============================================================
proc ::tkmcairo::svgview::_dragStart {w x y} {
    set ns ::tkmcairo::svgview::S_${w}
    set ${ns}::dragging 1
    set ${ns}::dragX    $x
    set ${ns}::dragY    $y
}

proc ::tkmcairo::svgview::_dragMotion {w x y} {
    set ns ::tkmcairo::svgview::S_${w}
    if {![set ${ns}::dragging]} return
    set ${ns}::panX [expr {[set ${ns}::panX] + ($x - [set ${ns}::dragX])}]
    set ${ns}::panY [expr {[set ${ns}::panY] + ($y - [set ${ns}::dragY])}]
    set ${ns}::dragX $x
    set ${ns}::dragY $y
    after cancel [set ${ns}::redrawJob]
    set ${ns}::redrawJob [after 30 [list ::tkmcairo::surface::_redraw $w]]
}

proc ::tkmcairo::svgview::_wheelZoom {w delta x y} {
    set factor [expr {$delta > 0 ? 1.15 : 0.87}]
    _zoom $w $factor $x $y
}
