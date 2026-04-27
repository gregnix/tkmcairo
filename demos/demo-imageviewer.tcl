#!/usr/bin/env wish
# demo-imageviewer.tcl — tkmcairo::imageviewer widget demo
#
# Shows: full image viewer widget — open, navigate, zoom, pan, export.
# All wrapped behind a single tkmcairo::imageviewer .iv command.
#
# Compare with the application-style code that was here before 0.1.1 —
# all of that logic now lives inside the imageviewer module.
#
# Requirements: tclmcairo, tkmcairo::imageviewer
# Optional: imgtools (for high-quality scaling), Img (for native JPEG)

package require Tk

set _dir [file dirname [file normalize [info script]]]
tcl::tm::path add [file join $_dir .. tcl]
if {[info exists env(TCLMCAIRO_LIBDIR)]} {
    lappend auto_path $env(TCLMCAIRO_LIBDIR)
    tcl::tm::path add $env(TCLMCAIRO_LIBDIR)
}

package require tkmcairo::imageviewer

wm title    . "tkmcairo::imageviewer"
wm geometry . 900x650

# Create the widget — toolbar is built-in
tkmcairo::imageviewer .iv -width 900 -height 600
pack .iv -fill both -expand 1

# Keyboard shortcuts at the toplevel
bind . <Left>      {.iv prev}
bind . <Right>     {.iv next}
bind . <plus>      {.iv zoom 1.25}
bind . <minus>     {.iv zoom 0.8}
bind . <Key-1>     {.iv zoom1}
bind . <Key-f>     {.iv fit}
bind . <Control-o> {.iv open}

# Drag & Drop support (if tkdnd is available)
catch {
    package require tkdnd
    tkdnd::drop_target register .iv *
    bind .iv <<Drop:DND_Files>> { .iv load [lindex %D 0] }
}

# Optional: load an image from the command line
if {[llength $argv] > 0 && [file exists [lindex $argv 0]]} {
    .iv load [lindex $argv 0]
}
