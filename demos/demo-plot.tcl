#!/usr/bin/env wish
# demo-plot.tcl — tkmcairo::plot demonstration
#
# Shows: line, area, scatter, bar charts
# Each chart exports to PDF/SVG on request
#
# Requirements: tclmcairo, tkmcairo::surface, tkmcairo::plot

package require Tk

# Find modules
set _dir [file dirname [file normalize [info script]]]
# tcl::tm::path add [file join $_dir .. tcl]
# tkmcairo/ subdir auto-discovered by tm system
tcl::tm::path add [file join $_dir .. tcl]

# Find tclmcairo
set _lib [file join $_dir .. .. tclmcairo03]
if {[file exists $_lib]} {
    lappend auto_path $_lib
    tcl::tm::path add $_lib
}
if {[info exists env(TCLMCAIRO_LIBDIR)]} {
    lappend auto_path $env(TCLMCAIRO_LIBDIR)
    tcl::tm::path add $env(TCLMCAIRO_LIBDIR)
}

package require tkmcairo::surface
package require tkmcairo::plot

# ============================================================
# Main window
# ============================================================
wm title . "tkmcairo::plot Demo"
wm geometry . 1000x700

ttk::frame .main
pack .main -fill both -expand 1

# Toolbar
ttk::frame .tb
pack .tb -in .main -side top -fill x -padx 4 -pady 4

ttk::label .tb.l -text "Chart:"
ttk::combobox .tb.chart -width 14 -state readonly \
    -values {Line Area Scatter Bar Multi}
.tb.chart set Line

ttk::button .tb.show -text "Show" -command showChart
ttk::separator .tb.s1 -orient vertical
ttk::button .tb.pdf  -text "Export PDF" \
    -command {exportChart pdf}
ttk::button .tb.svg  -text "Export SVG" \
    -command {exportChart svg}
ttk::button .tb.png  -text "Export PNG" \
    -command {exportChart png}

foreach w {l chart s1 show pdf svg png} {
    pack .tb.$w -side left -padx 3 -pady 2
}

# Plot area
tkmcairo::plot .p \
    -width 960 -height 580 \
    -title "tkmcairo::plot Demo"

pack .p -in .main -fill both -expand 1 -padx 4 -pady 4

# Status
ttk::label .status -text "Ready" -anchor w
pack .status -side bottom -fill x -padx 4

# ============================================================
# Chart definitions
# ============================================================

proc showChart {} {
    set which [.tb.chart get]
    .p clear

    switch $which {
        Line    { showLine    }
        Area    { showArea    }
        Scatter { showScatter }
        Bar     { showBar     }
        Multi   { showMulti   }
    }
    .status configure -text "Showing: $which"
}

proc showLine {} {
    .p configure -title "Monthly Temperature 2026"
    .p xaxis -label "Month" -min 1 -max 12 -ticks 11 -format "%.0f"
    .p yaxis -label "°C"    -min -15 -max 45 -grid 1

    .p series line "Berlin" \
        -data {1 -2  2 0  3 5  4 12  5 18  6 23
               7 25  8 24  9 19 10 13 11 6  12 1} \
        -color {0.2 0.45 0.85} -width 2.5 -marker circle -markersize 4

    .p series line "Athens" \
        -data {1 10  2 11  3 14  4 19  5 25  6 31
               7 34  8 33  9 28 10 22 11 16  12 12} \
        -color {0.85 0.35 0.15} -width 2.5 -marker circle -markersize 4

    .p series line "Reykjavik" \
        -data {1 -2  2 -1  3 1  4 4  5 9  6 12
               7 14  8 13  9 9 10 4 11 1  12 -1} \
        -color {0.3 0.7 0.4} -width 2 -dash {8 4}
}

proc showArea {} {
    .p configure -title "Website Traffic 2026 (Area Chart)"
    .p xaxis -label "Week" -min 1 -max 12 -ticks 11 -format "%.0f"
    .p yaxis -label "Visitors (k)" -min 0 -max 50 -grid 1

    .p series area "Desktop" \
        -data {1 18  2 22  3 19  4 25  5 28  6 32
               7 30  8 27  9 31 10 35 11 38  12 42} \
        -color {0.2 0.5 0.85} -alpha 0.6 -width 2

    .p series area "Mobile" \
        -data {1 8   2 10  3 12  4 11  5 15  6 18
               7 20  8 19  9 22 10 24 11 26  12 30} \
        -color {0.85 0.4 0.2} -alpha 0.6 -width 2
}

proc showScatter {} {
    .p configure -title "Scatter Plot — Performance vs Cost"
    .p xaxis -label "Cost (€)" -min 0 -max 100 -ticks 5
    .p yaxis -label "Performance" -min 0 -max 100 -ticks 5 -grid 1

    # Generate random-ish data
    set d1 {}; set d2 {}; set d3 {}
    for {set i 0} {$i < 30} {incr i} {
        lappend d1 [expr {10+rand()*30}] [expr {20+rand()*50+$i}]
        lappend d2 [expr {40+rand()*40}] [expr {30+rand()*60}]
        lappend d3 [expr {60+rand()*35}] [expr {60+rand()*35}]
    }

    .p series scatter "Product A" -data $d1 \
        -color {0.2 0.5 0.9} -markersize 6
    .p series scatter "Product B" -data $d2 \
        -color {0.9 0.4 0.2} -markersize 6
    .p series scatter "Product C" -data $d3 \
        -color {0.3 0.75 0.3} -markersize 6
}

proc showBar {} {
    .p configure -title "Sales by Product Q1 2026"
    .p xaxis -label "Product"
    .p yaxis -label "Sales (k€)" -min 0 -max 80 -grid 1

    .p series bar "Q1" \
        -data {Alpha 45  Beta 62  Gamma 38  Delta 71  Epsilon 29} \
        -color {0.2 0.5 0.85}
}

proc showMulti {} {
    .p configure -title "Multi-Series: Revenue & Growth"
    .p xaxis -label "Quarter" -min 0.5 -max 4.5 -ticks 4 -format "Q%.0f"
    .p yaxis -label "Revenue (M€)" -min 0 -max 60 -grid 1

    .p series area "Revenue" \
        -data {1 28  2 35  3 42  4 51} \
        -color {0.25 0.55 0.85} -alpha 0.5 -width 2.5

    .p series line "Forecast" \
        -data {1 26  2 33  3 44  4 55} \
        -color {0.8 0.5 0.1} -width 2 -dash {10 5}

    .p series scatter "Actual" \
        -data {1 28  2 35  3 42  4 51} \
        -color {0.2 0.2 0.8} -markersize 7
}

proc exportChart {fmt} {
    set file [tk_getSaveFile \
        -defaultextension .$fmt \
        -filetypes [list \
            [list "[string toupper $fmt] Files" .$fmt] \
            {"All Files" *}] \
        -title "Export as [string toupper $fmt]"]
    if {$file eq ""} return
    .p export $file
    .status configure -text "Exported: $file"
}

# Start with line chart
showLine
