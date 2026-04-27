# tkmcairo Makefile

PACKAGE_NAME    = tkmcairo
PACKAGE_VERSION = 0.1

TCLSH   ?= tclsh
WISH    ?= wish

# tclmcairo Installation (für Tests + Demos)
TCLMCAIRO_DIR ?= /usr/lib/tcltk/tclmcairo0.3.4

# Installationsverzeichnis
INSTALL_DIR ?= /usr/lib/tcltk/$(PACKAGE_NAME)$(PACKAGE_VERSION)

# ================================================================
# Installation
# ================================================================
install:
	install -d $(INSTALL_DIR)/tkmcairo
	install -m 644 tcl/pkgIndex.tcl         $(INSTALL_DIR)/pkgIndex.tcl
	install -m 644 tcl/tkmcairo/*.tm        $(INSTALL_DIR)/tkmcairo/
	@echo "Installed: $(INSTALL_DIR)"

uninstall:
	rm -rf $(INSTALL_DIR)
	@echo "Removed: $(INSTALL_DIR)"

# ================================================================
# Tests + Demos
# ================================================================
test:
	TCLMCAIRO_LIBDIR=$(TCLMCAIRO_DIR) $(WISH) tests/test-tkmcairo.tcl

demo-surface:
	TCLMCAIRO_LIBDIR=$(TCLMCAIRO_DIR) $(WISH) demos/demo-surface.tcl

demo-plot:
	TCLMCAIRO_LIBDIR=$(TCLMCAIRO_DIR) $(WISH) demos/demo-plot.tcl

demo-viewport:
	TCLMCAIRO_LIBDIR=$(TCLMCAIRO_DIR) $(WISH) demos/demo-viewport.tcl

demo-scene:
	TCLMCAIRO_LIBDIR=$(TCLMCAIRO_DIR) $(WISH) demos/demo-scene.tcl

demo-axis:
	TCLMCAIRO_LIBDIR=$(TCLMCAIRO_DIR) $(WISH) demos/demo-axis.tcl

demo-imageviewer:
	TCLMCAIRO_LIBDIR=$(TCLMCAIRO_DIR) $(WISH) demos/demo-imageviewer.tcl

demo-svgview:
	TCLMCAIRO_LIBDIR=$(TCLMCAIRO_DIR) $(WISH) demos/demo-svgview.tcl

demo-pageview:
	TCLMCAIRO_LIBDIR=$(TCLMCAIRO_DIR) $(WISH) demos/demo-pageview.tcl

demo: demo-surface demo-plot demo-viewport demo-scene demo-axis demo-svgview

.PHONY: install uninstall test demo \
        demo-surface demo-plot demo-viewport demo-scene demo-axis demo-imageviewer demo-svgview demo-pageview
