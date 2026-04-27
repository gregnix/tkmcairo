# tkmcairo::surface 0.1
#
# Cairo drawing widget backed by ttk::frame + tclmcairo + Tk photo image.
#
# Usage:
#   tkmcairo::surface pathName ?-width W -height H -drawcommand SCRIPT ...?
#   SCRIPT receives: ctx w h
#
#   $w redraw             force redraw
#   $w export filename                save PNG/PDF/SVG/PS/EPS to file
#   $w export -chan $ch -format fmt   stream output to a Tcl channel
#                                       (fmt: png|pdf|svg|ps|eps)
#   $w ctx                current tclmcairo context
#   $w width / $w height  current size
#   $w configure ...      update options
#   $w cget option        query option
#
# Part of tkmcairo -- https://github.com/gregnix/tkmcairo
# License: BSD 2-Clause

package provide tkmcairo::surface 0.1.1

package require Tk
package require tclmcairo

namespace eval ::tkmcairo::surface {
    variable _frameCmd  ;# array: w -> internal frame command
}

proc tkmcairo::surface {w args} {
    array set opts {
        -width       400
        -height      300
        -drawcommand ""
        -background  {1 1 1}
        -autoresize  1
    }
    foreach {k v} $args { set opts($k) $v }

    # Create frame
    ttk::frame $w

    # Rename the frame's Tcl command so we can install our own command
    # under the same name without Tk destroying the window
    set fc ::tkmcairo::surface::_frame_[string map {. _ : _} $w]
    set ::tkmcairo::surface::_frameCmd($w) $fc
    rename $w $fc

    # Install our command (alias, no existing .X command to delete now)
    interp alias {} $w {} ::tkmcairo::surface::_cmd $w

    # Label for the Cairo image
    set img [image create photo ::tkmcairo::surface::_img_[string map {. _ : _} $w]]
    ttk::label $w.lbl -image $img -anchor nw -padding 0
    pack $w.lbl

    # State namespace
    namespace eval ::tkmcairo::surface::S_$w {
        variable ctx     ""
        variable photo   ""
        variable width   0
        variable height  0
        variable pending 0
        variable opts
    }
    set ns ::tkmcairo::surface::S_${w}
    set ${ns}::photo  $img
    set ${ns}::width  $opts(-width)
    set ${ns}::height $opts(-height)
    array set ${ns}::opts [array get opts]

    if {$opts(-autoresize)} {
        bind $w <Configure> \
            [list ::tkmcairo::surface::_onConfigure $w %w %h]
    }
    bind $w <Destroy> [list ::tkmcairo::surface::_cleanup $w]

    after idle [list catch [list ::tkmcairo::surface::_redraw $w]]
    return $w
}

# ============================================================
proc tkmcairo::surface::_cmd {w subcmd args} {
    switch -- $subcmd {
        redraw    { _redraw $w }
        ctx       { set ::tkmcairo::surface::S_${w}::ctx }
        width     { set ::tkmcairo::surface::S_${w}::width }
        height    { set ::tkmcairo::surface::S_${w}::height }
        export    { _export $w {*}$args }
        configure { _configure $w {*}$args }
        cget      {
            lindex $args 0
            set ::tkmcairo::surface::S_${w}::opts([lindex $args 0])
        }
        id        { set ::tkmcairo::surface::S_${w}::ctx }
        default   {
            # Forward to underlying frame command
            set fc $::tkmcairo::surface::_frameCmd($w)
            $fc $subcmd {*}$args
        }
    }
}

# ============================================================
proc tkmcairo::surface::_redraw {w} {
    if {![winfo exists $w]} return
    set ns ::tkmcairo::surface::S_${w}

    set pw [set ${ns}::width]
    set ph [set ${ns}::height]
    if {$pw < 1 || $ph < 1} return

    if {[set ${ns}::ctx] ne ""} {
        catch {[set ${ns}::ctx] destroy}
        set ${ns}::ctx ""
    }

    set ctx ""
    if {[catch {tclmcairo::new $pw $ph} ctx]} { return }
    set ${ns}::ctx $ctx

    lassign [set ${ns}::opts(-background)] r g b
    $ctx clear $r $g $b 1

    set cmd [set ${ns}::opts(-drawcommand)]
    if {$cmd ne ""} {
        uplevel #0 [list set ctx $ctx]
        uplevel #0 [list set w   $pw]
        uplevel #0 [list set h   $ph]
        if {[catch {uplevel #0 $cmd} _err _opts]} {
            puts stderr "tkmcairo::surface drawcommand error: $_err\n[dict get $_opts -errorinfo]"
        }
    }

    # toppm (P6 RGB24) ist ~10x schneller als topng (kein PNG-Encoding)
    if {[catch {$ctx toppm} ppmdata]} {
        # Fallback auf topng
        if {[catch {$ctx topng} pngdata]} {
            catch {$ctx destroy}
            set ${ns}::ctx ""
            return
        }
        catch { [set ${ns}::photo] put $pngdata -format png }
    } else {
        catch { [set ${ns}::photo] put $ppmdata -format ppm }
    }
    # Feste Groesse via place (verhindert Wachsen des Fensters)
    catch { place $w.lbl -x 0 -y 0 -width $pw -height $ph }
    # Frame auf feste Groesse setzen damit pack-Manager nicht expandiert
    set fc [set ::tkmcairo::surface::_frameCmd($w)]
    catch { $fc configure -width $pw -height $ph }
    set ${ns}::pending 0
}

# ============================================================
proc tkmcairo::surface::_onConfigure {w nw nh} {
    if {![winfo exists $w]} return
    set ns ::tkmcairo::surface::S_${w}
    if {$nw < 1 || $nh < 1} return
    if {[set ${ns}::width] == $nw && [set ${ns}::height] == $nh} return
    set ${ns}::width  $nw
    set ${ns}::height $nh
    if {[set ${ns}::pending]} return
    set ${ns}::pending 1
    after 30 [list catch [list ::tkmcairo::surface::_redraw $w]]
}

# ============================================================
proc tkmcairo::surface::_configure {w args} {
    set ns ::tkmcairo::surface::S_${w}
    foreach {k v} $args {
        set ${ns}::opts($k) $v
        switch -- $k {
            -width  { set ${ns}::width  $v }
            -height { set ${ns}::height $v }
        }
    }
    after idle [list catch [list ::tkmcairo::surface::_redraw $w]]
}

# ============================================================
# _export — write the surface to a file or a channel.
#
#   $w export filename                ;# format from extension
#   $w export -chan $ch -format png   ;# stream to open channel
#   $w export -chan $ch -format pdf
#
# The channel form does not allocate the full output as a Tcl string —
# it streams via tclmcairo save -chan when available, or via tempfile
# fallback for vector formats that need seekable output.
proc tkmcairo::surface::_export {w args} {
    if {![winfo exists $w]} return
    set ns ::tkmcairo::surface::S_${w}
    set pw [set ${ns}::width]
    set ph [set ${ns}::height]

    # Parse args: either a single filename, or -chan $ch -format $fmt
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
                default { error "tkmcairo::surface export: unknown option $k" }
            }
        }
    }

    if {$file ne ""} {
        set ext [string tolower [file extension $file]]
        set mode [switch $ext {
            .pdf {expr {"pdf"}} .svg {expr {"svg"}}
            .ps  {expr {"ps"}}  .eps {expr {"eps"}}
            default {expr {"png"}}
        }]
    } elseif {$chan ne ""} {
        if {$fmt eq ""} { set fmt png }
        set mode $fmt
    } else {
        error "tkmcairo::surface export: need filename or -chan"
    }

    if {$mode eq "png"} {
        # Render fresh, then save to file or stream to channel.
        # tclmcairo save accepts both -chan and a path target (since 0.3.2),
        # so we don't need a topng -> bytes -> manual write round trip.
        set pctx ""
        if {[catch {tclmcairo::new $pw $ph} pctx]} return
        lassign [set ${ns}::opts(-background)] r g b
        $pctx clear $r $g $b 1
        set cmd [set ${ns}::opts(-drawcommand)]
        if {$cmd ne ""} {
            uplevel #0 [list set ctx $pctx]
            uplevel #0 [list set w   $pw]
            uplevel #0 [list set h   $ph]
            if {[catch {uplevel #0 $cmd} _err _opts]} {
                puts stderr "tkmcairo::surface drawcommand error: $_err\n[dict get $_opts -errorinfo]"
            }
        }
        if {$chan ne ""} {
            if {[catch {$pctx save -chan $chan -format png} _err]} {
                # Fallback for older tclmcairo without save -chan
                if {![catch {$pctx topng} pngdata]} {
                    fconfigure $chan -translation binary
                    puts -nonewline $chan $pngdata
                }
            }
        } else {
            if {[catch {$pctx save $file} _err]} {
                # Fallback for older tclmcairo (< 0.3.2)
                if {![catch {$pctx topng} pngdata]} {
                    set fh [open $file wb]
                    fconfigure $fh -translation binary
                    puts -nonewline $fh $pngdata
                    close $fh
                }
            }
        }
        catch {$pctx destroy}
        return
    }

    # Vector formats (pdf/svg/ps/eps): tclmcairo::new for vector mode
    # needs -file. For -chan, render to a tempfile and stream out.
    if {$chan ne ""} {
        set tmpf [file join \
            [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] \
            "tkmcairo_surface_export_[pid]_[clock microseconds].$mode"]
        set ctx ""
        if {[catch {tclmcairo::new $pw $ph -mode $mode -file $tmpf} ctx]} {
            error "Export failed: $ctx"
        }
        lassign [set ${ns}::opts(-background)] r g b
        $ctx clear $r $g $b 1
        set cmd [set ${ns}::opts(-drawcommand)]
        if {$cmd ne ""} {
            uplevel #0 [list set ctx $ctx]
            uplevel #0 [list set w   $pw]
            uplevel #0 [list set h   $ph]
            if {[catch {uplevel #0 $cmd} _err _opts]} {
                puts stderr "tkmcairo::surface drawcommand error: $_err\n[dict get $_opts -errorinfo]"
            }
        }
        catch {$ctx finish}
        catch {$ctx destroy}
        # Stream tempfile -> channel, then delete tempfile
        if {[file exists $tmpf]} {
            set fh [open $tmpf rb]
            fconfigure $fh   -translation binary
            fconfigure $chan -translation binary
            fcopy $fh $chan
            close $fh
            file delete -force $tmpf
        }
        return
    }

    # Vector formats, file output (the historical path)

    set ctx ""
    if {[catch {tclmcairo::new $pw $ph -mode $mode -file $file} ctx]} {
        error "Export failed: $ctx"
    }
    lassign [set ${ns}::opts(-background)] r g b
    $ctx clear $r $g $b 1
    set cmd [set ${ns}::opts(-drawcommand)]
    if {$cmd ne ""} {
        uplevel #0 [list set ctx $ctx]
        uplevel #0 [list set w   $pw]
        uplevel #0 [list set h   $ph]
        if {[catch {uplevel #0 $cmd} _err _opts]} {
            puts stderr "tkmcairo::surface drawcommand error: $_err\n[dict get $_opts -errorinfo]"
        }
    }
    catch {$ctx finish}
    catch {$ctx destroy}
}

# ============================================================
proc tkmcairo::surface::_cleanup {w} {
    set ns ::tkmcairo::surface::S_${w}
    catch {
        if {[set ${ns}::ctx] ne ""} { [set ${ns}::ctx] destroy }
        image delete [set ${ns}::photo]
        namespace delete $ns
    }
    catch { unset ::tkmcairo::surface::_frameCmd($w) }
    catch { interp alias {} $w {} }  ;# remove alias
}
