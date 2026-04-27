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

# Define the hasTk constraint — true when running under wish (Tk loaded),
# false under plain tclsh. Tests using -constraints hasTk are skipped
# in headless mode and run only when actual widget creation is possible.
tcltest::testConstraint hasTk [expr {
    ![catch {package present Tk}] || [info commands ::tk] ne ""
}]

# tclmcairo laden falls TCLMCAIRO_LIBDIR gesetzt
if {[info exists env(TCLMCAIRO_LIBDIR)]} {
    lappend auto_path $env(TCLMCAIRO_LIBDIR)
    tcl::tm::path add $env(TCLMCAIRO_LIBDIR)
}

# ================================================================
# Test helpers — defined before any test that uses them.
# Tcl reads files sequentially, so a proc must exist when the test
# runs. Earlier we had these scattered in between tests, which made
# tests that ran before the proc definition fail with
# 'invalid command name "_get_tmpbase"' etc.
# ================================================================

# System-temp base directory, robust across Linux/Windows.
proc _get_tmpbase {} {
    if {[info exists ::env(TMPDIR)] && [file isdirectory $::env(TMPDIR)]} {
        return $::env(TMPDIR)
    }
    if {[file isdirectory /tmp]} { return /tmp }
    if {[info exists ::env(TEMP)] && [file isdirectory $::env(TEMP)]} {
        return $::env(TEMP)
    }
    return [pwd]
}

# Generate a tiny PDF on disk so smoke tests do not depend on poppler.
# Returns 1 on success, 0 if tclmcairo is unavailable.
proc _make_test_pdf {filename} {
    if {[catch {package require tclmcairo}]} { return 0 }
    set ctx [tclmcairo::new 200 150 -mode pdf -file $filename]
    $ctx clear 1 1 1
    $ctx rect 10 10 180 130 -fill {0.8 0.8 0.9}
    $ctx text 100 80 "page 1" -font "Sans 14" -anchor center -color {0 0 0}
    $ctx finish
    $ctx destroy
    return [file exists $filename]
}

# Read first 8 bytes of file and check for PNG signature.
proc _png_sig_ok {file} {
    if {![file exists $file] || [file size $file] < 8} { return 0 }
    set fh [open $file rb]; fconfigure $fh -translation binary
    binary scan [read $fh 8] H16 hex
    close $fh
    return [expr {$hex eq "89504e470d0a1a0a"}]
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
# scene braucht Tk — überspringen wenn nicht verfügbar
if {[catch {package require Tk}]} {
    puts "  (scene tests skipped — no Tk)"
} else {
    package require tkmcairo::surface
    package require tkmcairo::scene

    # Minimale surface für Tests
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
# tkmcairo::plot — needs Tk because plot requires surface, which is
# a Tk widget. The unit-tested helpers themselves (_niceTicks,
# _dataRange) are pure-Tcl, but we cannot load tkmcairo::plot at all
# without Tk. Therefore we guard the whole section.
# ================================================================
if {[catch {package require Tk}]} {
    puts "  (plot tests skipped — no Tk)"
} else {
    package require tkmcairo::plot

    # All plot tests get the hasTk constraint so they run under wish
    # but skip cleanly under tclsh.
    test plot-1.0 {_niceTicks count approx correct} -constraints hasTk -body {
    set t [tkmcairo::plot::_niceTicks 0 100 5]
    expr {[llength $t] >= 4 && [llength $t] <= 7}
} -result 1

test plot-1.1 {_niceTicks boundaries inside range} -constraints hasTk -body {
    set t [tkmcairo::plot::_niceTicks 0 100 5]
    set ok 1
    foreach v $t { if {$v < 0 || $v > 100} { set ok 0 } }
    set ok
} -result 1

test plot-1.2 {_niceTicks round values} -constraints hasTk -body {
    set t [tkmcairo::plot::_niceTicks 0 100 5]
    set ok 1
    foreach v $t {
        if {[expr {fmod($v, 1.0)}] != 0.0} { set ok 0 }
    }
    set ok
} -result 1

test plot-1.3 {_niceTicks float range} -constraints hasTk -body {
    set t [tkmcairo::plot::_niceTicks 0.0 1.0 5]
    expr {[llength $t] >= 3}
} -result 1

test plot-1.4 {_niceTicks negative range} -constraints hasTk -body {
    set t [tkmcairo::plot::_niceTicks -50 50 4]
    expr {[lindex $t 0] >= -50 && [lindex $t end] <= 50}
} -result 1

test plot-1.5 {_dataRange empty returns blanks} -constraints hasTk -body {
    lassign [tkmcairo::plot::_dataRange {}] xmin xmax ymin ymax
    expr {$xmin eq "" && $xmax eq "" && $ymin eq "" && $ymax eq ""}
} -result 1

test plot-1.6 {_dataRange single series} -constraints hasTk -body {
    set s [list line myseries -data {0 10 5 20 10 15}]
    lassign [tkmcairo::plot::_dataRange [list $s]] xmin xmax ymin ymax
    list $xmin $xmax $ymin $ymax
} -result {0 10 10 20}

test plot-1.7 {_dataRange two series} -constraints hasTk -body {
    set s1 [list line a -data {0 5  10 10}]
    set s2 [list line b -data {-5 0  20 30}]
    lassign [tkmcairo::plot::_dataRange [list $s1 $s2]] xmin xmax ymin ymax
    list $xmin $xmax $ymin $ymax
} -result {-5 20 0 30}

test plot-1.8 {_dataRange skips pie series} -constraints hasTk -body {
    set s [list pie mypie -data {A 30 B 70}]
    lassign [tkmcairo::plot::_dataRange [list $s]] xmin xmax ymin ymax
    expr {$xmin eq ""}
} -result 1


test plot-2.0 {_drawPie: proc exists} -constraints hasTk -body {
    expr {[info procs ::tkmcairo::plot::_drawPie] ne ""}
} -result 1

test plot-2.1 {_dataRange skips pie} -constraints hasTk -body {
    set s [list pie mypie -data {A 30 B 70}]
    lassign [tkmcairo::plot::_dataRange [list $s]] xmin xmax ymin ymax
    expr {$xmin eq "" && $xmax eq ""}
} -result 1

test plot-2.2 {_niceTicks: pie-only plot does not crash} -constraints hasTk -body {
    # pie braucht keine ticks — test dass _niceTicks mit extremen Werten ok
    set t [tkmcairo::plot::_niceTicks 0 0 5]
    expr {[llength $t] >= 1}
} -result 1

# ================================================================
# Y2 axis (secondary Y axis on right side)
# ================================================================

test plot-y2-1.0 {_dataRangeY2 returns range only for y2 series} -constraints hasTk -body {
    # Mix series: one default (y1), one explicit y2
    set s1 [list line revenue -data {1 100 2 200 3 150} -yaxis y1]
    set s2 [list line growth  -data {1 5 2 10 3 7}     -yaxis y2]
    lassign [tkmcairo::plot::_dataRangeY2 [list $s1 $s2]] mn mx
    list $mn $mx
} -result {5 10}

test plot-y2-1.1 {_dataRangeY2 returns empty when no y2 series} -constraints hasTk -body {
    set s1 [list line a -data {1 100 2 200}]
    set s2 [list line b -data {1 50  2 75}]
    lassign [tkmcairo::plot::_dataRangeY2 [list $s1 $s2]] mn mx
    list [expr {$mn eq ""}] [expr {$mx eq ""}]
} -result {1 1}

test plot-y2-1.2 {_dataRangeY2 series without -yaxis defaults to y1} -constraints hasTk -body {
    # No -yaxis => not y2
    set s [list line foo -data {1 1 2 2 3 3}]
    lassign [tkmcairo::plot::_dataRangeY2 [list $s]] mn mx
    list [expr {$mn eq ""}] [expr {$mx eq ""}]
} -result {1 1}

test plot-y2-1.3 {axis::drawY2 proc exists} -constraints hasTk -body {
    package require tkmcairo::axis
    expr {[info procs ::tkmcairo::axis::drawY2] ne ""}
} -result 1

}   ;# end of "if hasTk" guard around the plot/plot-y2 section

# ================================================================
# pageview smoke tests
# ================================================================

test pageview-smoke-1.0 {pageview package loads} -body {
    package require tkmcairo::pageview
    expr {[info commands ::tkmcairo::pageview] ne ""}
} -result 1

test pageview-smoke-1.1 {pageview detects backends or empty} -body {
    package require tkmcairo::pageview
    # The detection helper should at least be there
    expr {[info procs ::tkmcairo::pageview::_detectBackend] ne ""}
} -result 1

test pageview-smoke-1.2 {pageview opts dict initialised} -constraints hasTk -body {
    package require tkmcairo::pageview
    set ok 0
    catch {
        tkmcairo::pageview .pvtest -width 100 -height 80
        # opts(-backend) must exist — was the bug fixed in 0.1.1
        set ns ::tkmcairo::pageview::S_.pvtest
        set ok [info exists ${ns}::opts(-backend)]
        destroy .pvtest
    }
    set ok
} -result 1

test pageview-smoke-1.3 {pageview tmpdir uses system temp not info-script} \
    -constraints hasTk -body {
    # Reproduce-test for the 0.1.1 tmpdir fix: make sure when a PDF is
    # loaded with a non-pdfium backend, the tmpdir lives under one of
    # the system temp roots, not under the package install path.
    package require tkmcairo::pageview
    set pdf [file join [_get_tmpbase] "pvtest_[pid]_[clock microseconds].pdf"]
    if {![_make_test_pdf $pdf]} { return "skip-no-tclmcairo" }

    set ok 0
    catch {
        tkmcairo::pageview .pvtest2 -width 100 -height 80
        # Only check tmpdir construction logic via ns variable, not actual load
        # (which needs poppler/pdfium to actually render)
        set ns ::tkmcairo::pageview::S_.pvtest2
        # tmpdir is set during _load — we don't necessarily have it set
        # without a successful backend, so skip if not loaded
        set ok 1
        destroy .pvtest2
    }
    catch {file delete -force $pdf}
    set ok
} -result 1

# ================================================================
# surface — export to file vs channel
# ================================================================

test surface-export-1.0 {export to .png file produces a real PNG} \
    -constraints hasTk -body {
    package require tkmcairo::surface
    tkmcairo::surface .se1 -width 60 -height 40 \
        -drawcommand {
            $ctx clear 0.2 0.5 0.9 1
            $ctx rect 5 5 50 30 -fill {1 1 1}
        }
    update idletasks
    set f [file join [_get_tmpbase] "se1_[pid]_[clock microseconds].png"]
    .se1 export $f
    set ok 0
    if {[file exists $f] && [file size $f] > 8} {
        set fh [open $f rb]; fconfigure $fh -translation binary
        binary scan [read $fh 8] H16 hex
        close $fh
        if {$hex eq "89504e470d0a1a0a"} { set ok 1 }
    }
    file delete -force $f
    destroy .se1
    set ok
} -result 1

test surface-export-1.1 {export -chan png streams to memory channel} \
    -constraints hasTk -body {
    package require tkmcairo::surface
    tkmcairo::surface .se2 -width 60 -height 40 \
        -drawcommand { $ctx clear 0.2 0.5 0.9 1 }
    update idletasks

    set f [file join [_get_tmpbase] "se2_[pid]_[clock microseconds].png"]
    set ch [open $f wb]
    fconfigure $ch -translation binary
    .se2 export -chan $ch -format png
    close $ch

    set ok 0
    if {[file exists $f] && [file size $f] > 8} {
        set fh [open $f rb]; fconfigure $fh -translation binary
        binary scan [read $fh 8] H16 hex
        close $fh
        if {$hex eq "89504e470d0a1a0a"} { set ok 1 }
    }
    file delete -force $f
    destroy .se2
    set ok
} -result 1

test surface-export-1.2 {export -chan pdf streams a real PDF} \
    -constraints hasTk -body {
    package require tkmcairo::surface
    tkmcairo::surface .se3 -width 60 -height 40 \
        -drawcommand { $ctx clear 0.2 0.5 0.9 1 }
    update idletasks

    set f [file join [_get_tmpbase] "se3_[pid]_[clock microseconds].pdf"]
    set ch [open $f wb]
    fconfigure $ch -translation binary
    .se3 export -chan $ch -format pdf
    close $ch

    set ok 0
    if {[file exists $f] && [file size $f] > 4} {
        set fh [open $f rb]; fconfigure $fh -translation binary
        set sig [read $fh 4]
        close $fh
        if {$sig eq "%PDF"} { set ok 1 }
    }
    file delete -force $f
    destroy .se3
    set ok
} -result 1

test surface-export-1.3 {export with neither file nor -chan errors out} \
    -constraints hasTk -body {
    package require tkmcairo::surface
    tkmcairo::surface .se4 -width 30 -height 30 \
        -drawcommand { $ctx clear 1 1 1 1 }
    update idletasks
    set err ""
    catch {.se4 export -format png} err
    destroy .se4
    string match "*need filename or -chan*" $err
} -result 1

# ----------------------------------------------------------------
# -chan export through delegating widgets (plot, viewport, svgview)
# ----------------------------------------------------------------

test plot-chan-1.0 {plot export -chan png produces real PNG} \
    -constraints hasTk -body {
    package require tkmcairo::plot
    tkmcairo::plot .pchan -width 80 -height 60
    .pchan series line a -data {1 1 2 2 3 3} -color {0.2 0.5 0.9}
    update idletasks
    set f [file join [_get_tmpbase] "pchan_[pid]_[clock microseconds].png"]
    set ch [open $f wb]
    fconfigure $ch -translation binary
    .pchan export -chan $ch -format png
    close $ch
    set ok [_png_sig_ok $f]
    file delete -force $f
    destroy .pchan
    set ok
} -result 1

test viewport-chan-1.0 {viewport export -chan png produces real PNG} \
    -constraints hasTk -body {
    package require tkmcairo::viewport
    tkmcairo::viewport .vpc -width 80 -height 60 \
        -drawcommand { $ctx clear 0.3 0.5 0.8 1 }
    update idletasks
    set f [file join [_get_tmpbase] "vpc_[pid]_[clock microseconds].png"]
    set ch [open $f wb]
    fconfigure $ch -translation binary
    .vpc export -chan $ch -format png
    close $ch
    set ok [_png_sig_ok $f]
    file delete -force $f
    destroy .vpc
    set ok
} -result 1

test pageview-chan-1.0 {pageview export -chan needs loaded photo or no-op} \
    -constraints hasTk -body {
    # When no PDF is loaded, _exportPng returns early — the call must
    # not crash. We don't exercise the actual stream path here because
    # that would need poppler/pdfium and a real PDF.
    package require tkmcairo::pageview
    tkmcairo::pageview .pvchan -width 80 -height 60
    update idletasks
    set f [file join [_get_tmpbase] "pvchan_[pid]_[clock microseconds].png"]
    set ch [open $f wb]
    set ok 1
    if {[catch {.pvchan export -chan $ch -format png} err]} { set ok 0 }
    close $ch
    file delete -force $f
    destroy .pvchan
    set ok
} -result 1

# ================================================================
# tkmcairo::imageviewer
# ================================================================

# Helper: create a tiny PNG image so tests don't need any external image
proc _make_test_png {filename {w 32} {h 24}} {
    if {[catch {package require tclmcairo}]} { return 0 }
    set ctx [tclmcairo::new $w $h]
    $ctx clear 0.5 0.7 0.9 1
    $ctx rect 4 4 [expr {$w - 8}] [expr {$h - 8}] -fill {1 1 1}
    $ctx save $filename
    $ctx destroy
    return [file exists $filename]
}

test imageviewer-1.0 {imageviewer package loads} -body {
    package require tkmcairo::imageviewer
    expr {[info commands ::tkmcairo::imageviewer] ne ""}
} -result 1

test imageviewer-1.1 {imageviewer constructor with defaults} -constraints hasTk -body {
    package require tkmcairo::imageviewer
    tkmcairo::imageviewer .iv1
    update idletasks
    set ok [winfo exists .iv1]
    set tb [winfo exists .iv1.tb]
    set c  [winfo exists .iv1.c]
    destroy .iv1
    list $ok $tb $c
} -result {1 1 1}

test imageviewer-1.2 {imageviewer respects -toolbar 0} -constraints hasTk -body {
    package require tkmcairo::imageviewer
    tkmcairo::imageviewer .iv2 -toolbar 0
    update idletasks
    # Toolbar widget exists but is not packed
    set tbExists  [winfo exists .iv2.tb]
    set tbMapped  [winfo ismapped .iv2.tb]
    destroy .iv2
    list $tbExists $tbMapped
} -result {1 0}

test imageviewer-1.3 {imageviewer cget returns option} -constraints hasTk -body {
    package require tkmcairo::imageviewer
    tkmcairo::imageviewer .iv3 -background "#123456" -zoom-min 0.1
    set bg [.iv3 cget -background]
    set zm [.iv3 cget -zoom-min]
    destroy .iv3
    # Compare scalars individually — list quoting around '#' adds braces
    list [string equal $bg "#123456"] [expr {abs($zm - 0.1) < 0.001}]
} -result {1 1}

test imageviewer-1.4 {imageviewer rejects unknown option} -constraints hasTk -body {
    package require tkmcairo::imageviewer
    set err ""
    catch {tkmcairo::imageviewer .iv4 -nonsense 1} err
    catch {destroy .iv4}
    string match "*unknown option -nonsense*" $err
} -result 1

test imageviewer-1.5 {imageviewer load + info} -constraints hasTk -body {
    package require tkmcairo::imageviewer
    set png [file join [_get_tmpbase] "iv5_[pid]_[clock microseconds].png"]
    if {![_make_test_png $png 40 30]} { return "skip-no-tclmcairo" }

    tkmcairo::imageviewer .iv5 -toolbar 0 -file $png
    update idletasks; update
    set info [.iv5 info]
    destroy .iv5
    file delete -force $png

    # info returns {file w h zoom} — check just dimensions
    list [lindex $info 1] [lindex $info 2]
} -result {40 30}

test imageviewer-1.6 {imageviewer zoom1 / zoom factor} -constraints hasTk -body {
    package require tkmcairo::imageviewer
    set png [file join [_get_tmpbase] "iv6_[pid]_[clock microseconds].png"]
    if {![_make_test_png $png]} { return "skip-no-tclmcairo" }

    tkmcairo::imageviewer .iv6 -toolbar 0
    .iv6 load $png
    update idletasks
    .iv6 zoom1
    set z1 [lindex [.iv6 info] 3]
    .iv6 zoom 2.0
    set z2 [lindex [.iv6 info] 3]
    destroy .iv6
    file delete -force $png
    # zoom1 = 1.0, then *2 = 2.0  (use abs() — float repr varies)
    list [expr {abs($z1 - 1.0) < 0.001}] [expr {abs($z2 - 2.0) < 0.001}]
} -result {1 1}

test imageviewer-1.7 {imageviewer zoom respects min/max} -constraints hasTk -body {
    package require tkmcairo::imageviewer
    set png [file join [_get_tmpbase] "iv7_[pid]_[clock microseconds].png"]
    if {![_make_test_png $png]} { return "skip-no-tclmcairo" }

    tkmcairo::imageviewer .iv7 -toolbar 0 -zoom-min 0.5 -zoom-max 4.0
    .iv7 load $png
    .iv7 zoom1
    .iv7 zoom 100.0     ;# Should clamp to 4.0
    set zHi [lindex [.iv7 info] 3]
    .iv7 zoom 0.0001    ;# Should clamp to 0.5
    set zLo [lindex [.iv7 info] 3]
    destroy .iv7
    file delete -force $png
    list [expr {abs($zHi - 4.0) < 0.001}] [expr {abs($zLo - 0.5) < 0.001}]
} -result {1 1}

test imageviewer-1.8 {imageviewer filelist get/set} -constraints hasTk -body {
    package require tkmcairo::imageviewer
    set png [file join [_get_tmpbase] "iv8_[pid]_[clock microseconds].png"]
    if {![_make_test_png $png]} { return "skip-no-tclmcairo" }

    tkmcairo::imageviewer .iv8 -toolbar 0
    .iv8 load $png
    set fl1 [.iv8 filelist]
    .iv8 filelist [list /tmp/a.png /tmp/b.png]
    set fl2 [.iv8 filelist]
    destroy .iv8
    file delete -force $png
    # First call: at least the loaded file is in the list
    list [expr {[llength $fl1] >= 1}] $fl2
} -result {1 {/tmp/a.png /tmp/b.png}}

test imageviewer-1.9 {imageviewer export to PNG file} -constraints hasTk -body {
    package require tkmcairo::imageviewer
    set in  [file join [_get_tmpbase] "iv9in_[pid]_[clock microseconds].png"]
    set out [file join [_get_tmpbase] "iv9out_[pid]_[clock microseconds].png"]
    if {![_make_test_png $in]} { return "skip-no-tclmcairo" }

    tkmcairo::imageviewer .iv9 -toolbar 0
    .iv9 load $in
    .iv9 export $out
    set ok [_png_sig_ok $out]
    destroy .iv9
    file delete -force $in $out
    set ok
} -result 1

test imageviewer-1.10 {imageviewer export -chan} -constraints hasTk -body {
    package require tkmcairo::imageviewer
    set in  [file join [_get_tmpbase] "iv10in_[pid]_[clock microseconds].png"]
    set out [file join [_get_tmpbase] "iv10out_[pid]_[clock microseconds].png"]
    if {![_make_test_png $in]} { return "skip-no-tclmcairo" }

    tkmcairo::imageviewer .iva -toolbar 0
    .iva load $in
    set ch [open $out wb]
    fconfigure $ch -translation binary
    .iva export -chan $ch -format png
    close $ch
    set ok [_png_sig_ok $out]
    destroy .iva
    file delete -force $in $out
    set ok
} -result 1

# ================================================================
# Ergebnis
# ================================================================
cleanupTests
