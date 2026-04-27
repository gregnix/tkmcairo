#!/usr/bin/env wish
# demo-imageviewer.tcl — Image viewer using imgtools + tclmcairo (export only)

package require Tk

set _dir [file dirname [file normalize [info script]]]
tcl::tm::path add [file join $_dir .. tcl]
if {[info exists env(TCLMCAIRO_LIBDIR)]} {
    lappend auto_path $env(TCLMCAIRO_LIBDIR)
    tcl::tm::path add $env(TCLMCAIRO_LIBDIR)
}
# tclmcairo: Dimensionen, JPEG-Decode (libjpeg) + PPM, falls kein brauchbares Img
package require tclmcairo

# ============================================================
# State
# ============================================================
namespace eval ::iv {
    variable file      ""
    variable filelist  {}
    variable fileindex -1
    variable imgW      0
    variable imgH      0
    variable zoom      1.0
    variable panX      0.0
    variable panY      0.0
    variable dragging  0
    variable dragX     0
    variable dragY     0
    variable redrawJob ""
    # Tk photo images
    variable origPhoto ""
    variable scaledPhoto ""
    variable scaledW   0
    variable scaledH   0
    variable hasImg    0
}
# System-Img (img::jpeg/…) — optional; bei jpegtcl-Version/ABI-Konflikten: aus, Nutzung tclmcairo
if {![catch {package require Img}]} {
    set ::iv::hasImg 1
} else {
    set ::iv::hasImg 0
}
package require imgtools

# Photo ohne [image create photo -file]: libjpeg in tclmcairo → PPM → photo
proc ivMakePhotoFromTclmcairo {file} {
    set ctx [tclmcairo::new 1 1]
    if {[catch {set id [$ctx image_load $file]} e]} {
        $ctx destroy
        return -code error $e
    }
    lassign [$ctx image_info $id] w h
    $ctx image_free $id
    $ctx destroy
    if {$w < 1 || $h < 1} {
        return -code error "invalid size ${w}x${h}"
    }
    set ctx [tclmcairo::new $w $h]
    if {[catch {set id [$ctx image_load $file]} e2]} {
        $ctx destroy
        return -code error $e2
    }
    if {[catch {$ctx image_blit $id 0 0} e3]} {
        $ctx image_free $id
        $ctx destroy
        return -code error $e3
    }
    if {[catch {set ppm [$ctx toppm]} e4]} {
        $ctx image_free $id
        $ctx destroy
        return -code error $e4
    }
    $ctx image_free $id
    $ctx destroy
    set ph [image create photo]
    if {![catch {$ph put $ppm -format ppm}]} {
        return [list $ph $w $h]
    }
    if {![info exists ::env(TMPDIR)] || $::env(TMPDIR) eq ""} {
        set tdir /tmp
    } else {
        set tdir $::env(TMPDIR)
    }
    set t [file join $tdir tcliv_[pid]_[clock millis].ppm]
    if {[catch {
        set fa [open $t wb]
        puts -nonewline $fa $ppm
        close $fa
        image delete $ph
        set ph [image create photo -file $t]
    } e5]} {
        catch {image delete $ph}
        file delete -force $t
        return -code error "PPM/photo: $e5"
    }
    file delete -force $t
    return [list $ph $w $h]
}

# ============================================================
# UI
# ============================================================
wm title . "tkmcairo Image Viewer"
wm geometry . 900x650

ttk::frame .tb
pack .tb -fill x -padx 4 -pady 4

ttk::button .tb.open -text "Open..."  -command ivOpen
ttk::button .tb.prev -text "◀"        -command ivPrev
ttk::button .tb.next -text "▶"        -command ivNext
ttk::separator .tb.s1 -orient vertical
ttk::button .tb.zin  -text "Zoom +"   -command {ivZoom 1.25}
ttk::button .tb.zout -text "Zoom −"   -command {ivZoom 0.8}
ttk::button .tb.zfit -text "Fit"      -command ivFit
ttk::button .tb.z1   -text "1:1"      -command ivZoom1
ttk::separator .tb.s2 -orient vertical
ttk::button .tb.epdf -text "Export PDF" -command {ivExport pdf}
ttk::button .tb.esvg -text "Export SVG" -command {ivExport svg}
ttk::button .tb.epng -text "Export PNG" -command {ivExport png}

foreach w {open prev next s1 zin zout zfit z1 s2 epdf esvg epng} {
    pack .tb.$w -side left -padx 2 -pady 2
}

# Canvas als Anzeige (kein surface — kein toppm/topng Overhead)
canvas .c -bg "#262626" -highlightthickness 0
pack .c -fill both -expand 1 -padx 4 -pady 4

ttk::label .status -text "Open an image file (PNG or JPEG)" -anchor w
pack .status -fill x -padx 6 -pady 2

# Mouse bindings
bind .c <ButtonPress-1>   {ivDragStart %x %y}
bind .c <B1-Motion>       {ivDragMotion %x %y}
bind .c <ButtonRelease-1> {set ::iv::dragging 0}
bind .c <MouseWheel>      {ivWheelZoom %D %x %y}
bind .c <Button-4>        {ivWheelZoom  120 %x %y}
bind .c <Button-5>        {ivWheelZoom -120 %x %y}
bind . <Left>  ivPrev
bind . <Right> ivNext
bind . <Configure> {ivRedrawDelayed}

# ============================================================
# Draw — direkt auf Canvas, kein Cairo
# ============================================================
proc ivDraw {} {
    if {$::iv::file eq ""} {
        .c delete all
        set w [winfo width .c]
        set h [winfo height .c]
        .c create text [expr {$w/2}] [expr {$h/2}]             -text "Open an image file (PNG or JPEG)"             -fill "#888" -font "Sans 16" -anchor center
        return
    }

    set iw $::iv::imgW
    set ih $::iv::imgH
    set z  $::iv::zoom
    set cw [winfo width  .c]
    set ch [winfo height .c]
    if {$cw < 10} { set cw 880 }
    if {$ch < 10} { set ch 590 }

    set dw [expr {max(1, int($iw * $z))}]
    set dh [expr {max(1, int($ih * $z))}]
    set x  [expr {int(($cw - $dw) / 2.0 + $::iv::panX)}]
    set y  [expr {int(($ch - $dh) / 2.0 + $::iv::panY)}]

    # Scaled image — only re-create if zoom has changed
    if {$::iv::scaledPhoto eq "" || $::iv::scaledW != $dw || $::iv::scaledH != $dh} {
        if {$::iv::scaledPhoto ne ""} { image delete $::iv::scaledPhoto }
        set ::iv::scaledPhoto [image create photo]
        set scaledOk 0
        foreach m {lanczos3 lanczos2 catrom linear} {
            if {![catch {
                ::imgtools::scale $::iv::origPhoto ${dw}x${dh} \
                    -interpolation $m $::iv::scaledPhoto
            }]} { set scaledOk 1; break }
        }
        if {!$scaledOk} { .status configure -text "imgtools::scale failed (tried lanczos… linear)" }
        set ::iv::scaledW $dw
        set ::iv::scaledH $dh
    }

    # Canvas aktualisieren — reiner Tk-Blit
    .c delete all
    .c create image $x $y -anchor nw -image $::iv::scaledPhoto

    # Info-Overlay
    set n   [llength $::iv::filelist]
    set idx $::iv::fileindex
    set nav [expr {$n > 1 ? "  \[$[expr {$idx+1}]/$n\]" : ""}]
    set info [format "%s%s  |  %d × %d px  |  zoom %.0f%%"         [file tail $::iv::file] $nav $iw $ih [expr {$z * 100}]]
    .c create rectangle 6 [expr {$ch-30}] [expr {[string length $info]*7+22}]         [expr {$ch-8}] -fill "#000" -stipple gray50 -outline ""
    .c create text 14 [expr {$ch-14}] -text $info         -fill "#f0f0f0" -font "Sans 11" -anchor w
}

proc ivRedrawDelayed {} {
    after cancel $::iv::redrawJob
    set ::iv::redrawJob [after 50 ivDraw]
}

# ============================================================
# Laden
# ============================================================
proc ivOpen {} {
    set f [tk_getOpenFile         -filetypes {{"Image Files" {.png .jpg .jpeg .PNG .JPG .JPEG}} {"All Files" *}}         -title "Open Image"]
    if {$f eq ""} return
    ivLoad $f
}

proc ivLoad {file} {
    # Dimensionen via tclmcairo
    set tmp [tclmcairo::new 1 1]
    set iw 800; set ih 600
    catch { lassign [$tmp image_size $file] iw ih }
    $tmp destroy

    # Alte Images verwerfen (catch: Name kann noch existieren, Objekt schon weg
    # — z. B. nach fehlgeschlagenem vorherigen create)
    catch { if {$::iv::origPhoto ne ""} { image delete $::iv::origPhoto } }
    set ::iv::origPhoto ""
    catch { if {$::iv::scaledPhoto ne ""} { image delete $::iv::scaledPhoto } }
    set ::iv::scaledPhoto ""
    set ::iv::scaledW 0; set ::iv::scaledH 0

    if {[catch { set ph [image create photo -file $file] } errMain]} {
        if {[catch { lassign [ivMakePhotoFromTclmcairo $file] ph xw xh } errFb]} {
            .status configure -text "Load: $errMain  |  tclmcairo: $errFb"
            return
        }
        set ::iv::imgW $xw
        set ::iv::imgH $xh
    } else {
        set ::iv::imgW $iw
        set ::iv::imgH $ih
    }
    set ::iv::origPhoto $ph
    set ::iv::file $file
    set ::iv::panX 0.0
    set ::iv::panY 0.0

    # Filelist
    set dir [file dirname [file normalize $file]]
    set all [lsort -unique [concat         [glob -nocomplain -directory $dir "*.png"]         [glob -nocomplain -directory $dir "*.jpg"]         [glob -nocomplain -directory $dir "*.jpeg"]         [glob -nocomplain -directory $dir "*.PNG"]         [glob -nocomplain -directory $dir "*.JPG"]         [glob -nocomplain -directory $dir "*.JPEG"]]]
    set ::iv::filelist  $all
    set ::iv::fileindex [lsearch -exact $all [file normalize $file]]
    if {$::iv::fileindex < 0} { set ::iv::fileindex 0 }

    ivFit
    .status configure -text         "[file tail $file]  ($::iv::imgW × $::iv::imgH px)  \[$[expr {$::iv::fileindex+1}]/[llength $all]\]"
}

proc ivFit {} {
    if {$::iv::file eq ""} return
    set cw [winfo width  .c]; if {$cw < 10} { set cw 880 }
    set ch [winfo height .c]; if {$ch < 10} { set ch 590 }
    set zw [expr {($cw - 10) / double($::iv::imgW)}]
    set zh [expr {($ch - 10) / double($::iv::imgH)}]
    set ::iv::zoom  [expr {min($zw, $zh, 1.0)}]
    set ::iv::panX  0.0
    set ::iv::panY  0.0
    ivDraw
}

proc ivZoom1 {} {
    set ::iv::zoom 1.0
    set ::iv::panX 0.0
    set ::iv::panY 0.0
    ivDraw
}

proc ivZoom {factor} {
    set ::iv::zoom [expr {max(0.05, min(20.0, $::iv::zoom * $factor))}]
    ivRedrawDelayed
}

proc ivWheelZoom {delta x y} {
    set ::iv::zoom [expr {max(0.05, min(20.0, $::iv::zoom *         [expr {$delta > 0 ? 1.15 : 0.87}]))}]
    ivRedrawDelayed
}

proc ivDragStart {x y} {
    set ::iv::dragging 1
    set ::iv::dragX    $x
    set ::iv::dragY    $y
}

proc ivDragMotion {x y} {
    if {!$::iv::dragging} return
    set ::iv::panX [expr {$::iv::panX + ($x - $::iv::dragX)}]
    set ::iv::panY [expr {$::iv::panY + ($y - $::iv::dragY)}]
    set ::iv::dragX $x
    set ::iv::dragY $y
    # Pan: sofort zeichnen (kein Delay)
    .c move all [expr {$x - $::iv::dragX + ($x - $::iv::dragX)}] 0
    ivDraw
}

proc ivPrev {} {
    set n [llength $::iv::filelist]
    if {$n < 2} return
    ivLoad [lindex $::iv::filelist         [expr {($::iv::fileindex - 1 + $n) % $n}]]
}

proc ivNext {} {
    set n [llength $::iv::filelist]
    if {$n < 2} return
    ivLoad [lindex $::iv::filelist         [expr {($::iv::fileindex + 1) % $n}]]
}

proc ivExport {fmt} {
    if {$::iv::file eq ""} return
    set base [file rootname [file tail $::iv::file]]
    set f [tk_getSaveFile         -initialfile "${base}_export.$fmt"         -defaultextension .$fmt         -title "Export as [string toupper $fmt]"]
    if {$f eq ""} return
    # Cairo for export
    set ctx [tclmcairo::new $::iv::imgW $::iv::imgH]
    $ctx image $::iv::file 0 0
    $ctx save $f
    $ctx destroy
    .status configure -text "Exported: $f"
}

# Drag & Drop
catch {
    package require tkdnd
    tkdnd::drop_target register .c *
    bind .c <<Drop:DND_Files>> { ivLoad [lindex %D 0] }
}

after idle ivDraw
