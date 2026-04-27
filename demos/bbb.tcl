package require tkmcairo::viewport

tkmcairo::viewport .vp \
    -width 600 -height 400 \
    -worldwidth 2000 -worldheight 2000 \
    -scrollbars 1 \
    -drawcommand {
        $ctx circle [expr {$zoom * 500}] [expr {$zoom * 300}] 100 \
            -fill {0.2 0.5 0.9}
    }
pack .vp