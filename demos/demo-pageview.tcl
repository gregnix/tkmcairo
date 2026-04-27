#!/usr/bin/env wish
# demo-pageview.tcl — PDF Viewer Demo

package require Tk

set _dir [file dirname [file normalize [info script]]]
tcl::tm::path add [file join $_dir .. tcl]
if {[info exists env(TCLMCAIRO_LIBDIR)]} {
    lappend auto_path $env(TCLMCAIRO_LIBDIR)
    tcl::tm::path add $env(TCLMCAIRO_LIBDIR)
}

package require tkmcairo::pageview

wm title . "tkmcairo PDF Viewer"
wm geometry . 900x950

# Menu / toolbar
ttk::frame .tb
pack .tb -fill x -padx 4 -pady 4
ttk::button .tb.open -text "Open PDF..." -command pvOpen
pack .tb.open -side left -padx 2

# pageview Widget
tkmcairo::pageview .pv \
    -width  860 \
    -height 880 \
    -dpi    150 \
    -bookmarks 1

pack .pv -fill both -expand 1 -padx 4 -pady 4

# Keyboard
bind . <Left>  {.pv prev}
bind . <Right> {.pv next}
bind . <Prior> {.pv prev}
bind . <Next>  {.pv next}
bind . <Home>  {.pv first}
bind . <End>   {.pv last}

proc pvOpen {} {
    set f [tk_getOpenFile \
        -filetypes {{"PDF Files" {.pdf .PDF}} {"All Files" *}} \
        -title "Open PDF"]
    if {$f eq ""} return
    .pv load $f
}

# Drag & Drop
catch {
    package require tkdnd
    tkdnd::drop_target register .pv *
    bind .pv <<Drop:DND_Files>> { .pv load [lindex %D 0] }
}
