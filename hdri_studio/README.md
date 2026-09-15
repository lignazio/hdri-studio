# HDRI Studio — progetto Godot

Godot 4.7.1, Forward+. Il piano completo è in `../PIANO.md`.

## Avvio

Serve solo Godot 4.7.1 (https://godotengine.org/download — la versione "Standard", non .NET).
Apri `hdri_studio/` con Godot ed esegui la scena principale (F5), oppure da terminale:

    # macOS
    /Applications/Godot.app/Contents/MacOS/Godot --path hdri_studio
    # Windows (PowerShell, dalla cartella dove hai messo l'eseguibile)
    .\Godot_v4.7.1-stable_win64.exe --path hdri_studio

Al primo avvio su una macchina nuova Godot rigenera la cartella `.godot/` (import): ci mette qualche
secondo. Se lanci da terminale prima di aver aperto il progetto nell'editor, fai prima un
`--headless --import` per costruire la cache delle classi.

Il rig salva il percorso dell'HDRI di base in assoluto: spostando un rig fra Mac e PC va ricaricata.

Layout: **luci + proprietà** | **preview 3D / mappa** | **sfondo + export**.

Controlli: trascina nel 3D = orbita · rotella = zoom · **Shift + trascina su una sfera = LightPaint**
(la luce selezionata si sposta dove serve per riflettersi sotto il cursore) · sulla mappa: click su una
maniglia seleziona, drag sposta, click sul vuoto porta lì la luce selezionata · Q/E = esposizione della
preview (solo visualizzazione) · ⌘Z / ⇧⌘Z = undo/redo.

Export: risoluzione 2k/4k/8k, half o float32, preset di orientamento per software (Cinema 4D = specchio
orizzontale, misurato con la taratura), rotazione extra. Il rig si salva/apre come JSON.

Smoke test dell'interfaccia senza click (add/duplica/elimina, slider, mappa, LightPaint, undo, solo,
HDRI di base, salva/apri rig, export con flip):

    /Applications/Godot.app/Contents/MacOS/Godot --path hdri_studio -s res://tools/ui_smoke.gd

## Spike di Fase 0 (bake → EXR → PNG di controllo, senza UI)

    /Applications/Godot.app/Contents/MacOS/Godot --path hdri_studio -s res://tools/fase0_spike.gd
    .\Godot_v4.7.1-stable_win64.exe --path hdri_studio -s res://tools/fase0_spike.gd

Scrive in `out/`: `calibration`, `furnace`, `rect`, `shapes`, `scrim`, `studio` (EXR half, EXR float32,
PNG di controllo, JSON del rig).

## Verifica fisica con Blender/Cycles

    /Applications/Blender.app/Contents/MacOS/Blender -b --python hdri_studio/tools/blender_verify.py -- hdri_studio/out

Furnace test, calibrazione dell'orientamento di Blender, irradianza di una singola luce confrontata con
l'integrale numerico e con un render Cycles.

## Struttura

    core/      RigLight, LightRig (modello dati, JSON), ColorTemp (Kelvin → Rec.709 lineare), UndoStack
    bake/      bake.glsl (compute shader), HdriBaker (RenderingDevice, texture RGBA32F)
    preview/   Preview3D (viewport, sfere, LightPaint), shader della sfera cromata e della mappa 2D
    ui/        ParamRow, LightListPanel, LightProperties, BackgroundPanel, ExportPanel, MapView
    export/    HdriExport (EXR half/float32, PNG di controllo)
    scenes/    main.tscn / main.gd — app
    tools/     spike di Fase 0, verifica Blender, smoke test UI
    out/       output generati (ignorati da git)
