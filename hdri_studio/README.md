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

## Preset di studio

Tab **Preset** nella colonna sinistra: *Salva preset…* scrive il rig corrente (`<nome>.json` + miniatura
PNG dal preview) nella cartella della libreria (`user://presets` di default, cambiabile). *Carica*
sostituisce il rig, *Aggiungi luci* appende le luci del preset a quello corrente, doppio click = carica.
La libreria è una cartella di file JSON: si copia, si versiona, si condivide.

## Preferiti, tag, anteprima

Nel catalogo, tasto destro su una miniatura → *★ Preferito* / *Tag…* (separati da virgola). I preferiti
hanno la stella nel nome; la spunta ★ mostra solo quelli; il menu dei tag filtra per tag; il campo di
testo cerca in nomi e tag. I metadati stanno in `user://catalog_meta.json`, chiave = percorso relativo
alla cartella del catalogo (la collezione non viene toccata). Passando il mouse su una miniatura compare
un'anteprima più grande.

## Spazio colore

Il bake lavora in Rec.709 lineare (D65) e la preview lo mostra così. Nel pannello Export, *Spazio colore*
→ **ACEScg**: i valori vengono convertiti sul GPU (Rec.709 → AP1 con adattamento Bradford, la matrice
standard 0.6131/0.3395/0.0474…) e i metadati dell'EXR dichiarano i primari AP1 con bianco D60. Vale anche
per gli EXR delle luci separate. Verificato: rosso Rec.709 puro → (0.613, 0.070, 0.021) in AP1.

## Codec EXR (GDExtension HsOpenEXR)

Gli EXR sono scritti e letti da **OpenEXR 3.4** (BSD-3) compilato dentro una GDExtension in C++
(`gdextension/`, binari in `addons/hs_openexr/bin/` per macOS universal e Windows x86_64). Nel pannello
Export, *Compressione* offre PIZ, ZIP, ZIPS, RLE, NONE (lossless) e PXR24, B44, B44A, DWAA, DWAB
(lossy): il file esce direttamente nel codec scelto, con i metadati, in una scrittura sola (4k×2k half:
~0,7 s compreso il bake). Il live link usa sempre PIZ. In lettura, gli EXR del catalogo o di base con
qualunque codec (DWAA/DWAB compresi, comuni nelle collezioni commerciali) si aprono senza conversioni.
Blender non serve più per nulla di tutto questo.

Senza l'estensione (piattaforma senza binario) resta TinyEXR di Godot: scrive solo PIZ, i metadati
vengono iniettati dopo la scrittura (`HdriExport.inject_metadata`) e DWAA/DWAB/B44/PXR24 non si leggono.

API dell'estensione, da GDScript tramite `ExrCodec` (`core/exr_codec.gd`):

    HsOpenEXR.save(image, path, codec := "PIZ", half := true, attributes := {}, dwa_level := 45.0) -> Error
    HsOpenEXR.load(path) -> Image            # RGBAF, qualunque codec; layer "beauty.R" e Y monocromatico gestiti
    HsOpenEXR.info(path) -> Dictionary       # width, height, compression, channels, half, attributes (string)
    HsOpenEXR.codecs() -> PackedStringArray, HsOpenEXR.version() -> String

`attributes`: String → attributo string, PackedFloat32Array di 8 → `chromaticities`, float/int → float/int.
Scrittura atomica (temporaneo + rinomina). Si scrivono solo R, G, B.

Per ricompilarla: `tools/build_gdextension.sh [macos|windows]` (cmake ≥ 3.24; per Windows dal Mac
`brew install mingw-w64`). Scarica OpenEXR 3.4.9 (+ Imath, libdeflate e OpenJPH vendored) e godot-cpp
v10 al primo avvio, in `gdextension/build/` (ignorata). Test: `tools/exr_smoke.gd` (tutti i codec,
half/float32, rilettura, metadati, compatibilità TinyEXR).

## Modalità fotometrica

Nel pannello proprietà, *Fotometrico (illuminamento al centro)*: invece della radianza si imposta
l'**illuminamento E** che la luce produce al centro della sfera su una superficie che la guarda (unità
arbitrarie ma coerenti fra luci). La radianza è `E / K`, con `K = ∫ w(d)·cosθ dω` misurato sul GPU nel
frame locale della luce — profilo, sfumatura e immagine compresi — e ricalcolato solo quando cambia la
forma. Due luci con lo stesso E espongono allo stesso modo qualunque sia la loro dimensione: allargare
una softbox la rende più morbida, non più forte. Il pannello mostra K e la radianza risultante.

## Fusione e ordine

Fusione per luce: **Somma** (fisica, default), **Massimo**, **Moltiplica** (maschere/bandiere) e
**Normale** (la luce copre ciò che c'è sotto in tutta la sua forma, parti scure comprese: per le HDRI
light con il proprio fondo e per gli scrim che hanno un corpo dietro il telo; il Gradiente resta morbido).
Con Normale l'ordine conta: le luci più in basso nell'elenco coprono quelle sopra; ▲ ▼ riordinano.

I bordi fra le colonne e fra preview e mappa si trascinano.

## App standalone

`export_presets.cfg` contiene i preset **macOS** (universal) e **Windows** (x86_64, PCK incorporato).
Servono i template di export di Godot 4.7.1 (Editor → Manage Export Templates → Download). Da terminale:

    /Applications/Godot.app/Contents/MacOS/Godot --headless --path hdri_studio --export-release "macOS" "../dist/HDRI Studio.app"
    /Applications/Godot.app/Contents/MacOS/Godot --headless --path hdri_studio --export-release "Windows" "../dist/windows/HDRI Studio.exe"

oppure dall'editor: Project → Export. L'app esportata accetta `-- --selftest` (bake + EXR + rilettura,
esce con 0 se tutto va) e `-- --screenshot`. `dist/` non è nel repository: si ricostruisce.

Dal catalogo le miniature si possono anche **trascinare** sulla mappa (la luce nasce lì) o sul preview 3D
(la luce nasce sul riflesso del punto colpito, come il LightPaint).

## Luci separate (area light in Cinema 4D)

Nel pannello proprietà, *Separata → area light nel 3D* con lo slider **Distanza (cm)**. La luce resta
visibile nel preview ma **non entra nell'HDRI esportata**: viene scritta come EXR singolo accanto
all'HDRI (`<nome>_<luce>.exr`, proiezione planare in tan-space, radianza già applicata) e il live link
manda al plugin direzione, dimensione fisica `2·D·tan(w/2) × 2·D·tan(h/2)` e percorso. In C4D il plugin
clona una luce modello chiamata **`HS_TEMPLATE`** (un'Octane Area Light con un ImageTexture nel suo slot
texture, preparata una volta), la mette sotto il null `HDRI Studio Lights` nella direzione giusta a
distanza D, orientata verso il centro, con la dimensione fisica e l'EXR assegnato. Spostando il null le
luci seguono; togliendo il flag la luce sparisce dalla scena.

Da tarare al primo uso (costanti in cima al `.pyp`): il verso di emissione della luce modello
(`LIGHT_EMITS_ALONG_Z`) e, con il furnace test, il rapporto fra la Power di Octane e la radianza.

## Finestra (23/09)

`Main._setup_window()` apre l'app al 92% dell'area utile dello schermo, centrata, e `_save_window()`
ricorda geometria e stato massimizzato in `settings.json` (chiave `window`). Una geometria salvata si
ripristina solo se il centro della finestra cade dentro uno schermo esistente e la dimensione è almeno
960×600: monitor scollegato o risoluzione cambiata → si riparte dal default. Nei modi non interattivi
(`--fresh`, `--screenshot`, `--selftest`, `--export`, cioè `_unattended()`) non si tocca niente e
restano i 1600×900 del progetto, perché i test misurino sempre la stessa finestra. La chiamata sta in
fondo a `_ready()`: ridimensionare la finestra fa girare un giro di ciclo di eventi, e `_process`
troverebbe il baker non ancora creato.

## Sistema visivo e scala dello schermo (23/09)

`ui/ui_style.gd` (`UiStyle`) tiene in un posto solo il tema dell'app e le sue scale, in pixel logici:
testo 15 (titoli) / 13 / 11 (sottotitoli di sezione in maiuscolo, suggerimenti), spazi 4 fra righe,
8 fra controlli affiancati, 16 sopra un sottotitolo, 24 fra pannelli (l'unica linea orizzontale),
colonna etichette 104 px con i puntini se una traduzione non ci sta. Le etichette sono un gradino più
spente dei valori; l'ambra è riservata alla selezione e al pulsante di export. I pannelli costruiscono
titoli, sezioni e righe con gli helper di `UiStyle` invece di impostare font e colori a mano.

Nei pannelli laterali tutto sta a 16 px (`UiStyle.MARGIN`) dal bordo. Le aree che scorrono (colonna
destra, proprietà della luce) occupano il pannello per intero e hanno il margine *dentro*
(`UiStyle.pad()`), così la barra di scorrimento sta sul bordo e il testo resta a 16 px da lei; le
schede Catalogo e Preset sono avvolte nello stesso margine (`Main.tabs` è la `TabContainer`).

`Main._apply_ui_scale()` mette in `content_scale_factor` la densità dello schermo
(`screen_get_scale()` su macOS, DPI/96 su Windows) per il moltiplicatore *Text size* dell'utente, e la
ricalcola su `dpi_changed`. Nei modi non interattivi resta 1, come la finestra. Le icone di
`LightIcons` sono rese a 2× con size override 16×16; `Preview3D` non è più un `SubViewportContainer`
(che dimensiona il viewport in pixel logici, quindi 3D a metà risoluzione sul Retina): è un `Control`
che tiene il `SubViewport` alla dimensione fisica e lo disegna nel proprio rettangolo. La camera del
preview si allontana quanto serve a inquadrare le tre sfere con il FOV e le proporzioni correnti (mai
sotto la distanza storica di 7), e la rotella agisce come zoom relativo.

## Radiance .hdr e metadati EXR (16/09, il rig nel .hdr il 23/09)

Nella dialog di export scegli l'estensione: `.exr` (half/float32, codec a scelta) oppure `.hdr`
(Radiance RGBE, codificato sul GPU, non compresso: lo leggono tutti; precisione della mantissa a 8 bit).
Le luci separate seguono lo stesso formato.

Ogni EXR esportato porta nell'header `chromaticities` (Rec.709/D65), un `comments` e l'attributo
`hdristudio_rig` con il **rig completo in JSON**: *Apri rig…* accetta anche un EXR e ricostruisce il set
da lì. Gli attributi li scrive OpenEXR insieme ai pixel (HsOpenEXR); nel fallback TinyEXR vengono
iniettati dopo la scrittura aggiornando la tabella degli offset. Verificato con TinyEXR e con OpenEXR.

Anche il `.hdr` porta il rig: l'header Radiance è testo fino alla prima riga vuota, e ci scriviamo il
JSON compresso (deflate) e in base64, spezzato su righe corte: `#HDRISTUDIO_RIG_DEFLATE=<byte>` e poi
`#HDRISTUDIO_RIG_B64=<pezzo>`, al massimo 117 byte per riga. Le righe corte servono perché molti lettori
hanno un buffer fisso per riga (Three.js 1024 caratteri, `rgbe.c` 128 byte) e con una riga più lunga
perdono la risoluzione dell'immagine. Sono **commenti** di proposito: i lettori saltano i commenti in
silenzio, mentre una variabile sconosciuta fa rumore (Godot stampa un warning con tutta la riga). Si
leggono ancora i `.hdr` di prima del 28/09, con il JSON su una riga `#HDRISTUDIO_RIG=`. *Apri rig…*
rilegge il rig da `.exr` e da `.hdr` allo stesso modo
(`HdriExport.read_rig_json`).

Ogni luce ha un **🔒** (accanto a On/Solo): bloccata, non la spostano né il LightPaint né la mappa né
le frecce.

## Set, esposimetro, clipping, camera, materiali (16/09)

- **Ruota tutto** (pannello *Set*, in cima alla colonna destra): ruota tutte le luci attorno all'asse
  verticale; lo slider torna a 0 quando lo lasci. **⇋** nella lista duplica le luci selezionate
  specchiate sinistra ↔ destra (azimut, rotazione, angolo del gradiente, offset dello scrim, specchio
  della texture).
- **Esposimetro** (pannello *Preview*): `E = ∫ L·cosθ dω` su tutta l'HDRI (luci e sfondo) per una
  superficie al centro rivolta verso la camera, verso l'alto o verso un az/el scelto; `EV100 = log2(E/2.5)`.
  Ambiente uniforme 1.0 → E = π. Due rig con lo stesso E espongono uguale prima di renderizzare.
- **Clipping**: spunta + soglia; i pixel oltre la soglia diventano magenta sulla mappa e sulla sfera
  cromata (e sui metalli lucidi).
- **Camera dal live link**: spunta nel pannello *Preview*; C4D e Blender mandano la camera attiva
  (direzione, alto, FOV orizzontale) quando cambia e il preview la segue, alla distanza corrente dal
  centro. Con un GLB caricato vedi l'inquadratura del render.
- **Materiali di prova**: Oro giallo, Oro bianco, Argento, Platino, Rame (riflessi esatti dalla
  panoramica, tinti con la riflettanza F0 del metallo), Spazzolato (anisotropo), Vetro. Valgono per il
  modello caricato o, senza modello, per la sfera centrale.

## Rifiniture d'uso (15/09)

- **Mappa**: griglia in gradi, contorno reale delle luci (selezionate in giallo), az/el e RGB del pixel
  sotto il cursore nella status bar.
- **Preview**: click (senza trascinare) su un riflesso seleziona la luce che lo produce; tasto destro
  ruota il modello; slider di esposizione, FOV e scala del modello nel pannello *Preview*.
- **Tastiera**: frecce spostano le luci selezionate di 1° (Shift 10°), H accende/spegne, ⌘D duplica,
  Canc elimina, Q/E esposizione, ⌘Z / ⇧⌘Z undo/redo. Selezione multipla nella lista (⌘/Shift-click):
  trascinare una luce del gruppo sulla mappa sposta tutto il gruppo.
- **Luci**: Kelvin rapidi (3200/4300/5600/6500) e menu *Gelatine* (CTO/CTB per mired, Plus/Minus
  Green, Straw, colori); scrim con sorgente a disco integrata (12 campioni); Texture con specchio
  H/V, rotazione 90° e *Salva default* (scrive il sidecar); gradiente con *Valore* per tacca (oltre
  1), preset, copia/incolla.
- **Sfondo**: *Sfocatura* dell'HDRI di base (mipmap).
- **Catalogo**: *Miniature EV* (rigenera le miniature con un offset). **Preset**: rinomina.
- **Export**: ricorda la cartella, propone il nome del rig, *Apri cartella*. **Live link**: risoluzione
  adattiva (metà durante le modifiche ravvicinate, piena dopo 1,5 s di pausa). Luci separate:
  *Visibile alla camera nel 3D* per luce (Blender; C4D solo se il tag Octane espone "camera visibility").
- **Avvio**: riapre l'ultimo rig salvato/aperto (`-- --fresh` per partire dal rig di default);
  autosave ogni minuto in `user://autosave/` (ultimi 10).

## Live link con Blender

Add-on in `plugins/blender/hdri_studio_link/` — installazione e uso in `plugins/blender/README.md`.
Stesso protocollo di C4D; luci separate come piani emissivi (strength 1 = radianza, verificato in
Cycles), LightPaint con `ray_cast` e normali interpolate.

## Live link con Cinema 4D (Octane)

Plugin in `plugins/c4d/hdri_studio_link/` — installazione e uso in `plugins/c4d/README.md`. In breve:
pannello **Live link** → *File di export…* → *Attivo*; carica lo stesso file in un ImageTexture di Octane;
ogni modifica riscrive il file e il plugin preme Reload sui nodi che lo usano. Protocollo JSON-lines su
TCP 127.0.0.1:47820, con fallback sulla data di modifica del file se l'app non è collegata.

## Forme, angoli e gradienti

Le forme rettangolari (rettangolo, scrim, Texture, gradiente rettangolare) hanno **Angoli °**: il raggio
degli angoli. Con 0 la sfumatura è il prodotto delle sfumature dei due assi (la caduta di una softbox:
contorno rettangolare, angolo che sfuma senza "spina"); con un raggio > 0 la sfumatura segue un
rettangolo arrotondato, con raggio mai inferiore alla sfumatura così la banda resta liscia ovunque.

Il **Gradiente** ha tipo *Radiale* o *Lineare* (con *Angolo* di rotazione del gradiente dentro la forma,
indipendente dalla rotazione della luce), forma *Circolare* o *Rettangolare*, interpolazione lineare o
morbida, e un editor di **tacche**: click sulla barra aggiunge una tacca con il colore interpolato lì,
trascina per spostarla, tasto destro o Canc la toglie, ogni tacca ha il suo colore (anche gradienti
colorati: centro caldo, bordo freddo), *Inverti* le specchia. I colori delle tacche moltiplicano
intensità, Kelvin e tinta della luce; la misura fotometrica pesa il gradiente per luminanza.

Nell'app esportata il sorgente `.glsl` non c'è: il baker usa la risorsa importata e, in mancanza, il
sorgente incorporato in `bake/bake_glsl_source.gd`, generato da `tools/embed_shader.py` (lo smoke test
controlla che sia aggiornato). Se l'app esportata mostra tutto nero, lancia il `.console.exe` (Windows)
o l'eseguibile da terminale: il baker stampa da dove ha caricato lo shader e gli errori.

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

    /Applications/Godot.app/Contents/MacOS/Godot --path hdri_studio -s res://tools/ui_smoke.gd -- --fresh

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

    core/      RigLight, LightRig, ColorTemp, UndoStack, AppSettings, ThumbnailCache, ExrCodec
    addons/    hs_openexr — GDExtension OpenEXR (binari macOS/Windows; sorgenti in ../gdextension/)
    bake/      bake.glsl (compute shader), HdriBaker (RenderingDevice, texture RGBA32F)
    preview/   Preview3D (viewport, sfere, LightPaint), shader della sfera cromata e della mappa 2D
    ui/        ParamRow, LightListPanel, LightProperties, BackgroundPanel, ExportPanel, LiveLinkPanel, CatalogPanel, PresetPanel, MapView
    export/    HdriExport (EXR half/float32 con codec e metadati, .hdr, PNG di controllo)
    scenes/    main.tscn / main.gd — app
    livelink/  LiveLink (server TCP, JSON-lines)
    plugins/   c4d/hdri_studio_link (plugin Cinema 4D), blender/hdri_studio_link (add-on Blender)
    tools/     spike di Fase 0, verifica Blender, smoke test UI, link ed EXR, test del drag & drop
    splash.png boot splash (generato da ../tools/make_splash.py, Pillow + numpy)
    out/       output generati (ignorati da git)
