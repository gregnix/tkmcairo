# tkmcairo::scene 0.1
#
# Retained-mode scene graph for tkmcairo.
# Manages a list of items with dirty flags.
# Renders only when something changed.
#
# API:
#   set s [tkmcairo::scene new $surface ?options?]
#
#   $s add type x1 y1 x2 y2 ?opts?  -> id
#     Types: rect oval line text image path circle
#     Options:
#       -fill    {r g b ?a?}    fill colour
#       -stroke  {r g b ?a?}    outline colour  (aliases: -outline -color)
#       -width   n              line width
#       -radius  n              corner radius (rect)
#       -text    string         text content
#       -font    fontspec       font
#       -anchor  center|w|e|n|s|nw|ne|sw|se
#       -dash    list           dash pattern
#       -alpha   0..1           overall opacity
#       -visible 0|1            visibility
#       -tags    taglist        tags for group operations
#
#   $s update id ?opts?          change properties -> dirty
#   $s delete id                 delete item
#   $s move   id dx dy           shift
#   $s moveto id x1 y1           absolute position
#   $s coords id ?x1 y1 x2 y2?   read / set coordinates
#
#   $s items ?-tag t?            list of all ids (optionally by tag)
#   $s type  id                  item type
#   $s cget  id option           read an option
#
#   $s hittest x y               topmost item at x/y -> id or ""
#   $s bbox   id                 bounding box {x1 y1 x2 y2}
#
#   $s raise  id                 to top of Z order
#   $s lower  id                 to bottom of Z order
#
#   $s bind  id event script     event binding (button motion enter leave)
#   $s unbind id event
#
#   $s render                    redraw (only if dirty)
#   $s forcerender               always redraw
#   $s background r g b ?a?      background colour
#
#   $s tag add    tag id...      set tags
#   $s tag remove tag id...
#   $s tag items  tag            items carrying a tag
#
#   $s destroy
#
# Part of tkmcairo — https://github.com/gregnix/tkmcairo
# License: BSD 2-Clause

package provide tkmcairo::scene 0.1

package require tkmcairo::surface

namespace eval ::tkmcairo::scene {}

# ============================================================
# Constructor
# ============================================================
proc ::tkmcairo::scene::new {surface args} {
    array set opts {
        -background {1 1 1 1}
    }
    foreach {k v} $args { set opts($k) $v }

    variable _count
    if {![info exists _count]} { set _count 0 }
    set id "::tkmcairo::scene::SC[incr _count]"

    namespace eval $id {
        variable items    {}    ;# ordered id list (Z order)
        variable data          ;# array: id -> dict
        variable nextid   0
        variable dirty    1
        variable bg       {1 1 1 1}
        variable surface  ""
        variable bindings      ;# array: id,event -> script
        variable tags          ;# array: tag -> {id ...}
        variable itemtags      ;# array: id -> {tag ...}
    }

    set ${id}::surface $surface
    set ${id}::bg      $opts(-background)

    # Drawcommand bridge — surface sets $ctx $w $h as globals
    set body "::tkmcairo::scene::_render [list $id] \$ctx \$w \$h"
    ::tkmcairo::surface::_configure $surface \
        -drawcommand $body

    # Event bindings on the surface
    set lbl ${surface}.lbl
    bind $lbl <ButtonPress-1>   [list ::tkmcairo::scene::_evButton $id %x %y 1]
    bind $lbl <ButtonRelease-1> [list ::tkmcairo::scene::_evButton $id %x %y 0]
    bind $lbl <Motion>          [list ::tkmcairo::scene::_evMotion $id %x %y]

    # Widget-Command
    set body "::tkmcairo::scene::_cmd [list $id] \$subcmd {*}\$args"
    proc $id {subcmd args} $body

    bind $surface <Destroy> [list namespace delete $id]

    return $id
}

# ============================================================
# Dispatcher
# ============================================================
proc ::tkmcairo::scene::_cmd {id subcmd args} {
    switch -- $subcmd {
        add       { _add    $id {*}$args }
        update    { _update $id {*}$args }
        delete    { _delete $id [lindex $args 0] }
        move      { _move   $id [lindex $args 0] [lindex $args 1] [lindex $args 2] }
        moveto    { _moveto $id [lindex $args 0] [lindex $args 1] [lindex $args 2] }
        coords    { _coords $id {*}$args }
        items     { _items  $id {*}$args }
        type      { dict get [set ${id}::data([lindex $args 0])] type }
        cget      { dict get [set ${id}::data([lindex $args 0])] [lindex $args 1] }
        hittest   { _hittest $id [lindex $args 0] [lindex $args 1] }
        bbox      { _bbox   $id [lindex $args 0] }
        raise     { _raise  $id [lindex $args 0] }
        lower     { _lower  $id [lindex $args 0] }
        bind      { _bind   $id [lindex $args 0] [lindex $args 1] [lindex $args 2] }
        unbind    { _unbind $id [lindex $args 0] [lindex $args 1] }
        render       { if {[set ${id}::dirty]} { ::tkmcairo::surface::_redraw [set ${id}::surface] } }
        forcerender  { ::tkmcairo::surface::_redraw [set ${id}::surface] }
        background   { set ${id}::bg $args; set ${id}::dirty 1
                       ::tkmcairo::surface::_redraw [set ${id}::surface] }
        tag       { _tag $id {*}$args }
        destroy   {
            namespace delete $id
            rename $id {}
        }
        default   { error "tkmcairo::scene: unknown subcommand: $subcmd" }
    }
}

# ============================================================
# Items verwalten
# ============================================================
proc ::tkmcairo::scene::_add {id type x1 y1 args2 args} {
    # circle/oval: support both cx cy r and x1 y1 x2 y2 conventions
    if {$type in {circle oval}} {
        # If args2 is a number and next arg is also number -> x1 y1 x2 y2
        # If args2 is a number and next arg starts with - -> cx cy r
        if {[string is double $args2] &&
            ([llength $args] == 0 || [string match "-*" [lindex $args 0]])} {
            # cx cy r style
            set r $args2
            set x2 [expr {$x1 + $r}]; set y2 [expr {$y1 + $r}]
            set x1 [expr {$x1 - $r}]; set y1 [expr {$y1 - $r}]
        } else {
            set x2 $args2
            set y2 [lindex $args 0]
            set args [lrange $args 1 end]
        }
    } else {
        set x2 $args2
        set y2 [lindex $args 0]
        set args [lrange $args 1 end]
    }
    set iid [incr ${id}::nextid]
    set item [dict create \
        type $type  x1 $x1 y1 $y1 x2 $x2 y2 $y2 \
        fill "" stroke "" width 1 radius 0 \
        text "" font "Sans 12" anchor center \
        dash {} alpha 1.0 visible 1 tags {}]
    foreach {k v} $args {
        dict set item $k $v
    }
    # -outline / -color aliases
    if {[dict exists $item -outline]} {
        dict set item stroke [dict get $item -outline]
        dict unset item -outline
    }
    if {[dict exists $item -color] && [dict get $item stroke] eq ""} {
        dict set item stroke [dict get $item -color]
    }

    set ${id}::data($iid) $item
    lappend ${id}::items $iid
    set ${id}::dirty 1
    return $iid
}

proc ::tkmcairo::scene::_update {id iid args} {
    if {![info exists ${id}::data($iid)]} return
    set item [set ${id}::data($iid)]
    foreach {k v} $args {
        dict set item $k $v
    }
    set ${id}::data($iid) $item
    set ${id}::dirty 1
}

proc ::tkmcairo::scene::_delete {id iid} {
    if {![info exists ${id}::data($iid)]} return
    unset ${id}::data($iid)
    set ${id}::items [lsearch -all -inline -not [set ${id}::items] $iid]
    set ${id}::dirty 1
}

proc ::tkmcairo::scene::_move {id iid dx dy} {
    if {![info exists ${id}::data($iid)]} return
    set item [set ${id}::data($iid)]
    dict set item x1 [expr {[dict get $item x1] + $dx}]
    dict set item y1 [expr {[dict get $item y1] + $dy}]
    dict set item x2 [expr {[dict get $item x2] + $dx}]
    dict set item y2 [expr {[dict get $item y2] + $dy}]
    set ${id}::data($iid) $item
    set ${id}::dirty 1
}

proc ::tkmcairo::scene::_moveto {id iid x1 y1} {
    if {![info exists ${id}::data($iid)]} return
    set item [set ${id}::data($iid)]
    set dx [expr {$x1 - [dict get $item x1]}]
    set dy [expr {$y1 - [dict get $item y1]}]
    _move $id $iid $dx $dy
}

proc ::tkmcairo::scene::_coords {id iid args} {
    if {![info exists ${id}::data($iid)]} return
    set item [set ${id}::data($iid)]
    if {[llength $args] == 0} {
        return [list [dict get $item x1] [dict get $item y1] \
                     [dict get $item x2] [dict get $item y2]]
    }
    lassign $args x1 y1 x2 y2
    dict set item x1 $x1; dict set item y1 $y1
    dict set item x2 $x2; dict set item y2 $y2
    set ${id}::data($iid) $item
    set ${id}::dirty 1
}

proc ::tkmcairo::scene::_items {id args} {
    if {[llength $args] >= 2 && [lindex $args 0] eq "-tag"} {
        set tag [lindex $args 1]
        if {[info exists ${id}::tags($tag)]} {
            return [set ${id}::tags($tag)]
        }
        return {}
    }
    return [set ${id}::items]
}

# ============================================================
# Rendering
# ============================================================
proc ::tkmcairo::scene::_render {id ctx w h} {
    set ${id}::dirty 0

    # Hintergrund
    lassign [set ${id}::bg] r g b a
    if {$a eq ""} { set a 1 }
    $ctx clear $r $g $b $a

    # Items in Z-Order
    foreach iid [set ${id}::items] {
        if {![info exists ${id}::data($iid)]} continue
        set item [set ${id}::data($iid)]
        if {![dict get $item visible]} continue
        _renderItem $ctx $item
    }
}

proc ::tkmcairo::scene::_renderItem {ctx item} {
    set type   [dict get $item type]
    set x1     [dict get $item x1]
    set y1     [dict get $item y1]
    set x2     [dict get $item x2]
    set y2     [dict get $item y2]
    set fill   [expr {[dict exists $item -fill]   ? [dict get $item -fill]   : [dict get $item fill]}]
    set stroke [expr {[dict exists $item -stroke] ? [dict get $item -stroke] : [dict exists $item -outline] ? [dict get $item -outline] : [dict get $item stroke]}]
    set lw     [expr {[dict exists $item -width]  ? [dict get $item -width]  : [dict get $item width]}]
    set alpha  [expr {[dict exists $item -alpha]  ? [dict get $item -alpha]  : [dict get $item alpha]}]

    # Alpha auf Farben anwenden
    set fopts {}
    set sopts {}
    if {$fill ne ""} {
        # Only append alpha if not already present (3 elements = rgb, 4 = rgba)
        set f $fill
        if {[llength $f] == 3} { lappend f $alpha }
        lappend fopts -fill $f
    }
    if {$stroke ne ""} {
        set s $stroke
        if {[llength $s] == 3} { lappend s $alpha }
        lappend sopts -stroke $s -width $lw
    }
    set dopts [concat $fopts $sopts]

    set dash   [expr {[dict exists $item -dash]   ? [dict get $item -dash]   : [dict get $item dash]}]
    if {$dash ne {}} { lappend dopts -dash $dash }

    switch $type {
        rect {
            set rx [dict get $item radius]
            $ctx rect $x1 $y1 [expr {$x2-$x1}] [expr {$y2-$y1}] \
                {*}$dopts -radius $rx
        }
        oval - circle {
            set cx [expr {($x1+$x2)/2.0}]
            set cy [expr {($y1+$y2)/2.0}]
            set rw [expr {abs($x2-$x1)/2.0}]
            set rh [expr {abs($y2-$y1)/2.0}]
            if {abs($rw-$rh) < 0.5} {
                $ctx circle $cx $cy $rw {*}$dopts
            } else {
                $ctx ellipse $cx $cy $rw $rh {*}$dopts
            }
        }
        line {
            set copts {}
            if {$stroke ne ""} { lappend copts -color $stroke }
            lappend copts -width $lw
            if {$dash ne {}} { lappend copts -dash $dash }
            $ctx line $x1 $y1 $x2 $y2 {*}$copts
        }
        text {
            set txt  [dict get $item text]
            set font [dict get $item font]
            set anc  [dict get $item anchor]
            set col  [expr {$stroke ne "" ? $stroke : {0 0 0}}]
            if {[llength $col] == 3} { lappend col $alpha }
            $ctx text $x1 $y1 $txt \
                -font $font -color $col -anchor $anc
        }
        image {
            set fname [dict get $item text]  ;# text field holds filename
            if {$fname ne "" && [file exists $fname]} {
                set iw [expr {$x2-$x1}]; set ih [expr {$y2-$y1}]
                $ctx image $fname $x1 $y1 -width $iw -height $ih -alpha $alpha
            }
        }
        path {
            set pdata [dict get $item text]  ;# text field holds SVG path
            if {$pdata ne ""} {
                $ctx path $pdata {*}$dopts
            }
        }
    }
}

# ============================================================
# Hit-Testing (einfach: bounding box)
# ============================================================
proc ::tkmcairo::scene::_hittest {id px py} {
    # Iterate Z-order from top to bottom (topmost first)
    foreach iid [lreverse [set ${id}::items]] {
        if {![info exists ${id}::data($iid)]} continue
        set item [set ${id}::data($iid)]
        if {![dict get $item visible]} continue
        set x1 [dict get $item x1]; set y1 [dict get $item y1]
        set x2 [dict get $item x2]; set y2 [dict get $item y2]
        if {$px >= $x1 && $px <= $x2 && $py >= $y1 && $py <= $y2} {
            return $iid
        }
    }
    return ""
}

proc ::tkmcairo::scene::_bbox {id iid} {
    if {![info exists ${id}::data($iid)]} return {}
    set item [set ${id}::data($iid)]
    list [dict get $item x1] [dict get $item y1] \
         [dict get $item x2] [dict get $item y2]
}

# ============================================================
# Z-Order
# ============================================================
proc ::tkmcairo::scene::_raise {id iid} {
    set items [set ${id}::items]
    set items [lsearch -all -inline -not $items $iid]
    lappend items $iid
    set ${id}::items $items
    set ${id}::dirty 1
}

proc ::tkmcairo::scene::_lower {id iid} {
    set items [set ${id}::items]
    set items [lsearch -all -inline -not $items $iid]
    set ${id}::items [linsert $items 0 $iid]
    set ${id}::dirty 1
}

# ============================================================
# Bindings
# ============================================================
proc ::tkmcairo::scene::_bind {id iid event script} {
    set ${id}::bindings($iid,$event) $script
}

proc ::tkmcairo::scene::_unbind {id iid event} {
    catch { unset ${id}::bindings($iid,$event) }
}

proc ::tkmcairo::scene::_evButton {id x y press} {
    set iid [_hittest $id $x $y]
    if {$iid eq ""} return
    set ev [expr {$press ? "button" : "release"}]
    if {[info exists ${id}::bindings($iid,$ev)]} {
        set script [set ${id}::bindings($iid,$ev)]
        set script [string map [list %i $iid %x $x %y $y] $script]
        uplevel #0 $script
    }
}

proc ::tkmcairo::scene::_evMotion {id x y} {
    set iid [_hittest $id $x $y]
    if {$iid eq ""} return
    if {[info exists ${id}::bindings($iid,motion)]} {
        set script [set ${id}::bindings($iid,motion)]
        set script [string map [list %i $iid %x $x %y $y] $script]
        uplevel #0 $script
    }
}

# ============================================================
# Tags
# ============================================================
proc ::tkmcairo::scene::_tag {id subcmd args} {
    switch $subcmd {
        add {
            set tag [lindex $args 0]
            foreach iid [lrange $args 1 end] {
                if {![info exists ${id}::tags($tag)]} {
                    set ${id}::tags($tag) {}
                }
                if {$iid ni [set ${id}::tags($tag)]} {
                    lappend ${id}::tags($tag) $iid
                }
            }
        }
        remove {
            set tag [lindex $args 0]
            foreach iid [lrange $args 1 end] {
                if {[info exists ${id}::tags($tag)]} {
                    set ${id}::tags($tag) \
                        [lsearch -all -inline -not [set ${id}::tags($tag)] $iid]
                }
            }
        }
        items {
            set tag [lindex $args 0]
            if {[info exists ${id}::tags($tag)]} {
                return [set ${id}::tags($tag)]
            }
            return {}
        }
    }
}
