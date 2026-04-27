# tkmcairo pkgIndex.tcl — version 0.1.1
#
# Each module is provided as a Tcl Module (TM) under tkmcairo/.
# This pkgIndex stays in sync when the .tm filenames are versioned.

package ifneeded tkmcairo::surface 0.1.1 \
    [list source [file join $dir tkmcairo/surface-0.1.1.tm]]

package ifneeded tkmcairo::plot 0.1.1 \
    [list source [file join $dir tkmcairo/plot-0.1.1.tm]]

package ifneeded tkmcairo::coords 0.1.1 \
    [list source [file join $dir tkmcairo/coords-0.1.1.tm]]

package ifneeded tkmcairo::axis 0.1.1 \
    [list source [file join $dir tkmcairo/axis-0.1.1.tm]]

package ifneeded tkmcairo::legend 0.1.1 \
    [list source [file join $dir tkmcairo/legend-0.1.1.tm]]

package ifneeded tkmcairo::data 0.1.1 \
    [list source [file join $dir tkmcairo/data-0.1.1.tm]]

package ifneeded tkmcairo::viewport 0.1.1 \
    [list source [file join $dir tkmcairo/viewport-0.1.1.tm]]

package ifneeded tkmcairo::scene 0.1.1 \
    [list source [file join $dir tkmcairo/scene-0.1.1.tm]]

package ifneeded tkmcairo::svgview 0.1.1 \
    [list source [file join $dir tkmcairo/svgview-0.1.1.tm]]

package ifneeded tkmcairo::pageview 0.1.1 \
    [list source [file join $dir tkmcairo/pageview-0.1.1.tm]]

package ifneeded tkmcairo::imageviewer 0.1.1 \
    [list source [file join $dir tkmcairo/imageviewer-0.1.1.tm]]
