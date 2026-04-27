# tkmcairo::legend 0.1
#
# Legende zeichnen mit tclmcairo.
#
# API:
#   tkmcairo::legend::draw $ctx $series ?options?
#
#   series = Liste von Dicts:  {name color ?type line|area|bar|scatter?}
#   Beispiel:
#     set series [list \
#         {name "Berlin" color {0.2 0.5 0.9} type line} \
#         {name "Wien"   color {0.9 0.4 0.2} type area}]
#
#   Optionen:
#     -x -y               Position (default: automatisch oben-rechts)
#     -position ne|nw|se|sw|right  (default: ne)
#     -font    fontspec   (default "Sans 10")
#     -bg      {r g b a}  Hintergrund (default {1 1 1 0.9})
#     -border  {r g b}    Rahmen (default {0.7 0.7 0.7})
#     -padding n          Innenabstand (default 6)
#     -itemh   n          Zeilenhöhe (default 20)
#     -swatchw n          Farb-Swatch Breite (default 18)
#     -pw -ph             Plot-Area Breite/Höhe für auto-position
#
# Part of tkmcairo — https://github.com/gregnix/tkmcairo
# License: BSD 2-Clause

package provide tkmcairo::legend 0.1.1

namespace eval ::tkmcairo::legend {}

proc ::tkmcairo::legend::draw {ctx series args} {
    if {[llength $series] == 0} return

    array set opts {
        -x       -1
        -y       -1
        -position ne
        -font    "Sans 10"
        -bg      {1 1 1 0.9}
        -border  {0.7 0.7 0.7}
        -padding 8
        -itemh   20
        -swatchw 18
        -pw      600
        -ph      400
    }
    foreach {k v} $args { set opts($k) $v }

    set pad    $opts(-padding)
    set itemh  $opts(-itemh)
    set sww    $opts(-swatchw)
    set n      [llength $series]

    # Breite: Swatch + Gap + längster Name
    set maxlen 0
    foreach s $series {
        if {[dict exists $s name]} {
            set len [string length [dict get $s name]]
            if {$len > $maxlen} { set maxlen $len }
        }
    }
    set lw [expr {$sww + 6 + $maxlen * 7 + $pad}]
    set lh [expr {$n * $itemh + 2 * $pad}]

    # Position berechnen
    if {$opts(-x) < 0 || $opts(-y) < 0} {
        switch $opts(-position) {
            ne      { set lx [expr {$opts(-pw) - $lw - 10}]; set ly 10 }
            nw      { set lx 10;                              set ly 10 }
            se      { set lx [expr {$opts(-pw) - $lw - 10}]
                      set ly [expr {$opts(-ph) - $lh - 10}] }
            sw      { set lx 10
                      set ly [expr {$opts(-ph) - $lh - 10}] }
            right   { set lx [expr {$opts(-pw) + 10}]
                      set ly [expr {($opts(-ph) - $lh) / 2.0}] }
            default { set lx [expr {$opts(-pw) - $lw - 10}]; set ly 10 }
        }
    } else {
        set lx $opts(-x)
        set ly $opts(-y)
    }

    # Hintergrund-Box
    lassign $opts(-bg) bgr bgg bgb bga
    $ctx rect $lx $ly $lw $lh \
        -fill [list $bgr $bgg $bgb $bga] \
        -stroke [list {*}$opts(-border) 1] \
        -width 0.8 -radius 4

    # Einträge
    set y [expr {$ly + $pad + $itemh/2.0}]
    foreach s $series {
        set name  [expr {[dict exists $s name]  ? [dict get $s name]  : ""}]
        set color [expr {[dict exists $s color] ? [dict get $s color] : {0.5 0.5 0.5}}]
        set type  [expr {[dict exists $s type]  ? [dict get $s type]  : "line"}]
        set alpha [expr {[dict exists $s alpha] ? [dict get $s alpha] : 1.0}]

        lassign $color cr cg cb

        # Farb-Swatch je nach Typ
        set sx [expr {$lx + $pad}]
        set sy [expr {$y - $itemh * 0.3}]
        set sh [expr {$itemh * 0.6}]

        switch $type {
            area {
                $ctx rect $sx $sy $sww $sh \
                    -fill [list $cr $cg $cb [expr {$alpha * 0.5}]] \
                    -stroke [list $cr $cg $cb $alpha] -width 1 -radius 2
            }
            bar {
                $ctx rect $sx $sy $sww $sh \
                    -fill [list $cr $cg $cb $alpha] \
                    -stroke [list [expr {$cr*0.7}] [expr {$cg*0.7}] [expr {$cb*0.7}] 1] \
                    -width 0.5 -radius 2
            }
            scatter {
                $ctx circle [expr {$sx + $sww/2.0}] $y 4 \
                    -fill [list $cr $cg $cb $alpha] \
                    -stroke {1 1 1 0.8} -width 1
            }
            default {
                # line
                $ctx line $sx $y [expr {$sx + $sww}] $y \
                    -color [list $cr $cg $cb $alpha] -width 2
                $ctx circle [expr {$sx + $sww/2.0}] $y 3 \
                    -fill [list $cr $cg $cb $alpha]
            }
        }

        # Name
        $ctx text [expr {$sx + $sww + 6}] $y $name \
            -font $opts(-font) -color {0.15 0.15 0.15} -anchor w

        set y [expr {$y + $itemh}]
    }
}
