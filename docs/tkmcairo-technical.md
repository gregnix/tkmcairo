# tkmcairo — Technische Dokumentation

Stand: 2026-04-27 | Version: 0.1.1

---

## Architektur-Überblick

```
Tk-Applikation
      |
tkmcairo::surface     (ttk::frame + ttk::label + Tk photo image)
      |
tclmcairo             (Off-screen Cairo context)
      |
Cairo                 (2D Vektorgrafik, C-Bibliothek)
      |
     topng → PNG-Bytes → Tk photo image → ttk::label
```

---

## tkmcairo::surface — Implementierung

### Widget-Command-Trick: rename + interp alias

Tk vernichtet ein Fenster wenn sein Tcl-Command gelöscht wird.
`interp alias {} .w {} handler` löscht zuerst den existierenden
Command, was das Fenster zerstört.

**Korrekte Reihenfolge:**
```tcl
ttk::frame $w
# 1. Erst rename — Command verschoben, Fenster bleibt erhalten
rename $w ::tkmcairo::surface::_frame_[string map {. _ : _} $w]
# 2. Dann alias — $w existiert nicht mehr als Command → nichts wird gelöscht
interp alias {} $w {} ::tkmcairo::surface::_cmd $w
```

Der interne Frame-Command wird in `_frameCmd($w)` gespeichert für
Weiterleitungen im `default`-Fall von `_cmd`.

### Namespace-Konvention

State-Namespace: `::tkmcairo::surface::S_$w`

Das `S_`-Prefix ist nötig weil der Widget-Pfad einen Punkt enthält:
`.s` → `S_.s`. Namespace-Namen mit führendem Punkt wären problematisch.

```tcl
namespace eval ::tkmcairo::surface::S_$w {
    variable ctx      ""   ;# tclmcairo-Context-Objekt
    variable photo    ""   ;# Tk photo image name
    variable width    0    ;# aktuelle Breite
    variable height   0    ;# aktuelle Höhe
    variable pending  0    ;# Debounce-Flag
    variable opts          ;# Optionen-Array
}
```

### Drawcommand-Convention

Surface setzt drei globale Variablen und evaluiert dann das Skript:

```tcl
uplevel #0 [list set ctx $ctx]   ;# tclmcairo Context-Objekt
uplevel #0 [list set w   $pw]    ;# Breite in Pixeln
uplevel #0 [list set h   $ph]    ;# Höhe in Pixeln
catch {uplevel #0 $cmd}
```

**Skript-Stil (für Endnutzer):**
```tcl
-drawcommand {myDraw $ctx $w $h}

proc myDraw {ctx w h} {
    $ctx clear 1 1 1 1
    $ctx circle [expr {$w/2.0}] [expr {$h/2.0}] 50 -fill {0.2 0.5 0.9}
}
```

**Proc-Verweis-Stil (für interne Nutzung, z.B. plot):**
```tcl
-drawcommand [list ::mypkg::_drawentry .w]

proc ::mypkg::_drawentry {self} {
    global ctx w h   ;# von surface als globale Vars gesetzt
    ::mypkg::_draw $self $ctx $w $h
}
```

Beide Stile funktionieren weil `uplevel #0` im globalen Kontext
evaluiert und dort `$ctx`, `$w`, `$h` zugänglich sind.

### Resize-Debounce

`<Configure>` feuert bei jedem Pixel beim Resize. Debounce 30ms:

```tcl
proc ::tkmcairo::surface::_onConfigure {w nw nh} {
    ...
    if {[set ${ns}::pending]} return
    set ${ns}::pending 1
    after 30 [list catch [list ::tkmcairo::surface::_redraw $w]]
}
```

### Context-Lifecycle

Pro Redraw:
1. Alter Context zerstören (falls vorhanden)
2. Neuen Context erstellen: `tclmcairo::new $pw $ph`
3. Background füllen
4. Drawcommand evaluieren
5. `$ctx topng` → PNG-Bytes
6. `$photo put $pngdata -format png`

Context wird in `${ns}::ctx` gehalten für `$w ctx`-Abfragen.
**Wichtig:** Immer `$ctx destroy` aufrufen, MAX_CTX=256.

### PNG-Export

`$ctx save $file` ist nicht für Raster-Contexts implementiert.
Korrekte Vorgehensweise:

```tcl
set fh [open $file wb]
fconfigure $fh -translation binary
puts -nonewline $fh [$ctx topng]
close $fh
```

### Vektor-Export (PDF/SVG/PS/EPS)

Neuer Vektor-Context, drawcommand erneut ausführen:

```tcl
set ctx [tclmcairo::new $pw $ph -mode pdf -file $file]
# ... background + drawcommand ...
catch {$ctx finish}
catch {$ctx destroy}
```

---

## tkmcairo::plot — Implementierung

### Schichtung: plot auf surface

plot erstellt intern eine `tkmcairo::surface` unter demselben
Widget-Pfad `$w`. Die surface installiert per `rename` + `interp alias`
ihren Command unter `$w`. plot überschreibt diesen Alias dann:

```tcl
tkmcairo::surface $w ...      ;# installiert Alias .p → surface::_cmd
interp alias {} $w {} ::tkmcairo::plot::_cmd $w  ;# überschreibt
```

Da surface bereits `rename` gemacht hat, löscht der zweite
`interp alias`-Aufruf nur den surface-Alias — das Tk-Fenster
bleibt erhalten.

### _cmd darf nie $w aufrufen

`$w` ist der Alias auf `_cmd` selbst → `$w subcmd` = infinite recursion.
Alle Weiterleitungen gehen direkt auf interne Procs:

```tcl
# FALSCH — rekursiv:
redraw { $w redraw }

# RICHTIG — direkte Proc-Aufrufe:
redraw { ::tkmcairo::surface::_redraw $w }
export { ::tkmcairo::surface::_export $w {*}$args }
default { ::tkmcairo::surface::_cmd $w $subcmd {*}$args }
```

### Drawcommand-Bridge

plot registriert bei surface einen Proc-Verweis:
```tcl
-drawcommand [list ::tkmcairo::plot::_drawentry $w]
```

`_drawentry` greift auf die von surface gesetzten globalen Variablen zu:
```tcl
proc ::tkmcairo::plot::_drawentry {plotw} {
    global ctx w h
    ::tkmcairo::plot::_draw $plotw $ctx $w $h
}
```

### Koordinaten-Transformation

`apply`-Lambdas mit expliziten Parametern (kein Closure-Problem):

```tcl
set toX [list apply [list {v px0 xmin xscale} {
    expr {$px0 + ($v - $xmin) * $xscale}
}]]
set px [{*}$toX $xval $px0 $xmin $xscale]
```

**Warum nicht globale procs?**
Globale procs haben keine Closure über lokale Variablen.
```tcl
# FALSCH — $px0 ist zur Laufzeit nicht definiert:
proc _X {v} [list expr "\$px0 + (\$v - $xmin) * $xscale"]
```

### Clipping — bekannte Einschränkung

`$ctx rect x y w h -fill ...` füllt und löscht danach den Pfad.
`$ctx clip` danach clippt auf leeren Pfad → alle folgenden
Zeichenoperationen unsichtbar.

→ Clipping in Series-Procs deaktiviert. Datenpunkte außerhalb
  des Plot-Bereichs werden gezeichnet. Fix geplant für 0.2.

---

## Bekannte Einschränkungen (0.1)

| Problem | Ursache | Fix |
|---------|---------|-----|
| Kein Clipping in Plot-Series | Cairo rect löscht Pfad | 0.2 |
| text_extents-Demo unvollständig | ctx-Objekt nicht OO-transparent | 0.2 |
| Zoom/Pan fehlt | kein viewport-Widget | 0.2 |

---

## Datei-Struktur

```
tkmcairo/
├── README.md
├── docs/
│   ├── tkmcairo-technical.md    ← dieses Dokument
│   ├── tkmcairo-concept.md      ← Architektur-Vision
│   └── tkmcairo-roadmap.md      ← Versionsplanung
├── nogit/
│   ├── TODO.md
│   ├── ROADMAP.md
│   └── uebergabe-0.1.md
├── tcl/tkmcairo/
│   ├── surface-0.1.tm           ← Core Widget
│   └── plot-0.1.tm              ← Chart Widget
└── demos/
    ├── demo-surface.tcl
    ├── demo-plot.tcl
    └── demo-imageviewer.tcl
```
