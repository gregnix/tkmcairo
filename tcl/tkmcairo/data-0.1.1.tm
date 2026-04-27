# tkmcairo::data 0.1
#
# Daten-Hilfsfunktionen für tkmcairo Charts.
#
# API:
#   tkmcairo::data::range     xydata     -> {xmin xmax ymin ymax}
#   tkmcairo::data::xrange    xydata     -> {xmin xmax}
#   tkmcairo::data::yrange    xydata     -> {ymin ymax}
#   tkmcairo::data::smooth    xydata n   -> geglättete xydata (Moving Average)
#   tkmcairo::data::boxstats  values     -> {min q1 median q3 max mean}
#   tkmcairo::data::histogram values ?-bins n? ?-min m? ?-max m? -> {label count ...}
#   tkmcairo::data::timeToNum datestr    -> Epoch-Sekunden
#   tkmcairo::data::numToTime epoch ?fmt? -> Datumsstring
#   tkmcairo::data::normalize xydata    -> xydata normalisiert 0..1
#   tkmcairo::data::cumsum    values    -> kumulative Summe
#
# Part of tkmcairo — https://github.com/gregnix/tkmcairo
# License: BSD 2-Clause

package provide tkmcairo::data 0.1.1

namespace eval ::tkmcairo::data {}

# Wertebereich aus x-y-Paaren
proc ::tkmcairo::data::range {xydata} {
    if {[llength $xydata] < 2} { return {0 1 0 1} }
    set xmin ""; set xmax ""; set ymin ""; set ymax ""
    foreach {xv yv} $xydata {
        if {$xmin eq "" || $xv < $xmin} { set xmin $xv }
        if {$xmax eq "" || $xv > $xmax} { set xmax $xv }
        if {$ymin eq "" || $yv < $ymin} { set ymin $yv }
        if {$ymax eq "" || $yv > $ymax} { set ymax $yv }
    }
    list $xmin $xmax $ymin $ymax
}

proc ::tkmcairo::data::xrange {xydata} {
    lassign [range $xydata] xmin xmax
    list $xmin $xmax
}

proc ::tkmcairo::data::yrange {xydata} {
    lassign [range $xydata] xmin xmax ymin ymax
    list $ymin $ymax
}

# Moving Average Glättung
proc ::tkmcairo::data::smooth {xydata n} {
    if {$n <= 1 || [llength $xydata] < 4} { return $xydata }
    set xs {}; set ys {}
    foreach {xv yv} $xydata { lappend xs $xv; lappend ys $yv }
    set result {}
    set half [expr {$n / 2}]
    for {set i 0} {$i < [llength $xs]} {incr i} {
        set sum 0; set cnt 0
        for {set j [expr {$i - $half}]} {$j <= [expr {$i + $half}]} {incr j} {
            if {$j >= 0 && $j < [llength $ys]} {
                set sum [expr {$sum + [lindex $ys $j]}]
                incr cnt
            }
        }
        lappend result [lindex $xs $i] [expr {$sum / $cnt}]
    }
    return $result
}

# Box-Plot Statistik
proc ::tkmcairo::data::boxstats {values} {
    if {[llength $values] == 0} { return {0 0 0 0 0 0} }
    set sorted [lsort -real $values]
    set n [llength $sorted]
    set mn [lindex $sorted 0]
    set mx [lindex $sorted end]
    # Median
    if {$n % 2 == 0} {
        set med [expr {([lindex $sorted [expr {$n/2-1}]] + [lindex $sorted [expr {$n/2}]]) / 2.0}]
    } else {
        set med [lindex $sorted [expr {$n/2}]]
    }
    # Q1, Q3
    set q1 [lindex $sorted [expr {$n/4}]]
    set q3 [lindex $sorted [expr {3*$n/4}]]
    # Mittelwert
    set sum 0
    foreach v $values { set sum [expr {$sum + $v}] }
    set mean [expr {$sum / double($n)}]
    list $mn $q1 $med $q3 $mx $mean
}

# Histogramm: Werte → Bins mit Labels und Counts
proc ::tkmcairo::data::histogram {values args} {
    array set opts {-bins 10 -min "" -max ""}
    foreach {k v} $args { set opts($k) $v }

    if {[llength $values] == 0} { return {} }

    set mn $opts(-min)
    set mx $opts(-max)
    if {$mn eq ""} { set mn [tcl::mathfunc::min {*}$values] }
    if {$mx eq ""} { set mx [tcl::mathfunc::max {*}$values] }
    if {$mn == $mx} { return [list "$mn" [llength $values]] }

    set bins $opts(-bins)
    set bw [expr {($mx - $mn) / double($bins)}]

    # Bins initialisieren
    set counts [lrepeat $bins 0]
    foreach v $values {
        set idx [expr {int(($v - $mn) / $bw)}]
        if {$idx >= $bins} { set idx [expr {$bins - 1}] }
        if {$idx < 0}      { set idx 0 }
        lset counts $idx [expr {[lindex $counts $idx] + 1}]
    }

    set result {}
    for {set i 0} {$i < $bins} {incr i} {
        set lo [expr {$mn + $i * $bw}]
        set hi [expr {$lo + $bw}]
        lappend result [format "%.4g" $lo] [lindex $counts $i]
    }
    return $result
}

# Datum → Epoch
proc ::tkmcairo::data::timeToNum {datestr} {
    clock scan $datestr
}

# Epoch → Datumsstring
proc ::tkmcairo::data::numToTime {epoch {fmt "%Y-%m-%d"}} {
    clock format [expr {int($epoch)}] -format $fmt
}

# Normalisierung auf 0..1
proc ::tkmcairo::data::normalize {xydata} {
    lassign [range $xydata] xmin xmax ymin ymax
    set xr [expr {$xmax - $xmin}]
    set yr [expr {$ymax - $ymin}]
    if {$xr == 0} { set xr 1 }
    if {$yr == 0} { set yr 1 }
    set result {}
    foreach {xv yv} $xydata {
        lappend result \
            [expr {($xv - $xmin) / $xr}] \
            [expr {($yv - $ymin) / $yr}]
    }
    return $result
}

# Kumulative Summe
proc ::tkmcairo::data::cumsum {values} {
    set result {}
    set sum 0
    foreach v $values {
        set sum [expr {$sum + $v}]
        lappend result $sum
    }
    return $result
}
