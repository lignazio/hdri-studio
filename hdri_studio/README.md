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

## Modalità fotometrica

Nel pannello proprietà, *Fotometrico (illuminamento al centro)*: invece della radianza si imposta
l'**illuminamento E** che la luce produce al centro della sfera su una superficie che la guarda (unità
arbitrarie ma coerenti fra luci). La radianza è `E / K`, con `K = ∫ w(d)·cosθ dω` misurato sul GPU nel
frame locale della luce — profilo, sfumatura e immagine compresi — e ricalcolato solo quando cambia la
forma. Due luci con lo stesso E espongono allo stesso modo qualunque sia la loro dimensione: allargare
una softbox la rende più morbida, non più forte. Il pannello mostra K e la radianza risultante.

## Fusione e ordine

Fusione per luce: **Somma** (fisica, default), **Massimo**, **Moltiplica** (maschere/bandiere) e
**Normale** (la luce copre ciò che c'è sotto dove sta: utile per le HDRI light con il proprio fondo).
Con Normale l'ordine conta: le luci più in basso nell'elenco coprono quelle sopra; ▲ ▼ riordinano.

I bordi fra le colonne e fra preview e mappa si trascinano.

## Live link con Cinema 4D (Octane)

Plugin in `plugins/c4d/hdri_studio_link/` — installazione e uso in `plugins/c4d/README.md`. In breve:
pannello **Live link** → *File di export…* → *Attivo*; carica lo stesso file in un ImageTexture di Octane;
ogni modifica riscrive il file e il plugin preme Reload sui nodi che lo usano. Protocollo JSON-lines su
TCP 127.0.0.1:47820, con fallback sulla data di modifica del file se l'app non è collegata.

## Luci Texture e catalogo

Una luce **Texture** proietta un'immagine EXR/HDR lineare (una "HDRI light": softbox fotografata, lampada,
finestra) sul proprio rettangolo angolare; intensità, EV, Kelvin e tinta la moltiplicano, la sfumatura fa
da maschera. Si crea da *+ Aggiungi → Texture* (scegli un file) o dal **Catalogo** (tab nella colonna
sinistra): punta una tua cartella (ricorsiva, ricordata in `user://settings.json`), le miniature vengono
generate in un thread e messe in cache in `user://thumbs/`, click su una miniatura → la luce entra nel rig.

Il rig salva **solo il percorso** del file. Accanto a un'immagine puoi mettere un sidecar `nome.json`
(o `nome.exr.json`) con i valori di default che il catalogo userà:

    {"name": "Softbox 60x90", "width": 25, "height": 37, "intensity": 3, "ev": 0, "kelvin": 5600, "softness": 0.5, "roll": 0}

Senza sidecar: 30° di larghezza, altezza dall'aspetto dell'immagine. Le miniature sono raggruppate per
sottocartella (intestazione gialla) e il menu a tendina limita la vista a una sottocartella. Sul GPU le immagini vivono in un
texture array 2048×1024 × 12 strati (RGBA16F, ~200 MB): oltre 12 luci Texture diverse contemporaneamente
le meno usate vengono ricaricate al bisogno.

LightPaint da C4D: tool "HDRI Studio LightPaint" nel plugin (vedi il README del plugin). Nel preview
dell'app si può caricare un GLB (pannello *Modello nel preview*) al posto della sfera centrale, con
materiale originale/cromato/glossy/diffuso: Shift+trascina sul modello funziona come sulle sfere.

Smoke test del link (app + client Python finto, da due terminali o in sequenza):

    /Applications/Godot.app/Contents/MacOS/Godot --path hdri_studio -s res://tools/link_smoke.gd &
    python3 hdri_studio/plugins/c4d/hdri_studio_link/link_core.py

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

    core/      RigLight, LightRig (modello dati, JSON), ColorTemp, UndoStack, AppSettings, ThumbnailCache
    bake/      bake.glsl (compute shader), HdriBaker (RenderingDevice, texture RGBA32F)
    preview/   Preview3D (viewport, sfere, LightPaint), shader della sfera cromata e della mappa 2D
    ui/        ParamRow, LightListPanel, LightProperties, BackgroundPanel, ExportPanel, LiveLinkPanel, CatalogPanel, MapView
    export/    HdriExport (EXR half/float32, PNG di controllo)
    scenes/    main.tscn / main.gd — app
    livelink/  LiveLink (server TCP, JSON-lines)
    plugins/   c4d/hdri_studio_link (plugin Cinema 4D), c4d/octane_reload_probe.py (sonda di Fase 0)
    tools/     spike di Fase 0, verifica Blender, smoke test UI e link
    out/       output generati (ignorati da git)
