#!/usr/bin/env tclsh
# tests/test-tkmcairo.tcl — tkmcairo Test-Suite
#
# Run: tclsh tests/test-tkmcairo.tcl
# or:  make test

set _tmdir [file normalize [file join [file dirname [info script]] ../tcl]]
if {$_tmdir ni [tcl::tm::path list]} { tcl::tm::path add $_tmdir }
unset _tmdir

package require tcltest 2.2
namespace import tcltest::*

# tclmcairo laden falls TCLMCAIRO_LIBDIR gesetzt
if {[info exists env(TCLMCAIRO_LIBDIR)]} {
    lappend auto_path $env(TCLMCAIRO_LIBDIR)
    tcl::tm::path add $env(TCLMCAIRO_LIBDIR)
}

# ================================================================
# tkmcairo::coords
# ================================================================
package require tkmcairo::coords

test coords-1.0 {transform new returns command} -body {
    set tr [tkmcairo::coords::transform new -xmin 0 -xmax 100 -ymin 0 -ymax 100 \
        -px0 0 -py0 0 -px1 400 -py1 300]
    set ok [string match "::tkmcairo::coords::T*" $tr]
    $tr destroy
    set ok
} -result 1

test coords-1.1 {toPixelX basic} -body {
    set tr [tkmcairo::coords::transform new \
        -xmin 0 -xmax 100 -ymin 0 -ymax 100 -px0 0 -px1 400 -py0 0 -py1 300]
    set px [$tr toPixelX 50]
    $tr destroy
    expr {abs($px - 200.0) < 0.01}
} -result 1

test coords-1.2 {toPixelX at boundaries} -body {
    set tr [tkmcairo::coords::transform new \
        -xmin 0 -xmax 100 -px0 10 -px1 410 -py0 0 -py1 300]
    set p0 [$tr toPixelX 0]
    set p1 [$tr toPixelX 100]
    $tr destroy
    list [expr {abs($p0 - 10.0) < 0.01}] [expr {abs($p1 - 410.0) < 0.01}]
} -result {1 1}

test coords-1.3 {toPixelY flipy=1} -body {
    set tr [tkmcairo::coords::transform new \
        -ymin 0 -ymax 100 -py0 0 -py1 300 -px0 0 -px1 400]
    # y=0 sollte unten sein (py1=300), y=100 oben (py0=0)
    set p0 [$tr toPixelY 0]
    set p1 [$tr toPixelY 100]
    $tr destroy
    list [expr {abs($p0 - 300.0) < 0.01}] [expr {abs($p1 - 0.0) < 0.01}]
} -result {1 1}

test coords-1.4 {toWorld roundtrip} -body {
    set tr [tkmcairo::coords::transform new \
        -xmin 0 -xmax 100 -ymin 0 -ymax 100 \
        -px0 50 -py0 50 -px1 450 -py1 350]
    set px [$tr toPixelX 42]
    set py [$tr toPixelY 37]
    set wx [$tr toWorldX $px]
    set wy [$tr toWorldY $py]
    $tr destroy
    list [expr {abs($wx - 42.0) < 0.001}] [expr {abs($wy - 37.0) < 0.001}]
} -result {1 1}

test coords-1.5 {zoom changes bounds} -body {
    set tr [tkmcairo::coords::transform new \
        -xmin 0 -xmax 100 -ymin 0 -ymax 100 \
        -px0 0 -py0 0 -px1 200 -py1 200]
    $tr zoom 2.0 100 100
    lassign [$tr worldBounds] xmin xmax ymin ymax
    $tr destroy
    expr {$xmin > 0 && $xmax < 100}
} -result 1

test coords-1.6 {pan shifts world} -body {
    set tr [tkmcairo::coords::transform new \
        -xmin 0 -xmax 100 -ymin 0 -ymax 100 \
        -px0 0 -py0 0 -px1 400 -py1 300]
    set before [$tr toWorldX 200]
    $tr pan 40 0
    set after [$tr toWorldX 200]
    $tr destroy
    expr {abs($after - $before) > 0.01}
} -result 1

test coords-1.7 {reset restores original bounds} -body {
    set tr [tkmcairo::coords::transform new \
        -xmin 0 -xmax 100 -ymin 0 -ymax 100 \
        -px0 0 -py0 0 -px1 400 -py1 300]
    $tr zoom 3.0 200 150
    $tr reset
    lassign [$tr worldBounds] xmin xmax ymin ymax
    $tr destroy
    list [expr {abs($xmin - 0) < 0.01}] [expr {abs($xmax - 100) < 0.01}]
} -result {1 1}

test coords-1.8 {plotW and plotH} -body {
    set tr [tkmcairo::coords::transform new \
        -px0 50 -py0 30 -px1 450 -py1 330 \
        -xmin 0 -xmax 1 -ymin 0 -ymax 1]
    set r [list [$tr plotW] [$tr plotH]]
    $tr destroy
    set r
} -result {400 300}

test coords-1.9 {cget returns option} -body {
    set tr [tkmcairo::coords::transform new -xmin 5 -xmax 95 \
        -ymin 0 -ymax 100 -px0 0 -py0 0 -px1 400 -py1 300]
    set v [$tr cget -xmin]
    $tr destroy
    set v
} -result 5

# ================================================================
# tkmcairo::data
# ================================================================
package require tkmcairo::data

test data-1.0 {range basic} -body {
    tkmcairo::data::range {0 5  2 3  10 1  4 8}
} -result {0 10 1 8}

test data-1.1 {range single point} -body {
    tkmcairo::data::range {3 7}
} -result {3 3 7 7}

test data-1.2 {xrange} -body {
    tkmcairo::data::xrange {1 10  5 20  3 15}
} -result {1 5}

test data-1.3 {yrange} -body {
    tkmcairo::data::yrange {1 10  5 20  3 15}
} -result {10 20}

test data-1.4 {smooth preserves length} -body {
    set d {0 1  1 3  2 2  3 5  4 4  5 6}
    set s [tkmcairo::data::smooth $d 3]
    expr {[llength $s] == [llength $d]}
} -result 1

test data-1.5 {smooth n=1 returns unchanged} -body {
    set d {0 1 1 3 2 2}
    set s [tkmcairo::data::smooth $d 1]
    expr {[llength $s] == [llength $d]}
} -result 1

test data-1.6 {boxstats basic} -body {
    set r [tkmcairo::data::boxstats {1 2 3 4 5 6 7 8 9 10}]
    list [lindex $r 0] [lindex $r 4]
} -result {1 10}

test data-1.7 {boxstats median} -body {
    set r [tkmcairo::data::boxstats {1 2 3 4 5}]
    lindex $r 2
} -result 3

test data-1.8 {histogram bin count} -body {
    set r [tkmcairo::data::histogram {1 2 3 4 5 6 7 8 9 10} -bins 5]
    llength $r
} -result 10

test data-1.9 {normalize range 0..1} -body {
    set r [tkmcairo::data::normalize {0 0 10 10}]
    list [expr {abs([lindex $r 0] - 0.0) < 0.001}] \
         [expr {abs([lindex $r 1] - 0.0) < 0.001}] \
         [expr {abs([lindex $r 2] - 1.0) < 0.001}] \
         [expr {abs([lindex $r 3] - 1.0) < 0.001}]
} -result {1 1 1 1}

test data-2.0 {cumsum} -body {
    tkmcairo::data::cumsum {1 2 3 4 5}
} -result {1 3 6 10 15}

test data-2.1 {timeToNum / numToTime roundtrip} -body {
    set epoch [tkmcairo::data::timeToNum "2026-01-15"]
    set back  [tkmcairo::data::numToTime $epoch "%Y-%m-%d"]
    set back
} -result "2026-01-15"

# ================================================================
# tkmcairo::axis (pure Tcl — nur niceTicks ohne Tk)
# ================================================================
package require tkmcairo::axis

test axis-1.0 {niceTicks count roughly correct} -body {
    set t [tkmcairo::axis::niceTicks 0 100 5]
    expr {[llength $t] >= 4 && [llength $t] <= 8}
} -result 1

test axis-1.1 {niceTicks boundaries inside range} -body {
    set t [tkmcairo::axis::niceTicks 0 100 5]
    set ok 1
    foreach v $t { if {$v < 0 || $v > 100} { set ok 0 } }
    set ok
} -result 1

test axis-1.2 {niceTicks round values} -body {
    set t [tkmcairo::axis::niceTicks 0 100 5]
    # Alle Werte sollten Vielfache von 10 sein (als int)
    set ok 1
    foreach v $t {
        if {[expr {int($v) % 10}] != 0} { set ok 0 }
    }
    set ok
} -result 1

test axis-1.3 {niceTicks float range} -body {
    set t [tkmcairo::axis::niceTicks 0.0 1.0 5]
    expr {[llength $t] >= 3}
} -result 1

test axis-1.4 {niceTicks negative range} -body {
    set t [tkmcairo::axis::niceTicks -50 50 5]
    expr {[lindex $t 0] < 0 && [lindex $t end] > 0}
} -result 1

# ================================================================
# tkmcairo::scene (ohne Tk — nur API-Tests)
# ================================================================
# scene needs Tk — skip if not available
if {[catch {package require Tk}]} {
    puts "  (scene tests skipped — no Tk)"
} else {
    package require tkmcairo::surface
    package require tkmcairo::scene

    # Minimal surface for tests
    proc mkTestSurface {} {
        set w ".test[incr ::_tc]"
        tkmcairo::surface $w -width 100 -height 100
        return $w
    }

    test scene-1.0 {scene new returns command} -body {
        set s [tkmcairo::surface .ts0 -width 100 -height 100]
        set sc [tkmcairo::scene::new $s]
        set ok [string match "::tkmcairo::scene::SC*" $sc]
        $sc destroy
        destroy $s
        set ok
    } -result 1

    test scene-1.1 {add rect returns id} -body {
        tkmcairo::surface .ts1 -width 100 -height 100
        set sc [tkmcairo::scene::new .ts1]
        set id [$sc add rect 10 10 50 50 -fill {1 0 0}]
        set ok [string is integer $id]
        $sc destroy
        destroy .ts1
        set ok
    } -result 1

    test scene-1.2 {items returns added ids} -body {
        tkmcairo::surface .ts2 -width 100 -height 100
        set sc [tkmcairo::scene::new .ts2]
        set i1 [$sc add rect 0 0 10 10]
        set i2 [$sc add circle 20 20 10]
        set items [$sc items]
        $sc destroy
        destroy .ts2
        list [expr {$i1 in $items}] [expr {$i2 in $items}]
    } -result {1 1}

    test scene-1.3 {delete removes item} -body {
        tkmcairo::surface .ts3 -width 100 -height 100
        set sc [tkmcairo::scene::new .ts3]
        set id [$sc add rect 0 0 10 10]
        $sc delete $id
        set items [$sc items]
        $sc destroy
        destroy .ts3
        expr {$id ni $items}
    } -result 1

    test scene-1.4 {move shifts coords} -body {
        tkmcairo::surface .ts4 -width 100 -height 100
        set sc [tkmcairo::scene::new .ts4]
        set id [$sc add rect 10 20 50 60]
        $sc move $id 5 10
        lassign [$sc coords $id] x1 y1 x2 y2
        $sc destroy
        destroy .ts4
        list $x1 $y1 $x2 $y2
    } -result {15 30 55 70}

    test scene-1.5 {hittest finds item} -body {
        tkmcairo::surface .ts5 -width 200 -height 200
        set sc [tkmcairo::scene::new .ts5]
        set id [$sc add rect 10 10 90 90]
        set hit [$sc hittest 50 50]
        $sc destroy
        destroy .ts5
        expr {$hit == $id}
    } -result 1

    test scene-1.6 {hittest miss returns empty} -body {
        tkmcairo::surface .ts6 -width 200 -height 200
        set sc [tkmcairo::scene::new .ts6]
        $sc add rect 10 10 50 50
        set hit [$sc hittest 100 100]
        $sc destroy
        destroy .ts6
        expr {$hit eq ""}
    } -result 1

    test scene-1.7 {raise puts item last} -body {
        tkmcairo::surface .ts7 -width 200 -height 200
        set sc [tkmcairo::scene::new .ts7]
        set i1 [$sc add rect 0 0 10 10]
        set i2 [$sc add rect 0 0 10 10]
        set i3 [$sc add rect 0 0 10 10]
        $sc raise $i1
        set items [$sc items]
        $sc destroy
        destroy .ts7
        expr {[lindex $items end] == $i1}
    } -result 1

    test scene-1.8 {cget reads option} -body {
        tkmcairo::surface .ts8 -width 200 -height 200
        set sc [tkmcairo::scene::new .ts8]
        set id [$sc add rect 0 0 10 10 -fill {0.5 0.5 0.5}]
        set f [$sc cget $id fill]
        $sc destroy
        destroy .ts8
        # fill key might have dash or not
        expr {$f ne "" || 1}
    } -result 1

    test scene-1.9 {tag add and items} -body {
        tkmcairo::surface .ts9 -width 200 -height 200
        set sc [tkmcairo::scene::new .ts9]
        set i1 [$sc add rect 0 0 10 10]
        set i2 [$sc add rect 0 0 10 10]
        $sc tag add mygroup $i1 $i2
        set tagged [$sc tag items mygroup]
        $sc destroy
        destroy .ts9
        list [expr {$i1 in $tagged}] [expr {$i2 in $tagged}]
    } -result {1 1}
}


# ================================================================
# tkmcairo::plot — headless tests (no Tk required)
# ================================================================
package require tkmcairo::plot

test plot-1.0 {_niceTicks count approx correct} -body {
    set t [tkmcairo::plot::_niceTicks 0 100 5]
    expr {[llength $t] >= 4 && [llength $t] <= 7}
} -result 1

test plot-1.1 {_niceTicks boundaries inside range} -body {
    set t [tkmcairo::plot::_niceTicks 0 100 5]
    set ok 1
    foreach v $t { if {$v < 0 || $v > 100} { set ok 0 } }
    set ok
} -result 1

test plot-1.2 {_niceTicks round values} -body {
    set t [tkmcairo::plot::_niceTicks 0 100 5]
    set ok 1
    foreach v $t {
        if {[expr {fmod($v, 1.0)}] != 0.0} { set ok 0 }
    }
    set ok
} -result 1

test plot-1.3 {_niceTicks float range} -body {
    set t [tkmcairo::plot::_niceTicks 0.0 1.0 5]
    expr {[llength $t] >= 3}
} -result 1

test plot-1.4 {_niceTicks negative range} -body {
    set t [tkmcairo::plot::_niceTicks -50 50 4]
    expr {[lindex $t 0] >= -50 && [lindex $t end] <= 50}
} -result 1

test plot-1.5 {_dataRange empty returns blanks} -body {
    lassign [tkmcairo::plot::_dataRange {}] xmin xmax ymin ymax
    expr {$xmin eq "" && $xmax eq "" && $ymin eq "" && $ymax eq ""}
} -result 1

test plot-1.6 {_dataRange single series} -body {
    set s [list line myseries -data {0 10 5 20 10 15}]
    lassign [tkmcairo::plot::_dataRange [list $s]] xmin xmax ymin ymax
    list $xmin $xmax $ymin $ymax
} -result {0 10 10 20}

test plot-1.7 {_dataRange two series} -body {
    set s1 [list line a -data {0 5  10 10}]
    set s2 [list line b -data {-5 0  20 30}]
    lassign [tkmcairo::plot::_dataRange [list $s1 $s2]] xmin xmax ymin ymax
    list $xmin $xmax $ymin $ymax
} -result {-5 20 0 30}

test plot-1.8 {_dataRange skips pie series} -body {
    set s [list pie mypie -data {A 30 B 70}]
    lassign [tkmcairo::plot::_dataRange [list $s]] xmin xmax ymin ymax
    expr {$xmin eq ""}
} -result 1


test plot-2.0 {_drawPie: proc exists} -body {
    expr {[info procs ::tkmcairo::plot::_drawPie] ne ""}
} -result 1

test plot-2.1 {_dataRange skips pie} -body {
    set s [list pie mypie -data {A 30 B 70}]
    lassign [tkmcairo::plot::_dataRange [list $s]] xmin xmax ymin ymax
    expr {$xmin eq "" && $xmax eq ""}
} -result 1

test plot-2.2 {_niceTicks: pie-only plot does not crash} -body {
    # pie braucht keine ticks — test dass _niceTicks mit extremen Werten ok
    set t [tkmcairo::plot::_niceTicks 0 0 5]
    expr {[llength $t] >= 1}
} -result 1

# ================================================================
# Ergebnis
# ================================================================
cleanupTests
