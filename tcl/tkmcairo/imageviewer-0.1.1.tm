# tkmcairo::imageviewer 0.1.1
#
# An image viewer widget — open, navigate, zoom, pan, export.
# Uses Tk Canvas internally for fast pan; tclmcairo for image loading
# (via image_load + toppm), JPEG support without Img, and high-quality
# Cairo-based vector export. imgtools is used for high-quality scaling.
#
# Minimal usage:
#     package require tkmcairo::imageviewer
#     tkmcairo::imageviewer .iv
#     pack .iv -fill both -expand 1
#     .iv load /path/to/picture.png
#
# Construction options:
#     -width W            initial width (default 800)
#     -height H           initial height (default 600)
#     -file path          if set, load this file at construction
#     -background color   canvas background (default "#262626")
#     -toolbar 0|1        show built-in toolbar (default 1)
#     -zoom-min  factor   smallest allowed zoom factor (default 0.05)
#     -zoom-max  factor   largest allowed zoom factor (default 20.0)
#
# Widget commands:
#     $w load file              load an image, populate filelist from sibling files
#     $w open                   pop up tk_getOpenFile and load the selection
#     $w prev / $w next         step through filelist (wraps at edges)
#     $w filelist ?list?        get or set the navigation list
#     $w fileindex              current index in filelist
#     $w fit                    zoom-fit to widget area
#     $w zoom1                  reset to 100 %
#     $w zoom factor ?cx cy?    multiply current zoom by factor
#     $w pan dx dy              shift the displayed image
#     $w info                   list of {file width height zoom}
#     $w export filename        write current image as PDF/SVG/PS/EPS/PNG
#     $w export -chan $ch -format fmt   stream to channel
#     $w configure / $w cget    standard option access
#     $w toolbar 0|1            show/hide the built-in toolbar at runtime
#
# Tk Canvas is intentional in 0.1.1 — direct Tk photo blits are
# faster for pan than going through Cairo + toppm + photo each frame.
# A surface-based variant is on the 0.3 roadmap.

# Hard dependency: tclmcairo is required for image_size, image_load,
# JPEG decoding fallback, and Cairo-based vector export.
package require tclmcairo

namespace eval ::tkmcairo::imageviewer {}

# ============================================================
# Constructor
# ============================================================
proc ::tkmcairo::imageviewer {w args} {
    if {[winfo exists $w]} {
        error "tkmcairo::imageviewer: window $w already exists"
    }

    array set opts {
        -width      800
        -height     600
        -file       ""
        -background "#262626"
        -toolbar    1
        -zoom-min   0.05
        -zoom-max   20.0
    }
    foreach {k v} $args {
        if {![info exists opts($k)]} {
            error "tkmcairo::imageviewer: unknown option $k"
        }
        set opts($k) $v
    }

    # Container frame holds toolbar (optional) + canvas + status
    ttk::frame $w -width $opts(-width) -height $opts(-height)

    # Per-instance state
    set ns ::tkmcairo::imageviewer::S_$w
    namespace eval $ns {}

    foreach k [array names opts] { set ${ns}::opts($k) $opts($k) }

    set ${ns}::file        ""
    set ${ns}::filelist    {}
    set ${ns}::fileindex   -1
    set ${ns}::imgW        0
    set ${ns}::imgH        0
    set ${ns}::zoom        1.0
    set ${ns}::panX        0.0
    set ${ns}::panY        0.0
    set ${ns}::dragging    0
    set ${ns}::dragX       0
    set ${ns}::dragY       0
    set ${ns}::redrawJob   ""
    set ${ns}::origPhoto   ""
    set ${ns}::scaledPhoto ""
    set ${ns}::scaledW     0
    set ${ns}::scaledH     0
    set ${ns}::hasImg      [expr {![catch {package require Img}]}]
    set ${ns}::hasImgtools [expr {![catch {package require imgtools}]}]

    # Build sub-widgets
    ::tkmcairo::imageviewer::_buildUI $w

    # Widget command via rename + alias trick (same pattern as surface)
    rename $w ::tkmcairo::imageviewer::_frame__$w
    interp alias {} $w {} ::tkmcairo::imageviewer::_cmd $w

    # Cleanup when destroyed
    bind $w <Destroy> [list ::tkmcairo::imageviewer::_evDestroy $w %W $w]

    # Initial load if requested
    if {$opts(-file) ne ""} {
        after idle [list catch [list $w load $opts(-file)]]
    } else {
        after idle [list catch [list ::tkmcairo::imageviewer::_draw $w]]
    }

    return $w
}

# ============================================================
# UI construction
# ============================================================
proc ::tkmcairo::imageviewer::_buildUI {w} {
    set ns ::tkmcairo::imageviewer::S_$w

    # ----- Toolbar -----
    ttk::frame $w.tb
    ttk::button $w.tb.open  -text "Open..." -command [list $w open]
    ttk::button $w.tb.prev  -text "\u25C0"  -command [list $w prev]
    ttk::button $w.tb.next  -text "\u25B6"  -command [list $w next]
    ttk::separator $w.tb.s1 -orient vertical
    ttk::button $w.tb.zin   -text "Zoom +"  -command [list $w zoom 1.25]
    ttk::button $w.tb.zout  -text "Zoom \u2212" -command [list $w zoom 0.8]
    ttk::button $w.tb.zfit  -text "Fit"     -command [list $w fit]
    ttk::button $w.tb.z1    -text "1:1"     -command [list $w zoom1]
    ttk::separator $w.tb.s2 -orient vertical
    ttk::button $w.tb.epdf  -text "Export PDF" -command [list ::tkmcairo::imageviewer::_exportDialog $w pdf]
    ttk::button $w.tb.esvg  -text "Export SVG" -command [list ::tkmcairo::imageviewer::_exportDialog $w svg]
    ttk::button $w.tb.epng  -text "Export PNG" -command [list ::tkmcairo::imageviewer::_exportDialog $w png]
    foreach b {open prev next s1 zin zout zfit z1 s2 epdf esvg epng} {
        pack $w.tb.$b -side left -padx 2 -pady 2
    }

    # ----- Canvas -----
    canvas $w.c -bg [set ${ns}::opts(-background)] -highlightthickness 0

    # ----- Status -----
    ttk::label $w.status -text "Open an image file (PNG or JPEG)" -anchor w

    # Layout — toolbar visibility is honoured at end
    if {[set ${ns}::opts(-toolbar)]} {
        pack $w.tb     -fill x    -padx 4 -pady 4
    }
    pack $w.c      -fill both -expand 1 -padx 4 -pady 4
    pack $w.status -fill x   -padx 6 -pady 2

    # ----- Bindings -----
    bind $w.c <ButtonPress-1>   [list ::tkmcairo::imageviewer::_dragStart  $w %x %y]
    bind $w.c <B1-Motion>       [list ::tkmcairo::imageviewer::_dragMotion $w %x %y]
    bind $w.c <ButtonRelease-1> [list set ${ns}::dragging 0]
    bind $w.c <MouseWheel>      [list ::tkmcairo::imageviewer::_wheelZoom $w %D %x %y]
    bind $w.c <Button-4>        [list ::tkmcairo::imageviewer::_wheelZoom $w  120 %x %y]
    bind $w.c <Button-5>        [list ::tkmcairo::imageviewer::_wheelZoom $w -120 %x %y]
    bind $w.c <Configure>       [list ::tkmcairo::imageviewer::_redrawDelayed $w]
}

# ============================================================
# Cleanup
# ============================================================
proc ::tkmcairo::imageviewer::_evDestroy {w evwin self} {
    # Only fire when the imageviewer frame itself is destroyed,
    # not for child widgets inside it. (Same %W filter as scene.)
    if {$evwin ne $self} return
    set ns ::tkmcairo::imageviewer::S_$w
    if {![namespace exists $ns]} return
    catch { after cancel [set ${ns}::redrawJob] }
    catch { if {[set ${ns}::origPhoto]   ne ""} { image delete [set ${ns}::origPhoto] } }
    catch { if {[set ${ns}::scaledPhoto] ne ""} { image delete [set ${ns}::scaledPhoto] } }
    catch { namespace delete $ns }
    catch { interp alias {} $w {} }
}

# ============================================================
# Widget command dispatch
# ============================================================
proc ::tkmcairo::imageviewer::_cmd {w subcmd args} {
    switch -- $subcmd {
        load        { _load     $w {*}$args }
        open        { _open     $w }
        prev        { _step     $w -1 }
        next        { _step     $w +1 }
        filelist    { _filelist $w {*}$args }
        fileindex   { return [set ::tkmcairo::imageviewer::S_${w}::fileindex] }
        fit         { _fit      $w }
        zoom1       { _zoom1    $w }
        zoom        { _zoom     $w {*}$args }
        pan         { _pan      $w {*}$args }
        info        { _info     $w }
        export      { _export   $w {*}$args }
        toolbar     { _toolbar  $w {*}$args }
        configure   { _configure $w {*}$args }
        cget        { _cget     $w {*}$args }
        redraw      { _draw     $w }
        default     { error "tkmcairo::imageviewer: unknown subcommand: $subcmd" }
    }
}

# ============================================================
# Image loading helpers
# ============================================================

# Load an image without a usable Img package — uses tclmcairo's libjpeg
# binding to decode JPEG, then PPM as the photo bridge.
proc ::tkmcairo::imageviewer::_makePhotoFromTclmcairo {file} {
    set ctx [tclmcairo::new 1 1]
    if {[catch {set id [$ctx image_load $file]} e]} {
        $ctx destroy
        return -code error $e
    }
    lassign [$ctx image_info $id] iw ih
    $ctx image_free $id
    $ctx destroy
    if {$iw < 1 || $ih < 1} {
        return -code error "invalid size ${iw}x${ih}"
    }
    set ctx [tclmcairo::new $iw $ih]
    if {[catch {set id [$ctx image_load $file]} e]} {
        $ctx destroy
        return -code error $e
    }
    if {[catch {$ctx image_blit $id 0 0} e]} {
        $ctx image_free $id; $ctx destroy
        return -code error $e
    }
    if {[catch {$ctx toppm} ppm]} {
        # On error, $ppm holds the error message.
        $ctx image_free $id; $ctx destroy
        return -code error $ppm
    }
    # On success, $ppm holds the PPM bytes.
    $ctx image_free $id
    $ctx destroy
    set ph [image create photo]
    if {![catch {$ph put $ppm -format ppm}]} {
        return [list $ph $iw $ih]
    }
    # Some Tk versions can't accept PPM via 'put' — round-trip via tempfile
    set tdir [_tmpbase]
    set tmp  [file join $tdir "tcliv_[pid]_[clock microseconds].ppm"]
    if {[catch {
        set fa [open $tmp wb]
        fconfigure $fa -translation binary
        puts -nonewline $fa $ppm
        close $fa
        image delete $ph
        set ph [image create photo -file $tmp]
    } e]} {
        catch {image delete $ph}
        catch {file delete -force $tmp}
        return -code error "PPM/photo: $e"
    }
    catch {file delete -force $tmp}
    return [list $ph $iw $ih]
}

proc ::tkmcairo::imageviewer::_tmpbase {} {
    if {[info exists ::env(TMPDIR)] && [file isdirectory $::env(TMPDIR)]} {
        return $::env(TMPDIR)
    }
    if {[file isdirectory /tmp]}      { return /tmp }
    if {[info exists ::env(TEMP)] && [file isdirectory $::env(TEMP)]} {
        return $::env(TEMP)
    }
    return [pwd]
}

# ============================================================
# Public actions
# ============================================================
proc ::tkmcairo::imageviewer::_load {w file} {
    set ns ::tkmcairo::imageviewer::S_$w
    if {![file exists $file]} { error "no such file: $file" }

    # Get dimensions via tclmcairo (works for PNG and JPEG without Img)
    set tmp [tclmcairo::new 1 1]
    set iw 0; set ih 0
    catch { lassign [$tmp image_size $file] iw ih }
    $tmp destroy

    # Free old photos (defensively — names may exist with destroyed objects)
    catch { if {[set ${ns}::origPhoto]   ne ""} { image delete [set ${ns}::origPhoto] } }
    set ${ns}::origPhoto ""
    catch { if {[set ${ns}::scaledPhoto] ne ""} { image delete [set ${ns}::scaledPhoto] } }
    set ${ns}::scaledPhoto ""
    set ${ns}::scaledW 0
    set ${ns}::scaledH 0

    # Try Tk's native loaders first; fall back to tclmcairo PPM bridge.
    if {[catch {set ph [image create photo -file $file]} errMain]} {
        if {[catch {lassign [_makePhotoFromTclmcairo $file] ph xw xh} errFb]} {
            $w.status configure \
                -text "Load: $errMain | tclmcairo: $errFb"
            return
        }
        set ${ns}::imgW $xw
        set ${ns}::imgH $xh
    } else {
        if {$iw < 1} { set iw [image width  $ph] }
        if {$ih < 1} { set ih [image height $ph] }
        set ${ns}::imgW $iw
        set ${ns}::imgH $ih
    }
    set ${ns}::origPhoto $ph
    set ${ns}::file      $file
    set ${ns}::panX      0.0
    set ${ns}::panY      0.0

    # Build filelist from siblings if the user hasn't set one explicitly.
    # User can override later via "$w filelist {a.jpg b.png ...}".
    set dir [file dirname [file normalize $file]]
    set siblings [lsort -unique [concat \
        [glob -nocomplain -directory $dir "*.png"] \
        [glob -nocomplain -directory $dir "*.PNG"] \
        [glob -nocomplain -directory $dir "*.jpg"] \
        [glob -nocomplain -directory $dir "*.JPG"] \
        [glob -nocomplain -directory $dir "*.jpeg"] \
        [glob -nocomplain -directory $dir "*.JPEG"]]]
    set ${ns}::filelist  $siblings
    set ${ns}::fileindex [lsearch -exact $siblings [file normalize $file]]
    if {[set ${ns}::fileindex] < 0} { set ${ns}::fileindex 0 }

    _fit $w
    set n [llength $siblings]
    set idx [set ${ns}::fileindex]
    set nav [expr {$n > 1 ? "  \[[expr {$idx+1}]/$n\]" : ""}]
    $w.status configure \
        -text "[file tail $file]  ([set ${ns}::imgW] \u00d7 [set ${ns}::imgH] px)$nav"
}

proc ::tkmcairo::imageviewer::_open {w} {
    set f [tk_getOpenFile \
        -filetypes {{"Image Files" {.png .jpg .jpeg .PNG .JPG .JPEG}} {"All Files" *}} \
        -title "Open Image"]
    if {$f eq ""} return
    _load $w $f
}

proc ::tkmcairo::imageviewer::_step {w dir} {
    set ns ::tkmcairo::imageviewer::S_$w
    set n [llength [set ${ns}::filelist]]
    if {$n < 2} return
    set i [set ${ns}::fileindex]
    set i [expr {(($i + $dir) % $n + $n) % $n}]
    _load $w [lindex [set ${ns}::filelist] $i]
}

proc ::tkmcairo::imageviewer::_filelist {w args} {
    set ns ::tkmcairo::imageviewer::S_$w
    if {[llength $args] == 0} { return [set ${ns}::filelist] }
    set ${ns}::filelist [lindex $args 0]
    set ${ns}::fileindex \
        [lsearch -exact [set ${ns}::filelist] [set ${ns}::file]]
    if {[set ${ns}::fileindex] < 0} { set ${ns}::fileindex 0 }
    return [set ${ns}::filelist]
}

proc ::tkmcairo::imageviewer::_fit {w} {
    set ns ::tkmcairo::imageviewer::S_$w
    if {[set ${ns}::file] eq ""} return
    set cw [winfo width  $w.c]; if {$cw < 10} { set cw 880 }
    set ch [winfo height $w.c]; if {$ch < 10} { set ch 590 }
    set zw [expr {($cw - 10) / double([set ${ns}::imgW])}]
    set zh [expr {($ch - 10) / double([set ${ns}::imgH])}]
    set ${ns}::zoom [expr {min($zw, $zh, 1.0)}]
    set ${ns}::panX 0.0
    set ${ns}::panY 0.0
    _draw $w
}

proc ::tkmcairo::imageviewer::_zoom1 {w} {
    set ns ::tkmcairo::imageviewer::S_$w
    set ${ns}::zoom 1.0
    set ${ns}::panX 0.0
    set ${ns}::panY 0.0
    _draw $w
}

proc ::tkmcairo::imageviewer::_zoom {w factor args} {
    set ns ::tkmcairo::imageviewer::S_$w
    set lo [set ${ns}::opts(-zoom-min)]
    set hi [set ${ns}::opts(-zoom-max)]
    set z  [expr {[set ${ns}::zoom] * double($factor)}]
    set ${ns}::zoom [expr {max($lo, min($hi, $z))}]
    _redrawDelayed $w
}

proc ::tkmcairo::imageviewer::_pan {w dx dy} {
    set ns ::tkmcairo::imageviewer::S_$w
    set ${ns}::panX [expr {[set ${ns}::panX] + double($dx)}]
    set ${ns}::panY [expr {[set ${ns}::panY] + double($dy)}]
    _draw $w
}

proc ::tkmcairo::imageviewer::_info {w} {
    set ns ::tkmcairo::imageviewer::S_$w
    return [list \
        [set ${ns}::file] \
        [set ${ns}::imgW] \
        [set ${ns}::imgH] \
        [set ${ns}::zoom]]
}

# ============================================================
# Mouse handlers
# ============================================================
proc ::tkmcairo::imageviewer::_dragStart {w x y} {
    set ns ::tkmcairo::imageviewer::S_$w
    set ${ns}::dragging 1
    set ${ns}::dragX $x
    set ${ns}::dragY $y
}

proc ::tkmcairo::imageviewer::_dragMotion {w x y} {
    set ns ::tkmcairo::imageviewer::S_$w
    if {![set ${ns}::dragging]} return
    set dx [expr {$x - [set ${ns}::dragX]}]
    set dy [expr {$y - [set ${ns}::dragY]}]
    set ${ns}::panX [expr {[set ${ns}::panX] + $dx}]
    set ${ns}::panY [expr {[set ${ns}::panY] + $dy}]
    set ${ns}::dragX $x
    set ${ns}::dragY $y
    _draw $w
}

proc ::tkmcairo::imageviewer::_wheelZoom {w delta x y} {
    set ns ::tkmcairo::imageviewer::S_$w
    set f  [expr {$delta > 0 ? 1.15 : 0.87}]
    _zoom $w $f
}

# ============================================================
# Toolbar and configuration
# ============================================================
proc ::tkmcairo::imageviewer::_toolbar {w {show ""}} {
    set ns ::tkmcairo::imageviewer::S_$w
    if {$show eq ""} { return [set ${ns}::opts(-toolbar)] }
    set show [expr {!!$show}]
    set ${ns}::opts(-toolbar) $show
    if {$show} {
        # Pack only if not already mapped — winfo manager returns "" if not packed
        if {[winfo manager $w.tb] eq ""} {
            pack $w.tb -fill x -padx 4 -pady 4 -before $w.c
        }
    } else {
        catch {pack forget $w.tb}
    }
    return $show
}

proc ::tkmcairo::imageviewer::_configure {w args} {
    set ns ::tkmcairo::imageviewer::S_$w
    if {[llength $args] == 0} {
        return [array get ${ns}::opts]
    }
    foreach {k v} $args {
        if {![info exists ${ns}::opts($k)]} {
            error "tkmcairo::imageviewer: unknown option $k"
        }
        set ${ns}::opts($k) $v
        switch -- $k {
            -background { catch {$w.c configure -bg $v} }
            -toolbar    { _toolbar $w $v }
            -file       { if {$v ne ""} { _load $w $v } }
        }
    }
}

proc ::tkmcairo::imageviewer::_cget {w opt} {
    set ns ::tkmcairo::imageviewer::S_$w
    if {![info exists ${ns}::opts($opt)]} {
        error "tkmcairo::imageviewer: unknown option $opt"
    }
    return [set ${ns}::opts($opt)]
}

# ============================================================
# Drawing
# ============================================================
proc ::tkmcairo::imageviewer::_redrawDelayed {w} {
    set ns ::tkmcairo::imageviewer::S_$w
    catch { after cancel [set ${ns}::redrawJob] }
    set ${ns}::redrawJob \
        [after 50 [list catch [list ::tkmcairo::imageviewer::_draw $w]]]
}

proc ::tkmcairo::imageviewer::_draw {w} {
    if {![winfo exists $w] || ![winfo exists $w.c]} return
    set ns ::tkmcairo::imageviewer::S_$w
    set c  $w.c

    if {[set ${ns}::file] eq ""} {
        $c delete all
        set cw [winfo width  $c]
        set ch [winfo height $c]
        if {$cw < 10} { set cw 200 }
        if {$ch < 10} { set ch 200 }
        $c create text [expr {$cw / 2}] [expr {$ch / 2}] \
            -text "Open an image file (PNG or JPEG)" \
            -fill "#888" -font "Sans 16" -anchor center
        return
    }

    set iw [set ${ns}::imgW]
    set ih [set ${ns}::imgH]
    set z  [set ${ns}::zoom]
    set cw [winfo width  $c]
    set ch [winfo height $c]
    if {$cw < 10} { set cw 880 }
    if {$ch < 10} { set ch 590 }

    set dw [expr {max(1, int($iw * $z))}]
    set dh [expr {max(1, int($ih * $z))}]
    set x  [expr {int(($cw - $dw) / 2.0 + [set ${ns}::panX])}]
    set y  [expr {int(($ch - $dh) / 2.0 + [set ${ns}::panY])}]

    # Re-scale photo only if zoom changed
    if {[set ${ns}::scaledPhoto] eq "" \
        || [set ${ns}::scaledW] != $dw \
        || [set ${ns}::scaledH] != $dh} {
        if {[set ${ns}::scaledPhoto] ne ""} {
            image delete [set ${ns}::scaledPhoto]
        }
        set sp [image create photo]
        set ${ns}::scaledPhoto $sp
        set scaledOk 0
        if {[set ${ns}::hasImgtools]} {
            foreach m {lanczos3 lanczos2 catrom linear} {
                if {![catch {
                    ::imgtools::scale [set ${ns}::origPhoto] \
                        ${dw}x${dh} -interpolation $m $sp
                }]} { set scaledOk 1; break }
            }
        }
        if {!$scaledOk} {
            # Fallback: Tk-native subsample/zoom (no high-quality filter)
            $sp blank
            $sp copy [set ${ns}::origPhoto]
            # Don't try fancy: just keep the source if scaling fails
        }
        set ${ns}::scaledW $dw
        set ${ns}::scaledH $dh
    }

    $c delete all
    $c create image $x $y -anchor nw \
        -image [set ${ns}::scaledPhoto]

    # Info overlay
    set info [format "%s  |  %d \u00d7 %d px  |  zoom %.0f%%" \
        [file tail [set ${ns}::file]] $iw $ih [expr {$z * 100}]]
    set tw [expr {[string length $info] * 7 + 22}]
    $c create rectangle 6 [expr {$ch - 30}] $tw [expr {$ch - 8}] \
        -fill "#000" -stipple gray50 -outline ""
    $c create text 14 [expr {$ch - 14}] -text $info \
        -fill "#f0f0f0" -font "Sans 11" -anchor w
}

# ============================================================
# Export
# ============================================================
proc ::tkmcairo::imageviewer::_export {w args} {
    set ns ::tkmcairo::imageviewer::S_$w
    if {[set ${ns}::file] eq ""} {
        error "tkmcairo::imageviewer export: no image loaded"
    }

    set file ""
    set chan ""
    set fmt  ""
    if {[llength $args] == 1} {
        set file [lindex $args 0]
    } else {
        foreach {k v} $args {
            switch -- $k {
                -chan   { set chan $v }
                -format { set fmt  $v }
                -file   { set file $v }
                default { error "tkmcairo::imageviewer export: unknown option $k" }
            }
        }
    }

    if {$file eq "" && $chan eq ""} {
        error "tkmcairo::imageviewer export: need filename or -chan"
    }

    set iw [set ${ns}::imgW]
    set ih [set ${ns}::imgH]

    # If exporting to channel, pick mode from -format; else from extension
    if {$chan ne ""} {
        if {$fmt eq ""} { set fmt png }
        set mode $fmt
    } else {
        set ext [string tolower [file extension $file]]
        set mode [switch $ext {
            .pdf {expr {"pdf"}} .svg {expr {"svg"}}
            .ps  {expr {"ps"}}  .eps {expr {"eps"}}
            default {expr {"png"}}
        }]
    }

    # Vector or PNG to a real file: tclmcairo handles directly
    if {$file ne ""} {
        if {$mode eq "png"} {
            set ctx [tclmcairo::new $iw $ih]
            $ctx image [set ${ns}::file] 0 0
            $ctx save $file
            $ctx destroy
        } else {
            set ctx [tclmcairo::new $iw $ih -mode $mode -file $file]
            $ctx image [set ${ns}::file] 0 0
            $ctx finish
            $ctx destroy
        }
        return $file
    }

    # Channel target
    if {$mode eq "png"} {
        set ctx [tclmcairo::new $iw $ih]
        $ctx image [set ${ns}::file] 0 0
        if {[catch {$ctx save -chan $chan -format png} _err]} {
            # Fallback for older tclmcairo without save -chan
            if {![catch {$ctx topng} bytes]} {
                fconfigure $chan -translation binary
                puts -nonewline $chan $bytes
            }
        }
        $ctx destroy
        return ""
    }

    # Vector to channel: tempfile then fcopy
    set tmpf [file join [_tmpbase] \
        "tkmcairo_iv_export_[pid]_[clock microseconds].$mode"]
    set ctx [tclmcairo::new $iw $ih -mode $mode -file $tmpf]
    $ctx image [set ${ns}::file] 0 0
    catch {$ctx finish}
    $ctx destroy
    if {[file exists $tmpf]} {
        set fh [open $tmpf rb]
        fconfigure $fh   -translation binary
        fconfigure $chan -translation binary
        fcopy $fh $chan
        close $fh
        catch {file delete -force $tmpf}
    }
    return ""
}

proc ::tkmcairo::imageviewer::_exportDialog {w fmt} {
    set ns ::tkmcairo::imageviewer::S_$w
    if {[set ${ns}::file] eq ""} return
    set base [file rootname [file tail [set ${ns}::file]]]
    set f [tk_getSaveFile \
        -initialfile     "${base}_export.$fmt" \
        -defaultextension .$fmt \
        -title           "Export as [string toupper $fmt]"]
    if {$f eq ""} return
    if {[catch {_export $w $f} err]} {
        $w.status configure -text "Export failed: $err"
        return
    }
    $w.status configure -text "Exported: $f"
}

package provide tkmcairo::imageviewer 0.1.1
