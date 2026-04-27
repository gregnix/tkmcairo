# tkmcairo::pageview 0.1
#
# PDF-Seitenvorschau Widget — zeigt PDF-Seiten via pdfiumtcl.
# Unterstützt Navigation, Zoom, Lesezeichen-Panel, Textsuche, Export.
#
# API:
#   tkmcairo::pageview pathName ?options?
#
#   Options:
#     -width  n          Breite in Pixeln (default 700)
#     -height n          Höhe in Pixeln (default 900)
#     -file   filename   PDF-Datei (optional)
#     -dpi    n          Render-Auflösung (default 150)
#     -background {r g b}
#
#   Widget-Commands:
#     $pv load filename ?password?
#     $pv page  n         Zu Seite n gehen (0-basiert)
#     $pv next            Nächste Seite
#     $pv prev            Vorherige Seite
#     $pv first           Erste Seite
#     $pv last            Letzte Seite
#     $pv zoom  factor    Zoom multiplizieren
#     $pv zoomfit         An Breite anpassen
#     $pv zoom1           100%
#     $pv dpi   n         DPI setzen
#     $pv pagecount       Anzahl Seiten
#     $pv currentpage     Aktuelle Seite (0-basiert)
#     $pv file            Aktueller Dateiname
#     $pv search text     Text suchen → Seiten mit Treffern
#     $pv export filename            PNG export of current page
#     $pv export -chan $ch ?-format png?  stream PNG bytes to a Tcl channel
#     $pv redraw
#     $pv destroy
#
# Requirements: pdfiumtcl, Tk
#
# Part of tkmcairo — https://github.com/gregnix/tkmcairo
# License: BSD 2-Clause

package provide tkmcairo::pageview 0.1.1

package require Tk

namespace eval ::tkmcairo::pageview {}


# ============================================================
# Backend-Erkennung
# ============================================================
proc ::tkmcairo::pageview::_detectBackend {pref} {
    if {$pref eq "pdfium"} {
        if {![catch {package require pdfiumtcl}]} { return pdfium }
        return ""
    }
    if {$pref eq "poppler"} {
        if {[auto_execok pdftoppm] ne ""} { return poppler }
        return ""
    }
    if {$pref eq "mupdf"} {
        if {[auto_execok mutool] ne ""} { return mupdf }
        return ""
    }
    # auto: pdfium zuerst, dann poppler, dann mupdf
    if {![catch {package require pdfiumtcl}]} { return pdfium }
    if {[auto_execok pdftoppm] ne ""}         { return poppler }
    if {[auto_execok mutool] ne ""}           { return mupdf }
    return ""
}

# ============================================================
# Konstruktor
# ============================================================
proc ::tkmcairo::pageview {w args} {
    array set opts {
        -width      700
        -height     900
        -file       ""
        -dpi        150
        -background {0.85 0.85 0.85}
        -bookmarks  1
        -backend    auto
    }
    foreach {k v} $args { set opts($k) $v }

    # Hauptframe
    ttk::frame $w
    set fc ::tkmcairo::pageview::_frame_[string map {. _ : _} $w]
    set ::tkmcairo::pageview::_frameCmd($w) $fc
    rename $w $fc
    interp alias {} $w {} ::tkmcairo::pageview::_cmd $w
    bind $w <Destroy> [list ::tkmcairo::pageview::_cleanup $w]

    # State
    namespace eval ::tkmcairo::pageview::S_$w {
        variable file       ""
        variable doc        ""
        variable pagecount  0
        variable backend    ""
        variable tmpdir     ""
        variable curpage    0
        variable dpi        150
        variable zoom       1.0
        variable imgname    ""
        variable panX       0.0
        variable panY       0.0
        variable dragging   0
        variable dragX      0
        variable dragY      0
    }
    set ns ::tkmcairo::pageview::S_${w}
    set ${ns}::dpi  $opts(-dpi)
    # Optionen für _load / _render (u. a. -backend) im Widget-Namespace halten
    foreach {k v} [array get opts] {
        set ${ns}::opts($k) $v
    }

    # Layout: Toolbar + optional Bookmark-Panel + Canvas
    ::tkmcairo::pageview::_buildUI $w $opts(-width) $opts(-height) $opts(-bookmarks)

    if {$opts(-file) ne ""} {
        after idle [list ::tkmcairo::pageview::_load $w $opts(-file)]
    }

    return $w
}

# ============================================================
# UI aufbauen
# ============================================================
proc ::tkmcairo::pageview::_buildUI {w width height showbm} {
    set fc $::tkmcairo::pageview::_frameCmd($w)

    # Toolbar
    ttk::frame $w.tb
    pack $w.tb -fill x -side top

    ttk::button  $w.tb.first -text "⏮"  -width 3 -command [list $w first]
    ttk::button  $w.tb.prev  -text "◀"  -width 3 -command [list $w prev]
    ttk::entry   $w.tb.pnum  -width 5   -justify center
    ttk::label   $w.tb.pof   -text "/ ?"
    ttk::button  $w.tb.next  -text "▶"  -width 3 -command [list $w next]
    ttk::button  $w.tb.last  -text "⏭"  -width 3 -command [list $w last]
    ttk::separator $w.tb.s1  -orient vertical
    ttk::button  $w.tb.zin   -text "+"  -width 3 -command [list $w zoom 1.25]
    ttk::button  $w.tb.zout  -text "−"  -width 3 -command [list $w zoom 0.8]
    ttk::button  $w.tb.zfit  -text "Fit" -command [list $w zoomfit]
    ttk::button  $w.tb.z1    -text "100%" -command [list $w zoom1]
    ttk::separator $w.tb.s2  -orient vertical
    ttk::entry   $w.tb.srch  -width 15
    ttk::button  $w.tb.sgo   -text "🔍" -command [list ::tkmcairo::pageview::_doSearch $w]
    ttk::separator $w.tb.s3  -orient vertical
    ttk::button  $w.tb.epng  -text "PNG" -command [list ::tkmcairo::pageview::_exportPng $w]

    foreach b {first prev pnum pof next last s1 zin zout zfit z1 s2 srch sgo s3 epng} {
        pack $w.tb.$b -side left -padx 1 -pady 2
    }

    # Enter in Seitennummer-Feld
    bind $w.tb.pnum <Return> [list ::tkmcairo::pageview::_gotoEntry $w]

    # Hauptbereich: optional Bookmarks links + Canvas rechts
    ttk::frame $w.main
    pack $w.main -fill both -expand 1

    if {$showbm} {
        # Bookmark-Panel
        ttk::frame $w.main.bm
        pack $w.main.bm -side left -fill y
        ttk::label $w.main.bm.lbl -text "Bookmarks" -anchor w
        pack $w.main.bm.lbl -fill x -padx 4 -pady 2
        ttk::treeview $w.main.bm.tree \
            -columns {page} -show tree \
            -selectmode browse -height 20
        $w.main.bm.tree column #0    -width 160
        ttk::scrollbar $w.main.bm.ys -orient vertical \
            -command [list $w.main.bm.tree yview]
        $w.main.bm.tree configure -yscrollcommand [list $w.main.bm.ys set]
        pack $w.main.bm.ys   -side right -fill y
        pack $w.main.bm.tree -fill both -expand 1

        bind $w.main.bm.tree <<TreeviewSelect>> \
            [list ::tkmcairo::pageview::_bmSelect $w]
    }

    # Canvas für PDF-Seite
    canvas $w.main.cv \
        -width  [expr {$showbm ? $width - 180 : $width}] \
        -height $height \
        -bg     "#D8D8D8" \
        -highlightthickness 0
    pack $w.main.cv -fill both -expand 1

    # Scrollbalken
    ttk::scrollbar $w.main.ys -orient vertical \
        -command [list $w.main.cv yview]
    ttk::scrollbar $w.main.xs -orient horizontal \
        -command [list $w.main.cv xview]
    pack $w.main.ys -side right -fill y
    pack $w.main.xs -side bottom -fill x
    $w.main.cv configure \
        -yscrollcommand [list $w.main.ys set] \
        -xscrollcommand [list $w.main.xs set]

    # Mouse-Bindings
    bind $w.main.cv <ButtonPress-1>   [list ::tkmcairo::pageview::_dragStart $w %x %y]
    bind $w.main.cv <B1-Motion>       [list ::tkmcairo::pageview::_dragMotion $w %x %y]
    bind $w.main.cv <ButtonRelease-1> [list set ::tkmcairo::pageview::S_${w}::dragging 0]
    bind $w.main.cv <MouseWheel>      [list ::tkmcairo::pageview::_wheel $w %D]
    bind $w.main.cv <Button-4>        [list ::tkmcairo::pageview::_wheel $w  120]
    bind $w.main.cv <Button-5>        [list ::tkmcairo::pageview::_wheel $w -120]
    bind $w.main.cv <Control-MouseWheel> [list ::tkmcairo::pageview::_wheelZoom $w %D]
    bind $w.main.cv <Control-Button-4>   [list ::tkmcairo::pageview::_wheelZoom $w  120]
    bind $w.main.cv <Control-Button-5>   [list ::tkmcairo::pageview::_wheelZoom $w -120]

    # Status
    ttk::label $w.status -text "" -anchor w
    pack $w.status -fill x -side bottom -padx 4
}

# ============================================================
# Widget-Command Dispatcher
# ============================================================
proc ::tkmcairo::pageview::_cmd {w subcmd args} {
    set ns ::tkmcairo::pageview::S_${w}
    switch -- $subcmd {
        load      { ::tkmcairo::pageview::_load $w {*}$args }
        page      { ::tkmcairo::pageview::_goto $w [lindex $args 0] }
        next      { ::tkmcairo::pageview::_goto $w [expr {[set ${ns}::curpage] + 1}] }
        prev      { ::tkmcairo::pageview::_goto $w [expr {[set ${ns}::curpage] - 1}] }
        first     { ::tkmcairo::pageview::_goto $w 0 }
        last      { ::tkmcairo::pageview::_goto $w [expr {[set ${ns}::pagecount] - 1}] }
        zoom      { ::tkmcairo::pageview::_zoom $w [lindex $args 0] }
        zoomfit   { ::tkmcairo::pageview::_zoomfit $w }
        zoom1     { set ${ns}::zoom 1.0; ::tkmcairo::pageview::_render $w }
        dpi       { set ${ns}::dpi [lindex $args 0]; ::tkmcairo::pageview::_render $w }
        pagecount { return [set ${ns}::pagecount] }
        currentpage { return [set ${ns}::curpage] }
        file      { return [set ${ns}::file] }
        search    { return [::tkmcairo::pageview::_search $w [lindex $args 0]] }
        export    { _exportPng $w {*}$args }
        redraw    { ::tkmcairo::pageview::_render $w }
        destroy   { destroy $w }
        default   {
            set fc $::tkmcairo::pageview::_frameCmd($w)
            $fc $subcmd {*}$args
        }
    }
}

# ============================================================
# Laden
# ============================================================
proc ::tkmcairo::pageview::_load {w file {password ""}} {
    set ns ::tkmcairo::pageview::S_${w}

    if {![file exists $file]} {
        tk_messageBox -message "File not found: $file" -type ok -icon error
        return
    }

    # Backend ermitteln
    set backend [::tkmcairo::pageview::_detectBackend [set ${ns}::opts(-backend)]]
    if {$backend eq ""} {
        $w.status configure -text "Error: kein PDF-Backend gefunden (pdfiumtcl/poppler/mupdf)"
        return
    }
    set ${ns}::backend $backend

    # Altes Dokument schließen
    if {[set ${ns}::doc] ne ""} {
        catch {pdfium::close [set ${ns}::doc]}
        set ${ns}::doc ""
    }
    # Altes tmpdir aufräumen
    set tmpdir [set ${ns}::tmpdir]
    if {$tmpdir ne "" && [file exists $tmpdir]} {
        catch {file delete -force $tmpdir}
    }

    set ${ns}::file    $file
    set ${ns}::curpage 0
    set ${ns}::zoom    1.0

    if {$backend eq "pdfium"} {
        if {[catch {
            set doc [pdfium::open $file {*}[expr {$password ne "" ? [list $password] : {}}]]
        } err]} {
            $w.status configure -text "Error: $err"
            return
        }
        set ${ns}::doc       $doc
        set ${ns}::pagecount [pdfium::pagecount $doc]
        set ${ns}::tmpdir    ""
        ::tkmcairo::pageview::_loadBookmarks $w $doc
    } else {
        # poppler / mupdf: Seitenanzahl via pdfinfo oder pdftoppm -l 1
        set ${ns}::doc ""
        set n [::tkmcairo::pageview::_countPages $w $file $backend]
        set ${ns}::pagecount $n
        # tmpdir for cached PNGs — system temp, not info-script based.
        # Old approach (info script -> .pvcache_PID) put it next to the
        # package install, which fails on read-only installs and causes
        # cleanup permission issues.
        set tmpbase ""
        if {[info exists ::env(TMPDIR)] && [file isdirectory $::env(TMPDIR)]} {
            set tmpbase $::env(TMPDIR)
        } elseif {[file isdirectory /tmp]} {
            set tmpbase /tmp
        } elseif {[info exists ::env(TEMP)] && [file isdirectory $::env(TEMP)]} {
            set tmpbase $::env(TEMP)
        } else {
            set tmpbase [pwd]
        }
        # Unique per widget instance (PID + microseconds)
        set td [file join $tmpbase \
            "tkmcairo_pageview_[pid]_[clock microseconds]"]
        file mkdir $td
        set ${ns}::tmpdir $td
    }

    ::tkmcairo::pageview::_zoomfit $w
    ::tkmcairo::pageview::_updateStatus $w
}

proc ::tkmcairo::pageview::_countPages {w file backend} {
    # pdfinfo für Seitenanzahl
    if {[auto_execok pdfinfo] ne ""} {
        catch {
            set out [exec pdfinfo $file]
            if {[regexp {Pages:\s+(\d+)} $out -> n]} { return $n }
        }
    }
    # Fallback: pdftoppm erste Seite rendern und zählen
    return 1
}

# ============================================================
# Bookmarks
# ============================================================
proc ::tkmcairo::pageview::_loadBookmarks {w doc} {
    if {![winfo exists $w.main.bm.tree]} return
    $w.main.bm.tree delete [$w.main.bm.tree children {}]

    catch {
        foreach bm [pdfium::bookmarks $doc] {
            lassign $bm title pagenum level
            set parent [expr {$level == 0 ? {} : "L[expr {$level-1}]_$pagenum"}]
            catch {
                $w.main.bm.tree insert {} end \
                    -id "L${level}_${pagenum}_[string map {{ } _} $title]" \
                    -text $title \
                    -values [list $pagenum]
            }
        }
    }
}

proc ::tkmcairo::pageview::_bmSelect {w} {
    set ns ::tkmcairo::pageview::S_${w}
    set sel [$w.main.bm.tree selection]
    if {$sel eq ""} return
    set page [$w.main.bm.tree set $sel page]
    if {[string is integer $page]} {
        ::tkmcairo::pageview::_goto $w $page
    }
}

# ============================================================
# Navigation
# ============================================================
proc ::tkmcairo::pageview::_goto {w n} {
    set ns ::tkmcairo::pageview::S_${w}
    set n [expr {max(0, min($n, [set ${ns}::pagecount] - 1))}]
    set ${ns}::curpage $n
    set ${ns}::panX    0.0
    set ${ns}::panY    0.0
    ::tkmcairo::pageview::_render $w
    ::tkmcairo::pageview::_updateStatus $w
}

proc ::tkmcairo::pageview::_gotoEntry {w} {
    set val [$w.tb.pnum get]
    if {[string is integer -strict $val]} {
        ::tkmcairo::pageview::_goto $w [expr {$val - 1}]
    }
}

# ============================================================
# Zoom
# ============================================================
proc ::tkmcairo::pageview::_zoom {w factor} {
    set ns ::tkmcairo::pageview::S_${w}
    set ${ns}::zoom [expr {max(0.1, min(5.0, [set ${ns}::zoom] * $factor))}]
    ::tkmcairo::pageview::_render $w
}

proc ::tkmcairo::pageview::_zoomfit {w} {
    set ns ::tkmcairo::pageview::S_${w}
    set cw [winfo width $w.main.cv]
    if {$cw < 50} { set cw 500 }
    set dpi  [set ${ns}::dpi]
    set zoom 1.0
    if {[set ${ns}::backend] eq "pdfium" && [set ${ns}::doc] ne ""} {
        set doc  [set ${ns}::doc]
        set page [set ${ns}::curpage]
        catch {
            lassign [pdfium::pagesize $doc $page] pw ph
            set pw_px [expr {$pw / 25.4 * $dpi}]
            if {$pw_px > 0} { set zoom [expr {($cw - 20) / $pw_px}] }
        }
    }
    set ${ns}::zoom $zoom
    ::tkmcairo::pageview::_render $w
}

# ============================================================
# Rendern
# ============================================================
proc ::tkmcairo::pageview::_render {w} {
    set ns ::tkmcairo::pageview::S_${w}
    set backend [set ${ns}::backend]
    if {$backend eq ""} return

    set page   [set ${ns}::curpage]
    set dpi    [set ${ns}::dpi]
    set zoom   [set ${ns}::zoom]
    set rdpi   [expr {int($dpi * $zoom)}]
    if {$rdpi < 10} { set rdpi 10 }

    set imgname "::tkmcairo::pageview::_img_[string map {. _ : _} $w]"
    set ${ns}::imgname $imgname

    if {$backend eq "pdfium"} {
        set doc [set ${ns}::doc]
        if {[catch {
            pdfium::render $doc $page -dpi $rdpi -imagename $imgname
        } err]} {
            $w.status configure -text "Render error: $err"
            return
        }
    } else {
        # poppler / mupdf: exec → PNG → Tk photo
        set file [set ${ns}::file]
        set tmpf [file join [set ${ns}::tmpdir] "page[format %04d $page].png"]

        if {![file exists $tmpf] || [file mtime $tmpf] < [file mtime $file]} {
            # Seite rendern
            if {$backend eq "poppler"} {
                set base [file join [set ${ns}::tmpdir] "page[format %04d $page]"]
                if {[catch {
                    exec pdftoppm -r $rdpi -png -f [expr {$page+1}] -l [expr {$page+1}]                         $file $base
                } err]} {
                    $w.status configure -text "pdftoppm error: $err"
                    return
                }
                # pdftoppm erzeugt page0001-1.png oder page0001.png
                foreach f [glob -nocomplain "${base}*.png"] {
                    file rename -force $f $tmpf
                    break
                }
            } elseif {$backend eq "mupdf"} {
                if {[catch {
                    exec mutool draw -o $tmpf -r $rdpi $file [expr {$page+1}]
                } err]} {
                    $w.status configure -text "mutool error: $err"
                    return
                }
            }
        }

        if {![file exists $tmpf]} {
            $w.status configure -text "Render failed: $tmpf"
            return
        }
        if {![image exists $imgname]} {
            image create photo $imgname
        }
        $imgname read $tmpf -format png
    }

    set iw [image width  $imgname]
    set ih [image height $imgname]

    $w.main.cv delete all
    $w.main.cv configure -scrollregion [list 0 0 $iw $ih]
    $w.main.cv create image 0 0 -anchor nw -image $imgname

    $w.tb.pnum delete 0 end
    $w.tb.pnum insert 0 [expr {$page + 1}]
    $w.tb.pof  configure -text "/ [set ${ns}::pagecount]"
}

# ============================================================
# Suche
# ============================================================
proc ::tkmcairo::pageview::_doSearch {w} {
    set ns ::tkmcairo::pageview::S_${w}
    set txt [$w.tb.srch get]
    if {$txt eq "" || [set ${ns}::doc] eq ""} return
    set hits [::tkmcairo::pageview::_search $w $txt]
    if {[llength $hits] == 0} {
        $w.status configure -text "Not found: $txt"
        return
    }
    # Zur ersten Seite mit Treffer springen
    ::tkmcairo::pageview::_goto $w [lindex $hits 0]
    $w.status configure -text "Found on pages: [join [lmap p $hits {expr {$p+1}}] {, }]"
}

proc ::tkmcairo::pageview::_search {w txt} {
    set ns ::tkmcairo::pageview::S_${w}
    if {[set ${ns}::doc] eq ""} return {}
    set doc [set ${ns}::doc]
    set n   [set ${ns}::pagecount]
    set hits {}
    for {set p 0} {$p < $n} {incr p} {
        set r [pdfium::search $doc $p $txt]
        if {[llength $r] > 0} { lappend hits $p }
    }
    return $hits
}

# ============================================================
# Export
# ============================================================
proc ::tkmcairo::pageview::_exportPng {w args} {
    set ns ::tkmcairo::pageview::S_${w}
    if {[set ${ns}::doc] eq ""} return

    # Parse args: file (positional) OR -chan ?-format?
    set file ""
    set chan ""
    set fmt  png
    if {[llength $args] == 1} {
        set file [lindex $args 0]
    } else {
        foreach {k v} $args {
            switch -- $k {
                -chan   { set chan $v }
                -format { set fmt $v }
                -file   { set file $v }
                default {
                    error "tkmcairo::pageview export: unknown option $k"
                }
            }
        }
    }

    if {$file eq "" && $chan eq ""} {
        set base [file rootname [file tail [set ${ns}::file]]]
        set p    [expr {[set ${ns}::curpage] + 1}]
        set file [tk_getSaveFile \
            -initialfile "${base}_page${p}.png" \
            -defaultextension .png \
            -filetypes {{"PNG Files" .png} {"All Files" *}} \
            -title "Export Page as PNG"]
        if {$file eq ""} return
    }

    set imgname [set ${ns}::imgname]
    if {$imgname eq "" || ![image exists $imgname]} return

    if {$chan ne ""} {
        # Tk photo write does not accept -chan, so go through 'data'
        # which gives us base64 — decode and stream out.
        # 'data -format png' returns base64 by default; we need raw bytes.
        if {[catch {$imgname data -format png} b64]} {
            error "pageview export -chan: photo data export failed: $b64"
        }
        # Tk's photo data returns base64-encoded PNG by default
        set bytes [binary decode base64 $b64]
        fconfigure $chan -translation binary
        puts -nonewline $chan $bytes
        return
    }

    $imgname write $file -format png
    $w.status configure -text "Exported: $file"
}

# ============================================================
# Mouse
# ============================================================
proc ::tkmcairo::pageview::_wheel {w delta} {
    set step [expr {$delta > 0 ? -3 : 3}]
    catch { $w.main.cv yview scroll $step units }
}

proc ::tkmcairo::pageview::_wheelZoom {w delta} {
    ::tkmcairo::pageview::_zoom $w [expr {$delta > 0 ? 1.15 : 0.87}]
}

proc ::tkmcairo::pageview::_dragStart {w x y} {
    set ns ::tkmcairo::pageview::S_${w}
    set ${ns}::dragging 1
    set ${ns}::dragX    $x
    set ${ns}::dragY    $y
}

proc ::tkmcairo::pageview::_dragMotion {w x y} {
    set ns ::tkmcairo::pageview::S_${w}
    if {![set ${ns}::dragging]} return
    set dx [expr {[set ${ns}::dragX] - $x}]
    set dy [expr {[set ${ns}::dragY] - $y}]
    catch { $w.main.cv xview scroll $dx pixels }
    catch { $w.main.cv yview scroll $dy pixels }
    set ${ns}::dragX $x
    set ${ns}::dragY $y
}

# ============================================================
# Status
# ============================================================
proc ::tkmcairo::pageview::_updateStatus {w} {
    set ns ::tkmcairo::pageview::S_${w}
    set p       [expr {[set ${ns}::curpage] + 1}]
    set n       [set ${ns}::pagecount]
    set f       [file tail [set ${ns}::file]]
    set dpi     [set ${ns}::dpi]
    set zoom    [expr {int([set ${ns}::zoom] * 100)}]
    set backend [set ${ns}::backend]
    set size ""
    if {$backend eq "pdfium"} {
        catch {
            lassign [pdfium::pagesize [set ${ns}::doc] [set ${ns}::curpage]] pw ph
            set size [format "  %.0f×%.0f mm" $pw $ph]
        }
    }
    $w.status configure -text         "$f  |  Page $p / $n$size  |  ${dpi}dpi  ${zoom}%  \[$backend\]"
}

# ============================================================
# Cleanup
# ============================================================
proc ::tkmcairo::pageview::_cleanup {w} {
    set ns ::tkmcairo::pageview::S_${w}
    if {![namespace exists $ns]} return
    if {[set ${ns}::doc] ne ""} {
        catch {pdfium::close [set ${ns}::doc]}
    }
    set tmpdir [set ${ns}::tmpdir]
    if {$tmpdir ne "" && [file exists $tmpdir]} {
        catch {file delete -force $tmpdir}
    }
    set imgname [set ${ns}::imgname]
    if {$imgname ne "" && [image exists $imgname]} {
        image delete $imgname
    }
    namespace delete $ns
}
