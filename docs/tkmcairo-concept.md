# tkmcairo — Konzept und Architektur-Vision

Stand: 2026-04-27

---

## Ziel

tkmcairo ist **keine** Canvas-Erweiterung und kein Canvas-Klon.
Es ist eine Cairo-basierte Rendering-Plattform für Tk — mit zwei Ebenen:

1. **Rendering-Bausteine** — wiederverwendbare Hilfsfunktionen für
   Koordinaten, Achsen, Legende, Daten
2. **Fertige Widgets** — surface, plot, viewport, scene

Dritte können eigene Chart-Typen oder Visualisierungen bauen
ohne Cairo-Details zu kennen — nur die Bausteine verwenden.

---

## Vergleich: Plotchart vs tkmcairo

| Merkmal | tklib Plotchart | tkmcairo::plot |
|---------|----------------|----------------|
| Rendering | Tk-Canvas | Cairo (Antialiasing) |
| PDF-Export | nein (Umweg) | nativ, Vektorqualität |
| SVG-Export | nein | nativ |
| Gradients/Alpha | nein | ja |
| Erweiterbarkeit | schwer (globale Arrays) | Bausteine |
| Chart-Typen | 30+ | 4 (0.1), wächst |
| Zeitachsen | ja | geplant 0.2 |
| Reife | sehr hoch | 0.1 |

**Plotchart und tkmcairo schließen sich nicht aus.**
Wer Plotchart kennt kann tkmcairo-Algorithmen (niceTicks, determineScale)
aus plotaxis.tcl übernehmen — die Lizenz (Tcl-Lizenz, Arjen Markus)
erlaubt das mit Attribution.

---

## Architektur-Übersicht

```
Applikation / eigene Algorithmen
        |
tkmcairo::plot          fertige Charts (line, area, bar, scatter, pie ...)
        |
tkmcairo::helpers       Rendering-Bausteine (coords, axis, legend, data)
        |
tkmcairo::surface       Cairo-Zeichenfläche als Tk-Widget
        |
tclmcairo               Low-Level Cairo Binding (C-Extension)
        |
Cairo 1.18+             2D Vektorgrafik
```

---

## Modul-Struktur (aktuell + geplant)

```
tcl/tkmcairo/
  surface-0.1.tm     (0.1) ← Core Widget: ttk::label + tclmcairo
  plot-0.1.tm        (0.1) ← Fertige Charts: line, area, scatter, bar

  coords-0.1.tm      (0.2) ← Koordinaten-Transformation
  axis-0.1.tm        (0.2) ← Achsen zeichnen (X, Y, Zeit)
  legend-0.1.tm      (0.2) ← Legende
  data-0.1.tm        (0.2) ← Daten-Hilfsfunktionen

  viewport-0.1.tm    (0.2) ← Scrollbares/zoombares Surface
  scene-0.1.tm       (0.2) ← Retained-Mode Szenengraph
  widgets-0.1.tm     (0.2) ← Cairo-gerenderte Tk-Widgets

  pageview-0.1.tm    (0.3) ← PDF-Seiten-Anzeige
```

---

## Rendering-Bausteine (helpers) — Detailplan

### tkmcairo::coords

Koordinaten-Transformation zwischen Datenwelt und Cairo-Pixeln.
Basis für alle Chart-Typen.

```tcl
# Transform-Objekt erstellen
set tr [tkmcairo::coords::transform new \
    -xmin 0 -xmax 12 -ymin -15 -ymax 45 \
    -px0 60 -py0 40 -px1 580 -py1 360]

# Koordinaten umrechnen
set px [$tr toPixelX 6.5]
set py [$tr toPixelY 22.3]
lassign [$tr toPixel 6.5 22.3] px py
lassign [$tr toWorld $px $py] xv yv

# Pan + Zoom
$tr zoom  1.5 $cx $cy   ;# Zoom um Mittelpunkt
$tr pan   20  -10        ;# Verschiebung in Pixel
$tr reset               ;# Ursprung

# Abfragen
lassign [$tr worldBounds] xmin xmax ymin ymax
lassign [$tr pixelBounds] px0 py0 px1 py1
```

### tkmcairo::axis

Achsen zeichnen mit Cairo. Nutzt coords-Transform intern.

```tcl
tkmcairo::axis::drawX $ctx $tr \
    -label "Monat" \
    -format "%.0f" \
    -ticks 12 \
    -grid 1 \
    -gridcolor {0.88 0.88 0.88} \
    -ticklen 5 \
    -font "Sans 10"

tkmcairo::axis::drawY $ctx $tr \
    -label "°C" \
    -format "%.1f" \
    -ticks 5 \
    -grid 1

# Zeitachse (Datum/Uhrzeit)
tkmcairo::axis::drawTimeX $ctx $tr \
    -start "2026-01-01" \
    -end   "2026-12-31" \
    -format "%b" \
    -ticks monthly

# Zweite Y-Achse rechts
tkmcairo::axis::drawY2 $ctx $tr2 -label "%" -color {0.8 0.3 0.2}
```

### tkmcairo::legend

Legende zeichnen.

```tcl
tkmcairo::legend::draw $ctx $series \
    -position ne \
    -font "Sans 10" \
    -background {1 1 1 0.85} \
    -border {0.7 0.7 0.7}
```

### tkmcairo::data

Daten-Hilfsfunktionen.

```tcl
# Wertebereich aus Datenliste
lassign [tkmcairo::data::range $xydata] xmin xmax ymin ymax

# Zeitstempel → numerischer Wert
set t [tkmcairo::data::timeToNum "2026-06-15"]

# Glättung (Moving Average)
set smooth [tkmcairo::data::smooth $xydata 3]

# Statistik für Boxplot
lassign [tkmcairo::data::boxstats $values] q0 q1 median q3 q4

# Aggregation für Histogramm
set bins [tkmcairo::data::histogram $values -bins 10 -min 0 -max 100]
```

---

## Eigene Chart-Typen bauen

Wer einen neuen Chart-Typ (z.B. Boxplot, Gantt, Radar) bauen will
braucht nur die Bausteine — keine Cairo-Kenntnisse nötig:

```tcl
package require tkmcairo::surface
package require tkmcairo::coords
package require tkmcairo::axis
package require tkmcairo::legend

tkmcairo::surface .p -width 600 -height 400 \
    -drawcommand {drawBoxplot $ctx $w $h $mydata}

proc drawBoxplot {ctx w h data} {
    # 1. Koordinaten-Transform
    set tr [tkmcairo::coords::transform new \
        -xmin 0 -xmax [llength $data] \
        -ymin 0 -ymax 100 \
        -px0 60 -py0 20 -px1 [expr {$w-20}] -py1 [expr {$h-40}]]

    # 2. Achsen
    tkmcairo::axis::drawX $ctx $tr -ticks [llength $data]
    tkmcairo::axis::drawY $ctx $tr -grid 1

    # 3. Eigener Algorithmus — nur Cairo
    set i 0
    foreach {lbl values} $data {
        lassign [tkmcairo::data::boxstats $values] q0 q1 med q3 q4
        set px [$tr toPixelX $i]
        # ... Cairo zeichnen ...
        incr i
    }
}
```

---

## Widget-Hierarchie

```
tkmcairo::surface          Core Widget (fertig)
    |
    ├── tkmcairo::plot      Fertige Charts (fertig, wächst)
    |
    ├── tkmcairo::viewport  Scrollbar + Zoom/Pan (0.2)
    |       |
    |       └── tkmcairo::pageview  PDF-Anzeige (0.3)
    |
    └── tkmcairo::scene     Retained-Mode Szenengraph (0.2)
            |
            └── tkmcairo::widgets  Cairo-Widgets (0.2)
```

---

## Abgrenzung

| Projekt | Zweck | Verhältnis |
|---------|-------|------------|
| tklib Plotchart | 30+ Chart-Typen, Canvas | Algorithmen nutzbar (Tcl-Lizenz) |
| tkpath | Cairo-Canvas-Extension | Braucht Display, anderes Ziel |
| TkMoin | Wayland-natives GUI | Widgets-Code portierbar |
| tclmcairo | Cairo-C-Binding | Basis von tkmcairo |
| BLT | Chart-Widgets | Kein Export, kein Antialiasing |

---

## Kernprinzipien

**Composability** — Kleine Module, aufeinander aufbauend.
Niemand muss alles importieren.

**Tk-Philosophie** — Widget-Pfade, Geometry-Manager-kompatibel,
keine eigene Event-Loop.

**Drawcommand-Pattern** — Dasselbe Skript für Screen + Export.
`$ctx $w $h` als Variablen — einfach erweiterbar.

**Cairo-Qualität** — Antialiasing, Gradients, Alpha, Vektorexport.
Das ist der Hauptvorteil gegenüber Canvas-basierten Lösungen.
