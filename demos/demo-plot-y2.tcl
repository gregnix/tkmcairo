#!/usr/bin/env wish
# demo-plot-y2.tcl — secondary Y axis demo
#
# Shows: dual-scale chart with revenue (€, left axis) and growth rate
# (%, right axis). Common pattern for business dashboards where two
# series have wildly different ranges that should not share the same
# scale.
#
# Requirements: tclmcairo, tkmcairo::surface, tkmcairo::plot

package require Tk

set _dir [file dirname [file normalize [info script]]]
tcl::tm::path add [file join $_dir .. tcl]

if {[info exists env(TCLMCAIRO_LIBDIR)]} {
    lappend auto_path $env(TCLMCAIRO_LIBDIR)
    tcl::tm::path add $env(TCLMCAIRO_LIBDIR)
}

package require tkmcairo::plot

# ----------------------------------------------------------------
# Sample data: monthly revenue (€) and YoY growth rate (%)
# ----------------------------------------------------------------
set months {1 2 3 4 5 6 7 8 9 10 11 12}
set revenue {
    1 12500   2 13800   3 15200   4 14600   5 16100   6 17800
    7 18400   8 17200   9 19500  10 21300  11 23800  12 27600
}
set growth {
    1 4.2    2 5.8    3 6.1    4 3.9    5 4.5    6 7.2
    7 8.1    8 4.8    9 9.3   10 12.5  11 14.2  12 18.7
}

# ----------------------------------------------------------------
# UI
# ----------------------------------------------------------------
wm title    . "tkmcairo::plot — secondary Y axis demo"
wm geometry . 800x500

ttk::label .info \
    -text "Revenue (€) on left axis · YoY growth (%) on right axis" \
    -padding 10
pack .info -side top -fill x

# The plot widget — surface beneath, plot on top
tkmcairo::plot .p -width 760 -height 400
pack .p -side top -fill both -expand 1 -padx 10 -pady 10

# Configure axes — Y is € revenue, Y2 is % growth
.p xaxis  -label "Month" -min 1 -max 12 -ticks 12 -format "%g"
.p yaxis  -label "Revenue (€)" -min 0 -max 30000 -ticks 6 -format "%g"
.p y2axis -label "Growth (%)"  -min 0 -max 25    -ticks 5 -format "%.0f"

# Two series — one on each axis, distinguished by colour
.p series line revenue \
    -data $revenue \
    -color {0.20 0.40 0.85} \
    -width 2.0
.p series line growth \
    -data $growth \
    -color {0.85 0.30 0.20} \
    -width 2.0 \
    -yaxis y2

# Legend hint at bottom
ttk::label .hint \
    -text "Blue → revenue (left axis)   ·   Red → growth (right axis)" \
    -padding {10 5} \
    -foreground gray40
pack .hint -side bottom -fill x
