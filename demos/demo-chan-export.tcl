#!/usr/bin/env wish
# demo-chan-export.tcl — streaming export through Tcl channels
#
# Demonstrates the -chan / -format export API added in tkmcairo 0.1.1.
# Three patterns are shown side by side:
#
#   1. Tempfile + read       — write to file, read back, show metadata
#   2. In-memory chan        — refchan/memchan, capture bytes in a Tcl var
#   3. Pipeline to subprocess — pipe directly into another program
#
# All three avoid the old "topng -> Tcl string -> file write" round-trip.
#
# Requirements: tclmcairo, tkmcairo::surface

package require Tk

set _dir [file dirname [file normalize [info script]]]
tcl::tm::path add [file join $_dir .. tcl]
if {[info exists env(TCLMCAIRO_LIBDIR)]} {
    lappend auto_path $env(TCLMCAIRO_LIBDIR)
    tcl::tm::path add $env(TCLMCAIRO_LIBDIR)
}

package require tkmcairo::surface

# ----------------------------------------------------------------
# A small Cairo drawing the demos export
# ----------------------------------------------------------------
proc drawSample {ctx w h} {
    # Background gradient
    $ctx gradient_linear bg 0 0 $w $h \
        {{0 0.15 0.20 0.45 1} {1 0.45 0.55 0.85 1}}
    $ctx rect 0 0 $w $h -fillname bg

    # Some shapes
    $ctx circle [expr {$w * 0.30}] [expr {$h * 0.45}] 80 \
        -fill {1 0.7 0.2 0.85}
    $ctx rect [expr {$w * 0.50}] [expr {$h * 0.30}] 180 100 \
        -fill {0.2 0.8 0.4 0.7} -radius 12

    # Title text
    $ctx text [expr {$w / 2}] [expr {$h * 0.85}] \
        "tkmcairo -chan export" \
        -font "Sans Bold 22" -color {1 1 1} -anchor center
}

# ----------------------------------------------------------------
# UI
# ----------------------------------------------------------------
wm title    . "tkmcairo channel export"
wm geometry . 720x600

ttk::frame .top -padding {10 10 10 4}
pack .top -side top -fill x

ttk::label .top.t -text "tkmcairo::surface  -chan export demo" \
    -font {Sans 14 bold}
pack .top.t -side left

# The surface that draws our sample
tkmcairo::surface .surf -width 700 -height 360 \
    -drawcommand {drawSample $ctx $w $h}
pack .surf -side top -padx 10 -pady 5

# Action buttons + status area
ttk::frame .bot -padding 10
pack .bot -side top -fill both -expand 1

ttk::button .bot.b1 -text "1. Tempfile + read"   \
    -command demo1_tempfile
ttk::button .bot.b2 -text "2. In-memory chan"    \
    -command demo2_memchan
ttk::button .bot.b3 -text "3. Pipe to | wc -c"   \
    -command demo3_pipeline

pack .bot.b1 .bot.b2 .bot.b3 -side left -padx 4

# Status / result text box
ttk::label .stat -text "Click a button above to run a demo" \
    -anchor w -padding {12 6}
pack .stat -side top -fill x

text .out -height 18 -wrap word -font {Monospace 10} \
    -background "#1a1a1a" -foreground "#dcdcdc" -borderwidth 0
pack .out -side top -fill both -expand 1 -padx 10 -pady {0 10}
.out insert end "Ready.\n"
.out configure -state disabled

proc say {msg} {
    .out configure -state normal
    .out insert end "$msg\n"
    .out see end
    .out configure -state disabled
}
proc clearout {} {
    .out configure -state normal
    .out delete 1.0 end
    .out configure -state disabled
}

# ================================================================
# Demo 1 — Tempfile, then read back
# ================================================================
# Use case: hand the file off to another program (an email attachment,
# a print spooler, a content-addressed store).  Channel target is a
# file handle opened in 'wb' mode, exactly like 'open file wb'.
proc demo1_tempfile {} {
    clearout
    say "=== Demo 1: tempfile via -chan ==="

    set tmp [file join /tmp "tkmcairo_chan_demo1_[pid]_[clock microseconds].pdf"]
    set ch [open $tmp wb]
    fconfigure $ch -translation binary

    say "Opening   $tmp"
    say "Streaming surface as PDF to channel..."

    .surf export -chan $ch -format pdf
    close $ch

    set sz [file size $tmp]
    say [format "Done.  Wrote %d bytes (%.1f KB)" $sz [expr {$sz / 1024.0}]]

    # Inspect the first few bytes — every PDF starts with %PDF-
    set fh [open $tmp rb]
    set head [read $fh 8]
    close $fh
    say "Header:   [string range $head 0 4]   (PDF magic)"

    # Cleanup
    file delete -force $tmp
    say "(temp file removed)"
    .stat configure -text "Demo 1 complete: PDF streamed to tempfile, $sz bytes"
}

# ================================================================
# Demo 2 — In-memory channel, capture bytes in a Tcl variable
# ================================================================
# Use case: HTTP response body, websocket frame, message queue payload.
# The bytes never touch disk.  Tcl 8.6+ provides 'chan create' for
# fully scriptable channels; we use a simpler tempfile-backed approach
# that works on every Tcl 8.6+ install without the reflected-channel
# extension dance.
proc demo2_memchan {} {
    clearout
    say "=== Demo 2: in-memory PNG bytes ==="

    # Create a memory-like channel via tempfile that we read back.
    # On Tcl 8.6+ you could also use [chan create] for true in-memory.
    set tmp [file tempfile path]
    fconfigure $tmp -translation binary

    say "Streaming surface as PNG into memory..."
    .surf export -chan $tmp -format png

    # Rewind and read the bytes into a Tcl variable
    seek $tmp 0
    set bytes [read $tmp]
    close $tmp
    file delete -force $path

    set len [string length $bytes]
    say [format "Captured  %d bytes in Tcl variable" $len]

    # Verify PNG signature
    binary scan [string range $bytes 0 7] H16 hex
    set ok [expr {$hex eq "89504e470d0a1a0a"}]
    say "Signature [string range $hex 0 15]   (PNG magic: $ok)"

    # Now we could base64-encode for HTTP, send via socket, etc.
    set b64 [binary encode base64 [string range $bytes 0 30]]
    say "Base64 prefix: $b64..."

    .stat configure -text "Demo 2 complete: $len bytes captured in memory"
}

# ================================================================
# Demo 3 — Pipeline to a sub-process
# ================================================================
# Use case: feed the export directly into pdftk, gs, ImageMagick, etc.
# Tcl's [open "|cmd"] gives us a write pipeline; tkmcairo streams into
# the program's stdin.
proc demo3_pipeline {} {
    clearout
    say "=== Demo 3: pipeline to subprocess ==="

    if {[auto_execok wc] eq ""} {
        say "Skipped: 'wc' not on PATH (this demo expects a Unix-ish system)"
        .stat configure -text "Demo 3 needs 'wc' on PATH"
        return
    }

    # 'wc -c' just counts bytes — a stand-in for any real consumer.
    say "Opening pipe:  | wc -c"
    set pipe [open "|wc -c" r+]
    fconfigure $pipe -translation binary

    say "Streaming surface as PDF into pipeline..."
    .surf export -chan $pipe -format pdf

    # Half-close so wc sees EOF on stdin and produces output
    chan close $pipe write

    # Read wc's count off stdout
    set count [string trim [read $pipe]]
    close $pipe

    say "wc -c reported: $count bytes"
    say ""
    say "In a real pipeline you might use:"
    say "  | gs -sDEVICE=pdfwrite -o out.pdf -        (compress)"
    say "  | pdftk - output signed.pdf owner_pw ...   (sign)"
    say "  | qpdf --linearize - linear.pdf            (web-optimise)"

    .stat configure -text "Demo 3 complete: piped $count bytes through wc -c"
}
