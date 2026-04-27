#!/usr/bin/env wish
# demo-svgview.tcl — SVG Viewer Demo

package require Tk

set _dir [file dirname [file normalize [info script]]]
tcl::tm::path add [file join $_dir .. tcl]
if {[info exists env(TCLMCAIRO_LIBDIR)]} {
    lappend auto_path $env(TCLMCAIRO_LIBDIR)
    tcl::tm::path add $env(TCLMCAIRO_LIBDIR)
}

package require tkmcairo::svgview

wm title . "tkmcairo SVG Viewer"
wm geometry . 900x650

# Toolbar
ttk::frame .tb
pack .tb -fill x -padx 4 -pady 4

ttk::button .tb.open -text "Open..."  -command svOpen
ttk::button .tb.prev -text "◀"        -command svPrev
ttk::button .tb.next -text "▶"        -command svNext
ttk::separator .tb.s1 -orient vertical
ttk::button .tb.zin  -text "Zoom +"   -command {.sv zoom 1.25}
ttk::button .tb.zout -text "Zoom −"   -command {.sv zoom 0.8}
ttk::button .tb.zfit -text "Fit"      -command {.sv zoomfit}
ttk::button .tb.z1   -text "1:1"      -command {.sv zoom1}
ttk::separator .tb.s2 -orient vertical
ttk::label .tb.rl    -text "Renderer:"
ttk::combobox .tb.rend -width 10 -state readonly \
    -values {auto luna svg2cairo nanosvg}
.tb.rend set auto
bind .tb.rend <<ComboboxSelected>> {
    .sv configure -renderer [.tb.rend get]
    .sv reload
}
ttk::separator .tb.s3 -orient vertical
ttk::button .tb.epdf -text "Export PDF" -command {svExport pdf}
ttk::button .tb.esvg -text "Export SVG" -command {svExport svg}
ttk::button .tb.epng -text "Export PNG" -command {svExport png}

foreach w {open prev next s1 zin zout zfit z1 s2 rl rend s3 epdf esvg epng} {
    pack .tb.$w -side left -padx 2 -pady 2
}

# SVG Viewer Widget
tkmcairo::svgview .sv \
    -width 880 -height 580 \
    -background {0.95 0.95 0.95}
pack .sv -fill both -expand 1 -padx 4 -pady 4

# Status
ttk::label .status -text "Open an SVG file" -anchor w
pack .status -fill x -padx 6 -pady 2

# Keyboard
bind . <Left>  svPrev
bind . <Right> svNext

# ============================================================
namespace eval ::sv {
    variable filelist {}
    variable fileindex -1
}

proc svOpen {} {
    set f [tk_getOpenFile \
        -filetypes {{"SVG Files" {.svg .SVG}} {"All Files" *}} \
        -title "Open SVG"]
    if {$f eq ""} return
    svLoadFile $f
}

proc svLoadFile {file} {
    set dir [file dirname [file normalize $file]]
    set all [lsort -unique [glob -nocomplain -directory $dir "*.svg" "*.SVG"]]
    set ::sv::filelist  $all
    set ::sv::fileindex [lsearch -exact $all [file normalize $file]]
    if {$::sv::fileindex < 0} { set ::sv::fileindex 0 }
    .sv load $file
    svUpdateStatus
}

proc svPrev {} {
    set n [llength $::sv::filelist]
    if {$n < 2} return
    set i [expr {($::sv::fileindex - 1 + $n) % $n}]
    svLoadFile [lindex $::sv::filelist $i]
}

proc svNext {} {
    set n [llength $::sv::filelist]
    if {$n < 2} return
    set i [expr {($::sv::fileindex + 1) % $n}]
    svLoadFile [lindex $::sv::filelist $i]
}

proc svUpdateStatus {} {
    set f   [.sv file]
    set sz  [.sv svgsize]
    set n   [llength $::sv::filelist]
    set idx $::sv::fileindex
    set nav [expr {$n > 1 ? "  \[$[expr {$idx+1}]/$n\]" : ""}]
    set r   [.sv renderer]
    .status configure -text \
        "[file tail $f]$nav  —  [lindex $sz 0]×[lindex $sz 1] px  —  $r"
}

proc svExport {fmt} {
    if {[.sv file] eq ""} return
    set base [file rootname [file tail [.sv file]]]
    set f [tk_getSaveFile \
        -initialfile "${base}_export.$fmt" \
        -defaultextension .$fmt \
        -title "Export as [string toupper $fmt]"]
    if {$f eq ""} return
    .sv export $f
    .status configure -text "Exported: $f"
}

# Drag & Drop
catch {
    package require tkdnd
    tkdnd::drop_target register .sv.lbl *
    bind .sv.lbl <<Drop:DND_Files>> { svLoadFile [lindex %D 0] }
}

after idle { .sv redraw }
