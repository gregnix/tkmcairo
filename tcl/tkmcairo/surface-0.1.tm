# tkmcairo::surface 0.1
#
# Cairo drawing widget backed by ttk::frame + tclmcairo + Tk photo image.
#
# Usage:
#   tkmcairo::surface pathName ?-width W -height H -drawcommand SCRIPT ...?
#   SCRIPT receives: ctx w h
#
#   $w redraw             force redraw
#   $w export filename    save PNG/PDF/SVG/PS/EPS
#   $w ctx                current tclmcairo context
#   $w width / $w height  current size
#   $w configure ...      update options
#   $w cget option        query option
#
# Part of tkmcairo -- https://github.com/gregnix/tkmcairo
# License: BSD 2-Clause

package provide tkmcairo::surface 0.1

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
proc tkmcairo::surface::_export {w file args} {
    if {![winfo exists $w]} return
    set ns ::tkmcairo::surface::S_${w}
    set pw [set ${ns}::width]
    set ph [set ${ns}::height]

    set ext [string tolower [file extension $file]]
    set mode [switch $ext {
        .pdf {expr {"pdf"}} .svg {expr {"svg"}}
        .ps  {expr {"ps"}}  .eps {expr {"eps"}}
        default {expr {"png"}}
    }]

    if {$mode eq "png"} {
        # Render fresh and write PNG bytes to file
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
        if {![catch {$pctx topng} pngdata]} {
            set fh [open $file wb]
            fconfigure $fh -translation binary
            puts -nonewline $fh $pngdata
            close $fh
        }
        catch {$pctx destroy}
        return
    }

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
