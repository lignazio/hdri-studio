---
tags:
  - hdri-studio
tipo: nota
area: progetto
---

# HDRI Studio — Piano

> [!success] Release 0.10.0 — 30 ottobre 2026
> Pubblicata https://github.com/lignazio/hdri-studio/releases/tag/v0.10.0 con `tools/release.sh`:
> plugin Houdini, interfaccia bilingue, revisione UX (UiStyle, scala dello schermo), finestra che si
> ricorda, rig nel `.hdr` leggibile da Three.js. Smoke test e self-test del build macOS OK; il build
> Windows non è stato aperto su un PC.

> [!success] Stato precedente: v2.1 — 17 settembre 2026 — OpenEXR dentro l'app: Fase 7 fatta
> GDExtension HsOpenEXR (C++, OpenEXR 3.4.9 statico, macOS universal + Windows x86_64 cross-compilata
> dal Mac): tutti i codec in scrittura e lettura, metadati scritti insieme ai pixel, niente più Blender
> per gli EXR. Resta la calibrazione della Power in Octane (Houdini: preset misurato e plugin fatti il 23/09).
> Verificata sul PC il 17/09: la DLL Windows si carica e l'EXR esce corretto. Release 0.9.1.

> [!success] Stato precedente: v2.0 — 16 settembre 2026 — export ACEScg: chiusi tutti i sospesi del piano tranne Houdini
> Icone di stato nella lista, export ACEScg. Dal piano iniziale resta solo Houdini (preset di
> orientamento e plugin), più la calibrazione della Power in Octane. Blender resta la dipendenza
> opzionale per i codec EXR: non esiste una GDExtension OpenEXR pronta (cercato su GitHub il 16/09);
> costruirla è una fase possibile.

> [!success] Stato precedente: v1.9 — 16 settembre 2026 — prima release per i tester
> Licenza MIT, versione 0.9.0 nell'app, `tools/release.sh` che esporta macOS e Windows, impacchetta
> con plugin e guida, verifica il build e pubblica su GitHub: prima release
> https://github.com/lignazio/hdri-studio/releases/tag/v0.9.0. Plugin C4D 1.0: ambiente e luci
> separate di default creati per ID misurati.

> [!success] Stato precedente: v1.8 — 16 settembre 2026 — .hdr, metadati EXR, lucchetto
> Export Radiance .hdr (RGBE sul GPU), metadati nell'EXR (chromaticities Rec.709 e rig JSON, letti
> anche da *Apri rig…*), luce bloccabile. Restano: ACEScg e Houdini, più i test in Octane della Fase 4.

> [!success] Stato precedente: v1.7 — 16 settembre 2026 — Fase 6 fatta
> Ruota tutto il set e duplica specchiata, esposimetro (E e EV100, validato: ambiente 1.0 → π),
> vista clipping, camera dal live link (C4D e Blender), materiali di prova per gioielleria.
> Cosa resta: [[#10. Cosa manca rispetto al piano iniziale]] (`.hdr`, metadati EXR, ACEScg, Houdini)
> e i test in Octane della Fase 4 (Power, verso/specchio della texture).

> [!success] Stato precedente: v1.6 — 15 settembre 2026 — rifiniture d'uso su tutte le feature esistenti
> Mappa con contorni e griglia, selezione dal riflesso, tastiera e multi-selezione, gelatine, scrim a
> disco, texture specchiabili, tacche con valore, sfocatura della base, sidecar dalla luce, rinomina
> preset, export che ricorda cartella e nome, live link adattivo, ultimo rig e autosave. Elenco
> completo nel README (*Rifiniture d'uso*). Prossimo: Fase 6, le cinque feature nuove concordate.

> [!success] Stato precedente: v1.5 — 15 settembre 2026 — angoli arrotondati e gradiente a tacche
> Sfumatura con angoli arrotondati (SDF) per le forme rettangolari; gradiente radiale/lineare,
> circolare/rettangolare, ruotabile, con tacche colorate in un editor dedicato (secondo buffer nel
> compute shader). Caricamento dello shader a tre vie con log per l'app esportata.

> [!success] Stato precedente: v1.4 — 15 settembre 2026 — preset, tag/preferiti/anteprima, codec EXR
> Libreria di preset con miniature; catalogo con preferiti, tag, filtri e anteprima al passaggio del
> mouse; export in ZIP/DWAA/DWAB/… via Blender in background e lettura degli EXR DWAA/B44/PXR24 del
> catalogo tramite conversione in cache. Cosa manca: [[#10. Cosa manca rispetto al piano iniziale]].

> [!success] Stato precedente: v1.3 — 15 settembre 2026 — Fase 5 (Blender) fatta e verificata in Cycles
> Add-on Blender: reload, LightPaint con `ray_cast`, luci separate come piani emissivi. Verifica
> fisica: piano emissivo vs stessa luce nell'HDRI → rapporto 1.002. Le cose che mancano rispetto al
> piano iniziale sono in [[#10. Cosa manca rispetto al piano iniziale]].

> [!success] Stato precedente: v1.2 — 15 settembre 2026 — Fase 4 in prova in C4D, Fase 5 (Blender) pianificata
> Luci separate: flag per luce, EXR planare singolo, messaggio `separate_lights`, plugin che clona la
> luce modello `HS_TEMPLATE`; posizione, dimensione e texture confermate automatiche, verso e
> specchio regolabili dal pannello Live link, Power da tarare ([[#5.4 Fase 4 — test in C4D]]).
> Prossimo su richiesta: [[#Fase 5 — Live link per Blender (pianificata il 15/09/2026, da fare su richiesta)]].
> In più: drag & drop dal catalogo, app standalone con preset macOS/Windows.

> [!success] Stato precedente: v1.0 — 15 settembre 2026 — le tre fasi del piano sono chiuse
> Verificato sul PC con Cinema 4D + Octane: live link e **LightPaint dal viewport**. Nell'app: luci
> parametriche (sei forme, scrim e Texture comprese), catalogo per sottocartelle, modalità fotometrica
> validata contro Cycles, fusione Normale, undo, export con preset per software, modello GLB nel
> preview. Da qui in poi: rifiniture d'uso e le voci aperte in [[#Fase 3 — LightPaint e maturità]].
> Progetto in `hdri_studio/`, repository privato: https://github.com/lignazio/hdri-studio. Ambiente rilevato sulla macchina: macOS 15.7 su M1 Pro,
> Godot 4.7.1, Blender 5.1.1, Cinema 4D 2025/2026, Houdini 20.0 e 22.0 (il link provato su 22.0.429).

## 1. Cosa stiamo costruendo

HDR Light Studio, ridotto all'osso, è **un compositor che lavora sulla sfera**: ogni luce è una forma
2D (rettangolo, ellisse, anello, gradiente) con un valore di radianza lineare in float, le forme vengono
sommate su una tela equirettangolare, e la tela viene mostrata riflessa su una sfera cromata e diffusa.
Tutto il resto — LightPaint, live link, preset, texture nelle luci — è costruito sopra questo nucleo.

### Fase 1 (questo piano)

- Luci parametriche posizionate in coordinate angolari sulla sfera (azimut, elevazione, dimensione
  angolare), non in pixel. Cinque forme: rettangolo, ellisse, anello, gradiente e **scrim** (sorgente
  dietro un telo diffusore, con hotspot e caduta fisicamente derivati).
- Sfondo di partenza: gradiente zenit/orizzonte/nadir **oppure** un'HDRI esistente (EXR/HDR) da
  "aumentare" con le luci parametriche — è il caso d'uso principale: luce da studio.
- Preview in tempo reale: sfera cromata + sfera diffusa + sfera glossy, illuminate dall'HDRI baked.
- Bake su GPU in float32, esportazione **EXR lineare** (half o float) e Radiance `.hdr`.
- Workflow lineare da capo a fondo: i parametri diventano radianza, la radianza diventa pixel, il tone
  mapping esiste **solo** nella finestra di preview e non tocca mai i dati esportati.
- Salvataggio/caricamento del rig di luci (JSON).

### Fase 2 (dopo)

- Live link con un software 3D: l'HDRI si aggiorna nel dome light mentre sposti le luci.
- LightPaint: clicchi un punto sul modello nel software 3D, la luce si sposta dove serve per produrre
  il riflesso in quel punto.

### Fuori scope, per ora

Rendering di scene, gestione di geometria complessa nel preview, HDRI fotografiche come luci (solo come
sfondo di base), modalità fotometrica con unità reali (arriva in Fase 3).

## 2. Principi per HDRI fisicamente corrette

Questi sono i vincoli che rendono l'output *usabile come luce*, non solo bello da vedere.

> [!important] Il valore del pixel è radianza
> Ogni pixel dell'HDRI contiene radianza lineare (W·sr⁻¹·m⁻² in unità arbitrarie ma coerenti). Niente
> gamma, niente tone mapping, niente clamp. Un renderer che campiona la mappa fa già il conto del peso
> `sin(θ)` dell'equirettangolare: **non va applicata nessuna correzione ai poli** nel bake.

1. **Luci definite sulla sfera, non sulla tela.** Una luce è una regione angolare: una softbox di 20°×30°
   resta 20°×30° sia all'orizzonte sia vicino allo zenit. Se la disegnassimo in spazio UV si deformerebbe
   ai poli e cambierebbe angolo solido con l'elevazione. Il test di appartenenza si fa nel *frame locale*
   della luce (forward/right/up), come descritto in [[#4.4 Matematica del bake]].
2. **Intensità = radianza.** In Fase 1 il parametro è un valore lineare più un offset in stop
   (`L = base · 2^EV`). In Fase 3 aggiungiamo la modalità fotometrica: si specifica l'illuminamento al
   centro della sfera e la radianza viene derivata da `E = L · Ω_proj`, così una luce grande e una piccola
   con lo stesso valore "lux" danno la stessa esposizione.
3. **Colore.** Temperatura in Kelvin convertita via CIE 1931 → XYZ → primari Rec.709 lineari, più una tinta
   RGB moltiplicativa. Spazio di output: **lineare Rec.709/sRGB** (è ciò che Cycles, Redshift e Karma
   assumono per un'HDRI senza metadati), con l'attributo `chromaticities` scritto nell'EXR. ACEScg come
   opzione in Fase 3.
4. **Antialiasing dei bordi.** Bordi soft analitici (larghezza in gradi, `smoothstep`) più supersampling
   2×2 all'export. Un bordo duro aliasato si vede nei riflessi speculari.
5. **Precisione.** Bake in float32. Export EXR half (default, con compressione ZIP) o float32 a scelta.
   Attenzione: half satura a 65504 — una luce "sole" può superarlo, quindi l'export passa in automatico
   a float32 se il massimo del bake lo richiede.
6. **Orientamento.** Ogni software mappa il centro dell'equirettangolare su un asse diverso (Blender
   guarda verso −X con Z in alto; C4D e Houdini hanno Y in alto e convenzioni proprie). Definiamo una
   convenzione interna e un **offset di export per software di destinazione**, calibrato empiricamente
   in Fase 0 con un'HDRI di taratura a marker colorati (+X rosso, +Y verde, +Z blu).

## 3. Scelta della piattaforma

Criteri: viewport PBR per il preview, widget UI pronti, bake GPU in float32, scrittura EXR, accesso a
filesystem e socket per il live link, quanto ti è familiare, quanto è facile impacchettarlo.

| | Godot 4.7 | Three.js + Tauri/Electron | Python (Qt + numpy/OIIO) | Nativo dentro Houdini (COPs/Copernicus) |
|---|---|---|---|---|
| Preview PBR con riflessi | Sì, `PanoramaSkyMaterial` aggiorna i riflessi in tempo reale | Sì, `PMREMGenerator` + `scene.environment` | Da costruire da zero (moderngl) | Sì, ma solo dentro Houdini |
| UI | Control nodes nativi, docking, theming | HTML/CSS — massima libertà, più lavoro | Qt, solido ma verboso | Parametri Houdini |
| Bake float32 su GPU | Compute shader via `RenderingDevice` | Fragment/compute su float render target | numpy su CPU (lento a 8k) o CuPy | Nativo |
| Export EXR | `Image.save_exr` (TinyEXR, in 4.7 compilato anche nei template di export — verificato nel sorgente, da confermare con un test) | `EXRExporter` di three (half/float, ZIP) | OpenEXR/OIIO, il meglio | Nativo |
| Live link | `TCPServer`/WebSocket nativi | Il browser è solo client: serve Tauri o un relay Node | Trivial | Non serve |
| Familiarità | GDScript nuovo ma banale, shader ≈ GLSL | Alta (Three.js, shader) | Media | Alta per Houdini |
| Packaging | Export nativo macOS/Win | Tauri: leggero; Electron: pesante | PyInstaller, scomodo | Zero: è un HDA |

**Raccomandazione: Godot 4.7.** Tre motivi concreti:

- È l'unico dei quattro che dà *contemporaneamente* viewport PBR, UI, compute shader, socket server e
  file system senza pezzi da incollare. Per un tool desktop che deve scrivere file e parlare con un
  altro programma, questo pesa più della familiarità con Three.js.
- Il nucleo — il bake — è un compute shader di 100 righe e la matematica è identica ovunque. Il
  vantaggio di conoscere Three.js si esaurisce presto; il costo di dover aggiungere Tauri per il live
  link resta.
- Il preview con riflessi è gratis: la texture baked va in un `PanoramaSkyMaterial` tramite
  `Texture2DRD` (zero copie dalla GPU) e le sfere si aggiornano nello stesso frame.

**Piano B: Three.js.** Se preferisci restare nel tuo ecosistema, la Fase 1 è fattibile *senza* wrapper:
la File System Access API di Chrome scrive l'EXR in una cartella scelta. Il live link in Fase 2
richiederebbe però Tauri o un relay Node di ~40 righe. Nessun'altra differenza sostanziale.

**Scorciatoia da considerare: Houdini Copernicus.** Se il tuo lavoro è Houdini-first, un HDA che genera
l'HDRI in COPs e la collega a un dome light Karma/Redshift copre Fase 1 e Fase 2 in pochi giorni, senza
app esterna. Non scala a C4D e Blender. Lo cito perché è la strada più breve a un risultato utile,
non perché sia la scelta consigliata per un tool standalone.

## 4. Architettura (Godot)

### 4.1 Moduli

```
hdri_studio/
├── core/        modello dati: LightRig, RigLight (Resource), serializzazione JSON
├── bake/        compute shader GLSL + BakeController (dirty flag, debounce, risoluzione)
├── preview/     WorldEnvironment + PanoramaSkyMaterial, sfere di prova, camera orbit, tonemap di sola visualizzazione
├── ui/          lista luci, pannello proprietà, mappa equirettangolare 2D con maniglie trascinabili
├── export/      EXR (save_exr), Radiance .hdr (writer nostro), metadati, preset di orientamento per software
├── livelink/    TCPServer, protocollo JSON-lines (Fase 2)
└── plugins/     c4d/, blender/, houdini/ — script Python lato software 3D (Fase 2)
```

### 4.2 Flusso dati

```
parametro cambia → rig.dirty = true
  → BakeController (max 1 bake per frame) → compute dispatch → texture RGBA32F
      → preview: la stessa texture è già lo sky (Texture2DRD)
      → export/autosave (debounce ~300 ms): texture → Image RGBAF → save_exr
          → livelink: "hdri_updated" + path al plugin → plugin ricarica la bitmap del dome light
```

A 4096×2048 sono 8 M pixel × N luci: su M1 Pro è ben sotto il millisecondo per luce. Il preview è
interattivo anche a 8k; è l'export su disco a dettare il ritmo del live link, non il bake.

### 4.3 Modello di una luce

| Parametro | Tipo | Note |
|---|---|---|
| `name`, `enabled`, `solo` | | |
| `shape` | rect · ellipse · ring · gradient · scrim | Fase 1. `texture` in Fase 3 |
| `azimuth`, `elevation`, `roll` | gradi | Posizione e rotazione sulla sfera |
| `width`, `height` | gradi | Dimensione angolare. Per `ring`: raggio interno/esterno |
| `softness` | gradi | Larghezza del bordo sfumato |
| `falloff` | curva | Lineare, smoothstep, gaussiana |
| `scrim.offset` | (x, y) in −1…1 | Posizione della sorgente dietro il telo, relativa alla sua metà larghezza/altezza |
| `scrim.depth` | float | Distanza della sorgente dal telo, in unità di metà larghezza del telo. Piccolo = hotspot duro, grande = telo quasi uniforme |
| `scrim.source_size` | float | Raggio della sorgente (0 = puntiforme). Sfuma l'hotspot |
| `intensity`, `ev` | float | `L = intensity · 2^ev` |
| `kelvin`, `tint` | K, RGB | Tinta moltiplicativa su bianco a `kelvin` |
| `blend` | add · max · multiply | `add` è il default fisico; `multiply` serve per maschere/bandiere nere |

Sfondo (Fase 1, un layer base sotto le luci): nero · colore uniforme · gradiente zenit/orizzonte/nadir ·
**HDRI importata** (EXR via `Image.load_exr_from_buffer`, Radiance `.hdr` via `Image.load`), con
rotazione orizzontale, esposizione in EV e opzionale flip. Il layer base è campionato nel compute shader
come texture, quindi la risoluzione della base non deve coincidere con quella del bake.

### 4.4 Matematica del bake

Per ogni pixel `(u, v)` della tela equirettangolare, la direzione sulla sfera unitaria:

```
φ = (u − 0.5) · 2π          θ = (0.5 − v) · π
d = ( −cos θ · sin φ,  sin θ,  cos θ · cos φ )    // convenzione interna: Y in alto, centro = +Z, u = 0,25 = +X (come Godot)
```

Per ogni luce si costruisce il frame ortonormale `F` (forward, da azimut/elevazione), `R`, `U` (con il
roll). Il punto viene proiettato in coordinate angolari locali:

```
se d·F ≤ 0 → fuori (la luce è sull'emisfero opposto)
ax = atan2(d·R, d·F)        ay = atan2(d·U, d·F)          // in radianti, tangenti nel frame della luce
rect:     inside = |ax| < w/2  &&  |ay| < h/2
ellipse:  inside = (ax/(w/2))² + (ay/(h/2))² < 1
ring:     r_in < sqrt(ax²+ay²) < r_out
gradient: peso = falloff(dist / raggio)
scrim:    vedi sotto
bordo:    peso = smoothstep(0, softness, distanza_dal_bordo)
L_pixel += peso · intensità · 2^ev · colore(kelvin) · tint
```

**Scrim.** Il telo è un rettangolo `w×h` come `rect`; la luminosità sul telo non è uniforme ma è
l'irradianza prodotta da una sorgente posta dietro, a distanza `depth`, spostata di `offset`. Per una
sorgente puntiforme di intensità `I` che illumina un piano (legge del coseno + inverso del quadrato):

```
p  = (ax / (w/2), ay / (h/2))                 // coordinate normalizzate sul telo, −1…1
q  = p − offset                                // vettore dal piede della sorgente al punto
E  = I · depth / (|q|² + depth²)^(3/2)         // irradianza sul telo: hotspot con caduta fisica
L  = E · τ / π                                 // il telo è un diffusore lambertiano di trasmittanza τ
```

Con `source_size > 0` la sorgente diventa un disco: l'integrale non è chiuso, ma una convoluzione
gaussiana equivalente (σ ∝ source_size / depth) è indistinguibile a occhio e resta monotona.
L'intensità è normalizzata in modo che il picco sul telo valga `intensity · 2^ev`, così i cursori
si comportano come per le altre forme. Il risultato è il classico hotspot morbido che scivola verso i
bordi: è il motivo per cui una softbox vera non si vede mai uniforme nei riflessi.

Con `softness = 0` e supersampling 2×2 il bordo è comunque pulito. Le luci sono un buffer SSBO di
struct; il compute shader fa un loop sulle luci per pixel, che a decine di luci è più che sufficiente.

### 4.5 Export

- **EXR**: `Image.save_exr` con formato `RGBAF` (float32) o `RGBAH` (half). Metadati: chromaticities
  Rec.709, `worldToCamera` non serve, un attributo custom `hdri_studio:rig` con il JSON del rig, così
  l'HDRI porta con sé i propri parametri.
- **Radiance .hdr**: writer RGBE nostro (~60 righe). Precisione inferiore (mantissa 8 bit con esponente
  condiviso), lo teniamo per compatibilità e come fallback se TinyEXR mancasse nei template di export.
- **Orientamento**: preset per Blender / C4D / Houdini che applica uno shift orizzontale e, se serve, un
  flip, prima della scrittura. Calibrati in Fase 0.

### 4.6 Preview

- `WorldEnvironment` con `PanoramaSkyMaterial` che punta alla texture del bake.
- Tre sfere: cromata (roughness 0), glossy (roughness 0.3), diffusa bianca (albedo 0.8). Opzionale in
  Fase 2: caricare un GLB (un anello, una montatura) per vedere i riflessi sul pezzo vero.
- Esposizione e tone mapping (AgX o ACES) **solo** su questo viewport. Un toggle "lineare/clamp" mostra
  i dati nudi per verificare che il bake sia quello che ci si aspetta.
- Manipolazione: trascinando una luce sulla mappa 2D o direttamente sulla sfera 3D. Nel 3D il drag è
  un raggio dalla camera intersecato con la sfera unitaria → nuova direzione → azimut/elevazione. È lo
  stesso raggio che userà LightPaint in Fase 3, con il riflesso `R = reflect(V, N)` al posto del punto.

### 4.7 Live link (Fase 2)

Protocollo JSON-lines su TCP locale, un messaggio per riga:

```
app → plugin:  {"type":"hdri_updated","path":"/…/rig.exr","orientation":"c4d"}
plugin → app:  {"type":"hello","host":"c4d","version":"2026"}
plugin → app:  {"type":"lightpaint","point":[x,y,z],"normal":[x,y,z],"camera":[x,y,z]}   // Fase 3
```

Lato software 3D:

- **Cinema 4D + Octane** (primo target): plugin `MessageData` con `GetTimer` (polling ogni 200 ms) nel
  thread principale, C4D non ama i thread Python. L'HDRI in Octane sta in un oggetto *Octane
  Environment* (o nel tag Environment) → shader *ImageTexture*. **Misurato (15/09)**: Octane tiene una
  cache delle texture e né sovrascrivere il file, né riassegnarlo, né riavviare il Live Viewer la
  invalidano; **solo il pulsante Reload** dell'ImageTexture funziona. Il plugin quindi: rileva il
  cambiamento (socket o `mtime`), trova gli ImageTexture che puntano al file esportato, e preme Reload
  con `node.Message(c4d.MSG_DESCRIPTION_COMMAND, {"id": DescID(pulsante)})`, poi `EventAdd()`.
- **Cinema 4D + Redshift** (dopo): stessa struttura, il dome light rilegge il bitmap shader con
  `EventAdd()`.
- **Blender**: add-on con `bpy.app.timers`, `image.reload()` sull'immagine dell'Environment Texture.
- **Houdini**: timer Qt via `hdefereval`, poi `hou.hscript("texcache -r")` per invalidare la cache
  texture, altrimenti Karma non rilegge il file.

Il fallback senza socket è banale e vale la pena averlo comunque: i plugin guardano la `mtime` del file.

## 5. Fasi e stime

### Fase 0 — Spike tecnico (2–3 giorni)

Obiettivo: dimostrare la catena completa prima di costruire UI.

1. Progetto Godot vuoto, compute shader che scrive un gradiente e una luce rettangolare hard-coded su
   texture RGBA32F, `save_exr` in float e half.
2. HDRI di taratura con marker colorati agli assi; caricarla in C4D, Blender e Houdini e annotare gli
   offset di orientamento.
3. Furnace test (vedi [[#6. Validazione fisica]]) in Blender.
4. Prova manuale in C4D: aprire l'EXR in un Octane ImageTexture, sovrascriverlo, e trovare il modo
   più affidabile di forzare il reload dal Python di C4D. È il prerequisito della Fase 2.
5. (Facoltativo, tool personale) Confermare che `save_exr` funziona anche in un build esportato.

Criterio di uscita: un EXR generato da Godot che, caricato nel software 3D, illumina una sfera diffusa con
il valore atteso e con la luce nella direzione attesa.

### 5.1 Fase 0 — stato e test C4D/Octane

| Passo | Esito |
|---|---|
| Compute shader + texture RGBA32F + `save_exr` half e float32 | **Fatto.** Bake 4k×2k in 40–85 ms su M1 Pro, EXR in ~2,2 s (è la compressione ZIP di TinyEXR, non il bake) |
| HDRI di taratura con marker sugli assi | **Fatto.** `out/calibration.exr`: +X rosso, −X rosso scuro, +Y verde, −Y verde scuro, +Z blu, −Z blu scuro, punto bianco ad az +25° / el +12° |
| Furnace test in Cycles | **Passato.** Ambiente 1.0 → sfera diffusa bianca = 0.998 |
| Singola luce: EXR vs integrale vs Cycles | **Passato.** E/π = 0.5632 (EXR) = 0.5632 (integrale indipendente) ≈ 0.5691 (Cycles, +1%, rumore) |
| Orientamento Blender | **Calibrato.** Rotazione pura (det +1): centro immagine = +X, u = 0,25 = +Y, alto = +Z. Nessun offset, nessun flip |
| Viewer: sky + sfera cromata esatta + glossy + diffusa + mappa 2D | **Fatto.** `scenes/main.tscn` |
| Orientamento C4D | **Misurato il punto bianco.** In **Octane** appare a destra come nel preview → nessun flip (preset "Cinema 4D + Octane", default). In **C4D nativo** appare a sinistra → specchio (preset "Cinema 4D nativo"). Da confermare quale asse è al centro |
| Reload in Octane | **Misurato.** Sovrascrivere il file non basta; riassegnarlo non basta; riavviare il Live Viewer non basta. **Solo il pulsante Reload dell'ImageTexture** rilegge la texture. Il plugin lo premerà via `MSG_DESCRIPTION_COMMAND`; la sonda `plugins/c4d/octane_reload_probe.py` trova l'ID del pulsante |

> [!todo] Test da fare in Cinema 4D + Octane
> 1. **Orientamento.** Crea un Octane Environment (o tag Environment sulla Sky), ImageTexture →
>    `hdri_studio/out/calibration.exr`, gamma 1, colorspace lineare. Aggiungi una sfera con materiale
>    specular puro (o guarda direttamente l'ambiente nel Live Viewer). Annota: quale colore appare
>    guardando lungo **+X, −X, +Y, −Y, +Z, −Z** di C4D, e se il **punto bianco** sta a destra o a sinistra
>    del disco blu guardandolo dal centro. Con sei colori e il punto bianco ricavo la matrice (e
>    l'eventuale specchio, visto che C4D è left-handed).
> 2. **Reload.** Con `out/studio.exr` caricata nello stesso ImageTexture, lancia da terminale
>    lo spike (`README.md`) che la riscrive, e guarda se il Live Viewer si aggiorna da solo, se serve
>    premere Reload sulla texture, o se serve riassegnare il file. Se hai un attimo, prova anche dallo
>    Script Manager: `c4d.EventAdd()` dopo aver toccato il parametro filename dello shader.

### Fase 1 — MVP — fatta il 15/09/2026

- [x] Modello dati e serializzazione del rig (JSON).
- [x] Compute shader con le cinque forme (scrim inclusa), bordi soft, Kelvin, blend add/max/multiply.
- [x] Layer base: gradiente e HDRI importata (rotazione, esposizione, specchio).
- [x] Preview 2048×1024 interattiva, export 2k/4k/8k con supersampling 2×2.
- [x] Preview con le tre sfere (cromata esatta via shader dedicato), orbit camera, tonemap AgX di sola visualizzazione.
- [x] UI: lista luci con add/duplicate/delete/solo, pannello proprietà, mappa 2D con maniglie.
- [x] **LightPaint locale**: Shift + drag su una sfera del preview sposta la luce dove serve per il riflesso. Era previsto in Fase 3, ma sul preview costa dieci righe.
- [x] Export EXR half/float32 con preset di orientamento e rotazione extra.
- [x] Undo/redo a snapshot.
- [ ] Radiance `.hdr` (rimandato a Fase 2, poco utile finché non serve la compatibilità).

Da rifinire quando lo usi: default delle nuove luci, range degli slider, tema.

### Fase 2 — Live link — costruita il 15/09/2026

- [x] Server TCP nell'app (`livelink/live_link.gd`, JSON-lines, porta 47820), pannello Live link.
- [x] Export automatico 300 ms dopo l'ultima modifica, alla risoluzione live (1k/2k/4k), scrittura
      atomica (tmp + rename) così il plugin non legge mai un file a metà.
- [x] Plugin Cinema 4D (`plugins/c4d/hdri_studio_link/`): `MessageData` con timer a 200 ms, client
      TCP non bloccante con riconnessione, preme i pulsanti *Reload* dei nodi che usano il file;
      fallback sulla data di modifica ogni secondo; comando "HDRI Studio: reload textures" (in italiano fino al 23/09/2026).
- [x] Ricezione del messaggio `lightpaint` (Fase 3 lato app già pronta: conversione C4D → interna).
- [x] Caricamento GLB nel preview (16/09: pannello *Modello nel preview*, materiale originale/cromato/glossy/diffuso, collisioni trimesh per il LightPaint locale).
- [ ] Radiance `.hdr` (8k già possibile).

### 5.2 Fase 2 — stato e test in C4D

Sul Mac: smoke test con un client Python che simula il plugin → hello, `hdri_updated` all'aggancio,
`hdri_updated` dopo una modifica, `lightpaint` di ritorno che sposta la luce. Tutto verde.

> [!success] Verificato sul PC il 15/09/2026: il Live Viewer di Octane si aggiorna da solo a ogni modifica.

> [!todo] Procedura di installazione (per riferimento)
> 1. `git pull`, poi installa il plugin: Edit → Preferences → Plugins → *Add Folder…* →
>    `hdri_studio/plugins/c4d` → riavvia C4D. Nella console: `[hdri-studio] plugin caricato`.
> 2. Nell'app: pannello **Live link** → *File di export…* (un `.exr` nella cartella `tex/` del progetto
>    C4D) → *Attivo*. Lo stato deve dire "1 client (c4d 2026…)".
> 3. Carica quel file nell'ImageTexture di Octane, poi sposta una luce nell'app: il Live Viewer deve
>    aggiornarsi da solo entro un secondo. Nella console C4D: `nome.exr → 1 nodi ricaricati`.
> 4. Se non aggiorna: dimmi cosa stampa la console, e se il fallback (chiudere l'app e sovrascrivere
>    il file con un export manuale) ricarica.

### Fase 3 — LightPaint e maturità

- [x] LightPaint da C4D: tool `HDRI Studio LightPaint` (ToolData) nel plugin. Click o drag nel
      viewport → raggio dal pixel (`bd.SW`) → `GeRayCollider` su tutte le mesh (cache dei generatori
      comprese) → punto, normale di faccia e direzione di vista → messaggio `lightpaint` → l'app
      calcola `reflect(V, N)` (con X invertita per il sistema left-handed) e sposta la luce selezionata.
      Marker giallo nel viewport sull'ultimo punto colpito. **Verificato sul PC il 15/09/2026.**
- [x] **Luci Texture** (15/09): sesta forma, immagine EXR/HDR lineare mappata sul rettangolo angolare
      (texture array 2048×1024 × 12 strati RGBA16F nel compute shader, cache LRU per percorso).
      Intensità/EV/Kelvin/tinta moltiplicano l'immagine, la sfumatura fa da maschera.
- [x] **Catalogo** (15/09): tab nella colonna sinistra, cartella locale ricorsiva salvata nelle
      preferenze, miniature generate in un thread (esposizione automatica) e cache PNG in
      `user://thumbs/`, filtro per nome, click → luce nel rig. Il rig salva solo il percorso del file;
      sidecar `nome.json` opzionale con i default (dimensione, intensità, Kelvin…).
- [x] Normali interpolate (Phong, baricentriche nel triangolo colpito) nel picking C4D; fallback alla
      normale di faccia se l'oggetto non ha Phong.
- [x] LightPaint che crea una luce nuova se nessuna è selezionata.
- [x] Catalogo per sottocartelle: intestazioni per gruppo e menu a tendina di filtro.
- [x] **Modalità fotometrica**: E al centro → `L = E / K`, con K = ∫ w·cosθ dω misurato sul GPU nel
      frame locale della luce (griglia 256², coordinate angolari, jacobiano esatto), cache sui
      parametri di forma. Validato: rect 30°×20° → K = 0.1769 sr, lo stesso valore ricavato da Cycles
      in Fase 0.
- [x] Fusione **Normale** (copre in ordine di elenco) e riordino ▲▼ delle luci.
- [x] Colonne e preview/mappa ridimensionabili (split container).
- [x] ID dei plugin C4D portati a valori alti dopo la collisione di 1065932 con `C4d_objects`.
- [x] Catalogo: drag & drop delle miniature sulla mappa (la luce nasce lì) e sul preview 3D (nasce
      sul riflesso del punto colpito).
- [x] App standalone: preset di export macOS/Windows, shader caricato dalla risorsa importata, self-test
      da riga di comando; build provato su macOS (bake + EXR nell'app esportata).
- [ ] Catalogo: anteprima al passaggio del mouse, tag/preferiti.
- [ ] ACEScg in export.

### Fase 4 — Luci separate in Cinema 4D (pianificata il 15/09/2026)

Alcune luci del rig non finiscono nell'HDRI ma diventano **luci vere nella scena**: ognuna esportata
come EXR singolo e ricreata in C4D come area light con quella texture, nella stessa direzione angolare,
a una distanza dal centro scelta con uno slider. Il motivo: una luce vicina al soggetto dà ombre e
riflessi con la parallasse giusta, cosa che un'HDRI all'infinito non può fare; il resto del set resta
nell'HDRI.

Coerenza fisica: un'area light di radianza `L` posta a distanza `D` con dimensione fisica
`w = 2·D·tan(width/2)`, `h = 2·D·tan(height/2)` sottende lo stesso angolo solido della luce nell'HDRI
vista dal centro, quindi produce lo stesso illuminamento lì; allontanandosi dal centro compare la
parallasse, che è esattamente ciò che si vuole.

Passi:

1. [x] **Flag per luce** "separata" con slider *Distanza (cm)*: esclusa dal bake dell'HDRI esportata
   (nel preview resta visibile), all'export scrive `<rig>_<luce>.exr` con una **proiezione planare**:
   i pixel campionano uniformemente in tan-space, cioè esattamente la texture di un rettangolo piano a
   distanza D che sottende (w × h). Lineare, radianza già applicata, 1024 px sul lato lungo.
2. [x] **Messaggio live link** `separate_lights`: per luce `forward/right/up` già nelle coordinate del
   software (X invertita per Octane; per "C4D nativo" no, e il plugin specchia l'asse X della luce),
   distanza, dimensione fisica, percorso. Inviato con ogni `hdri_updated` e all'aggancio del plugin.
3. [x] **Plugin C4D**: null `HDRI Studio Lights`; per ogni voce clona la luce modello `HS_TEMPLATE`
   (scelta dell'utente: Octane Area Light con ImageTexture), matrice `(F·D, R, U, F)` con −Z verso il
   centro, `LIGHT_AREADETAILS_SIZEX/Y` alla dimensione fisica, primo slot immagine → l'EXR + Reload;
   rimuove le luci non più in lista. Costante `LIGHT_EMITS_ALONG_Z` se Octane emette lungo +Z.
4. [ ] **Calibrazione dell'intensità in Octane**: nella luce modello *Surface brightness* attivo
   (emissione per unità di area = radianza) e Power = 1; il furnace test (luce separata vs stessa luce
   nell'HDRI → stesso pixel su una sfera diffusa) dà il fattore da mettere nel template. Va fatta sul PC.
   Verso di emissione misurato il 15/09: **+Z** (`LIGHT_EMITS_ALONG_Z = +1`); posizione, dimensione e
   texture confermate automatiche. Specchio della texture da confermare con una luce asimmetrica.
5. [ ] Opzioni: luce invisibile alla camera, esportare tutte le luci separate in blocco, verso della
   texture se risultasse specchiata.

### Fase 5 — Live link per Blender — fatta il 15/09/2026

Costruita e verificata headless sul Mac (Blender 5.1): collegamento, `hdri_updated` → `reload()`,
`separate_lights` → piano emissivo a 1.5 m lungo +X con la faccia verso il centro e larghezza 1.092 m,
LightPaint da Blender → az 0 / el 0 nell'app. **Verifica fisica in Cycles**: stessa luce nell'HDRI
(0.5621) e come piano emissivo creato dall'add-on (0.5630) → rapporto 1.002. Scelta diversa da C4D: i
piani emissivi con Emission strength 1 hanno la semantica della radianza, quindi niente calibrazione.
Piano originale:

Stesso protocollo di C4D (TCP 47820, JSON-lines, `hdri_updated` / `separate_lights` / `lightpaint`),
un add-on Python al posto del plugin. Rispetto a C4D è più semplice su ogni fronte: Blender ricarica
un'immagine con `image.reload()`, ha timer nel thread principale (`bpy.app.timers`), il picking nel
viewport è `scene.ray_cast` con normali interpolate gratis, e le area light hanno texture e dimensione
fisica native (`light.size`, `size_y`, nodi emission con Image Texture). L'orientamento è già misurato
in Fase 0: rotazione pura, nessuno specchio (centro immagine = +X, alto = +Z).

Passi:

1. **Add-on** `plugins/blender/hdri_studio_link/` (`__init__.py` + `link_core.py` riusato tale e
   quale): pannello nella sidebar N (*HDRI Studio*): stato del collegamento, pulsante *Ricarica*,
   operatore modale *LightPaint* (click nel viewport → `ray_cast` → `lightpaint` con punto, normale e
   direzione di vista, host `blender`: nessuna inversione di assi).
2. **Reload**: a `hdri_updated`, per ogni `bpy.data.images` il cui filepath coincide → `reload()`;
   fallback su mtime come in C4D. Nessun pulsante da premere: Cycles ed EEVEE rileggono da soli.
3. **Luci separate**: collezione `HDRI Studio Lights` con una area light per voce: `light.shape =
   'RECTANGLE'`, `size`/`size_y` = dimensione fisica, matrice da `forward/right/up` (Blender è
   right-handed: le basi arrivano senza inversione, come per Godot), nodi `Emission` con l'EXR planare
   in `Image Texture` e `Strength` = 1 (la texture porta la radianza; in Blender la strength di una
   area light è già per unità di area, quindi il fattore dovrebbe essere 1 — da confermare con il
   furnace test). Le area light emettono lungo −Z: matrice `(F·D, R, U, F)`.
4. **Conversione**: nel messaggio `separate_lights` l'app manda le basi nelle coordinate del target
   scelto nel pannello Export; con *Godot / Blender* nessuna inversione. Blender è Z-up: il plugin
   ruota le basi con la matrice misurata in Fase 0 (interno → Blender: X→Y, Y→Z, Z→X).
5. Test: `link_smoke.gd` + un client Blender headless (`blender -b --python`) che si collega, riceve
   `hdri_updated`, ricarica e verifica il pixel; furnace test per la strength.

### Fase 6 — Feature nuove concordate — fatta il 16/09/2026

1. [x] **Ruota tutto il set** (slider nel pannello *Set*, destructivo sugli azimut, torna a 0) e
   **⇋ Duplica specchiata** (azimut, rotazione, angolo del gradiente, offset scrim, specchio texture).
2. [x] **Esposimetro**: copia CPU 256×128 del bake, `E = Σ L·max(d·n,0)·dω`, EV100 = log2(E/2.5),
   normale verso la camera / l'alto / az-el. Validato: ambiente 1.0 → E = π per qualunque normale.
3. [x] **Clipping**: soglia con falsi colori (magenta) sulla mappa e sui materiali a riflessi esatti.
4. [x] **Camera dal live link**: messaggio `camera` (forward, up, fov orizzontale) da C4D (camera
   della vista attiva) e Blender (vista 3D o camera di scena), mandato solo quando cambia; il preview
   usa direzione, alto e FOV alla distanza corrente. X invertita per C4D come per il LightPaint.
5. [x] **Materiali di prova**: metalli lucidi con lo shader a riflessi esatti tinto con F0 (oro
   1.0/0.71/0.29, oro bianco, argento, platino, rame), spazzolato anisotropo, vetro con rifrazione;
   per il modello o per la sfera centrale.

### Fase 7 — OpenEXR dentro l'app (GDExtension) — fatta il 17/09/2026

Obiettivo: esportare in ogni codec EXR e leggere DWAA/DWAB/B44/PXR24 senza dipendere da Blender.
Non esisteva una GDExtension OpenEXR pronta: costruita in casa, ~350 righe di C++.

1. [x] **Sorgenti** in `gdextension/` (`src/hs_openexr.cpp`, `register_types.cpp`, `CMakeLists.txt`,
   toolchain mingw). Classe `HsOpenEXR` (RefCounted, metodi statici): `save(image, path, codec, half,
   attributes, dwa_level)`, `load(path) → Image RGBAF`, `info(path)`, `codecs()`, `version()`.
   Stream `Imf::OStream`/`IStream` sopra `FileAccess`, così i percorsi `user://` e Unicode li gestisce
   Godot. Si scrivono solo R, G, B; OpenEXR non converte i tipi in scrittura, quindi l'immagine viene
   convertita in `RGBH`/`RGBF` prima. In lettura: R/G/B piatti, oppure il primo layer (`beauty.R`),
   oppure `Y` monocromatico; canali mancanti riempiti; tiled e prima parte dei multipart gestiti da
   `InputFile`. Thread pool = core della macchina.
2. [x] **Build**: `tools/build_gdextension.sh [macos|windows]`. Due progetti CMake in sequenza:
   OpenEXR 3.4.9 statico (Imath, libdeflate e OpenJPH interni; il config esportato cita `openjph`
   senza installarlo → copiato nel prefix e dichiarato come target importato) e poi l'estensione con
   godot-cpp v10 (master, commit fissato, `api_version 4.7`) via FetchContent. macOS: universal
   arm64+x86_64, deployment 11.0, 5,3 MB. Windows: `brew install mingw-w64` (GCC 16, thread posix),
   `-static` per libstdc++/winpthread, dipende solo da KERNEL32 e UCRT, 3,9 MB. Binari committati in
   `hdri_studio/addons/hs_openexr/bin/`; il `.gdextension` li dichiara per `macos` e `windows.x86_64`.
3. [x] **Integrazione**: `ExrCodec` (ex `ExrConvert`) chiama l'estensione via
   `ClassDB.class_call_static`, così se il binario manca il codice resta valido e si torna a TinyEXR
   (solo PIZ, metadati iniettati dopo). `HdriExport.save_exr(img, path, half, codec, rig_json, acescg)`
   scrive pixel e metadati in una volta; il fallback half → float32 sopra 65504 resta. `export_to`
   accetta `codec` nelle opzioni; il live link usa sempre PIZ. `HdriBaker.load_linear_image` legge
   qualunque EXR con l'estensione. Rimossi: riconversione in background, cache PIZ, ricerca e scelta
   dell'eseguibile di Blender, `blender_path`.
4. [x] **Test**: `tools/exr_smoke.gd` (10 codec × half/float32: scrittura, rilettura, errore massimo
   — lossless 0, half 5e-4, DWA 6e-3, B44 2e-3 lontano dai blocchi con inf —, metadati, rilettura con
   TinyEXR dei codec che conosce, EXR scritto da Godot riletto da OpenEXR); `ui_smoke.gd` (export ZIP
   identico al PIZ e con rig, DWAA riletto); `--selftest` dell'app esportata ora pretende l'estensione
   caricata (`release.sh` fallisce altrimenti). Export macOS: dylib in `Contents/Frameworks`, firmata
   ad hoc dall'export; Windows: DLL accanto all'exe. Tempi a 4k×2k half, bake compreso: ZIP 0,65 s,
   DWAA 0,7 s. Dimensioni sul rig di prova: PIZ 40 KB, ZIP 23 KB, DWAA 14 KB.
5. [x] **Verifica sul PC** (17/09): la DLL si carica, l'EXR viene salvato correttamente. HTJ2K (nuovo in OpenEXR 3.4) è compilato ma non esposto nel menu:
   i software 3D con OpenEXR < 3.4 non lo leggono.

### Interfaccia bilingue — fatta il 23/09/2026

Obiettivo: l'app in inglese per default, l'italiano quando ha senso, senza doppiare i testi nel codice.

1. [x] **Inglese come lingua base**: le stringhe nel codice sono in inglese, quindi un testo senza
   traduzione resta leggibile invece di sparire. Migrazione una tantum delle ~200 stringhe italiane
   (label, tooltip, voci di menu, forme, materiali, gelatine, preset di gradiente, messaggi di stato).
   Console, log CLI/selftest e metadati EXR restano solo in inglese: non sono interfaccia.
2. [x] **Traduzione italiana** in `core/lang_it.gd` (`LangIt.DATA`, inglese → italiano), caricata a
   runtime in un `Translation` con locale `it` dall'autoload `I18n` (`core/i18n.gd`). Niente CSV né
   `.translation` importati: il dizionario è codice, sta in git e non dipende dall'import.
   I `Control` si ritraducono da soli (Godot usa `atr` su testo, tooltip, voci di popup e schede);
   solo i testi composti a mano (`%` o concatenazione) passano da `tr()` e vengono riscritti da
   `Main._retranslate()` al cambio di lingua.
3. [x] **Politica**: la scelta salvata in `settings.json` vince sempre; con `auto` (default) si segue
   `OS.get_locale_language()`, quindi italiano su un sistema in italiano e inglese in tutti gli altri
   casi. Un codice che non sappiamo tradurre ricade sull'inglese. Selettore *Language* in fondo alla
   colonna destra (Automatic (system) / English / Italiano), cambio a caldo senza riavvio.
4. [x] **Test**: `tools/i18n_smoke.gd` (politica `auto`/esplicita/sconosciuta, chiavi invariate in
   inglese, ogni voce del dizionario applicata in italiano, barra di stato ritradotta, selettore che
   cambia e ricorda la lingua).

5. [x] **Plugin C4D e Blender in inglese** (23/09): voci di menu, tooltip, dialoghi, pannello della
   sidebar, report e stampe in console. Lì non c'è selettore: Cinema 4D e Blender si usano quasi sempre
   in inglese, e i testi sono pochi. Rinominati i comandi C4D (`HDRI Studio: reload textures`,
   `create HDRI environment`, `Octane diagnostics`) e il pannello Blender (`Reload textures`,
   `Separate lights visible to camera`); i README dei plugin citano i nomi nuovi. Verifica: add-on
   registrato in Blender headless e `blender_link_test.py` end-to-end OK; il plugin C4D è solo
   controllato sintatticamente, va riprovato sul PC.

Resta in italiano: `GUIDA.md`, i README dei plugin, questo piano e i commenti/docstring del codice.

### Houdini — preset misurato e live link — fatto il 23/09/2026

L'ultimo buco del piano iniziale. Niente LightPaint: HDRI + luci separate.

1. [x] **Orientamento misurato** (`tools/houdini_calibrate.py`, hython + Karma CPU): l'HDRI di
   taratura in un envlight, sei render stretti lungo gli assi del mondo e uno largo sul centro.
   Risultato: centro dell'immagine su **−Z**, +X interno su **−X**, +Y su +Y — una rotazione di 180°
   attorno a Y, la stessa di Godot/Blender; punto bianco (az +25, el +12) a destra e in alto come nel
   preview → nessuno specchio. Il preset `Houdini` (flip false, shift 0, mirror_x false) era giusto,
   ora è verificato e non più indovinato. Da sapere: `light_contribprimary` dell'envlight è 0 di
   default, cioè il dome illumina ma non si vede dalla camera.
2. [x] **Plugin** in `plugins/houdini/` (package JSON + `scripts/python/hdri_studio_link/`, startup
   123.py/456.py, shelf con Reload textures / Create HDRI environment / Live link on-off). Polling su
   `hou.ui.addEventLoopCallback`, `texcache -c` + riassegnazione dei parametri file per il reload,
   fallback sulla data di modifica. Luci separate = area light *grid* dentro `/obj/HDRI_Studio_Lights`,
   figlie del null `HDRI_Studio_Center`, con `light_texture`, dimensione fisica, intensità 1 e
   `normalizearea` spento (radianza del pixel, come il piano emissivo in Blender). Le grid light
   emettono lungo il proprio −Z: base (−R, U, F), destrorsa.
3. [x] **Test**: `tools/houdini_link_test.py` end-to-end con `blender_link_host.gd` (ora accetta
   `-- --target <preset>`) e `tools/houdini_separate_verify.py` in Karma — la stessa luce nell'HDRI e
   come area light illuminano un piano diffuso con rapporto **0,984** (1,6% di scarto, contro 1,002 del
   piano emissivo in Cycles), e un quadrante di prova sulla texture esce in alto a sinistra come nella
   mappa dell'app, quindi niente specchio.

Resta fuori: LightPaint dal viewport di Houdini e una prova su una scena vera (finora solo headless).

### Rig dentro il `.hdr` — fatto il 23/09/2026

L'EXR portava il progetto dentro di sé dal 16/09, il `.hdr` no: `save_hdr` scriveva solo `SOFTWARE=` e
ignorava il rig. Ora i due formati si comportano allo stesso modo.

1. [x] **Scrittura**: l'header Radiance è testo fino alla prima riga vuota, quindi `save_hdr` ci
   aggiunge `#HDRISTUDIO_RIG=<json>` (il JSON di `rig.to_dict()`, su una riga sola; eventuali a capo
   sono sostituiti da spazi perché un a capo chiuderebbe l'header a metà del rig). Scritta come
   **commento**: i lettori saltano i commenti in silenzio, mentre per una variabile sconosciuta Godot
   stampa un warning con tutta la riga — provate entrambe le forme, tenuta quella zitta.
2. [x] **Lettura**: `HdriExport.read_hdr_variable` scorre l'header, e `read_rig_json` sceglie da sé
   fra attributo EXR e riga del `.hdr`. *Apri rig…* accetta `.json`, `.exr` e `.hdr`.
3. [x] **Test**: in `ui_smoke.gd`, accanto all'export `.hdr` che già c'era — la riga riletta, il rig
   riaperto dal file (una luce, nome e parametri), e la rilettura dei pixel da parte di Godot come
   prova che la riga in più non disturba chi legge l'immagine. Controllato anche con un parser RGBE
   scritto a parte: header chiuso bene, riga di risoluzione intatta, payload esattamente W×H×4 byte,
   centro 7,48 contro i 7,5 attesi. Su questo Mac non ci sono né OpenImageIO né ImageMagick, quindi la
   prova con un lettore di terze parti compilato resta da fare (stb_image, che è quello che usano in
   tanti, tronca le righe lunghe senza rompersi — letto nel sorgente, non provato).

### Rig nel `.hdr` su righe corte — fatto il 28/09/2026

Due `.hdr` esportati con un rig grande (`gem-studio-v5-dragon`, `gold-studio-v8-dragon`) non si aprivano
nel visualizzatore web: `THREE.RGBELoader: Bad File Format: missing image size specifier`. La causa era
la riga `#HDRISTUDIO_RIG=<json>`, lunga 8023 e 18709 caratteri. Il formato Radiance ammette righe
libere nell'header, ma molti lettori hanno un buffer fisso per riga: `RGBELoader` di Three.js
(`three-stdlib`) smette di leggere l'header oltre i 1024 caratteri, e così non arriva mai a
`-Y … +X …`; il classico `rgbe.c`, da cui derivano anche le versioni vecchie di OpenImageIO, legge a
pezzi di 128 byte. Godot e stb_image reggono, per questo il 23/09 non era saltato fuori.

1. [x] **Scrittura**: il JSON del rig viene compresso (deflate), codificato in base64 e spezzato su
   righe di commento da 117 byte al massimo: `#HDRISTUDIO_RIG_DEFLATE=<byte del JSON>`, poi
   `#HDRISTUDIO_RIG_B64=<pezzo>` in ordine. Il base64 non ha a capo né caratteri fuori dall'ASCII,
   quindi il limite regge qualunque cosa ci sia nei nomi delle luci. Il rig da 18 KB diventa qualche
   decina di righe.
2. [x] **Lettura**: `HdriExport.read_hdr_rig` ricompone le righe; se non le trova usa ancora la riga
   unica dei file vecchi, che quindi si riaprono come prima.
3. [x] **Test** in `ui_smoke.gd`: nessuna riga dell'header oltre `HDR_HEADER_LINE_MAX` (120 byte, sotto i
   128 di `rgbe.c`) sia nell'export dell'app sia con un rig da 12,9 K caratteri non ASCII, il rig grande
   riletto identico, i pixel riletti da Godot, e un `.hdr` nel vecchio formato ancora letto. Controllato
   anche fuori da Godot: `RGBELoader` di `three-stdlib` 0.184 (quello del visualizzatore) legge i nuovi
   file e rifiuta i due vecchi con lo stesso errore; una simulazione di `rgbe.c` con buffer da 128 byte
   legge i nuovi.

I due `.hdr` del visualizzatore vanno riesportati: *Apri rig…* li riapre dal vecchio formato.

### Finestra grande all'avvio — fatto il 23/09/2026

I 1600×900 del progetto sono una finestrella su un monitor grande (su questo Mac lo schermo è
3456×2234: meno della metà in larghezza).

1. [x] **Default**: `_setup_window()` apre al 92% dell'area utile dello schermo, centrata. L'area
   utile, non lo schermo intero, così la barra dei menu e la dock non ci finiscono sotto.
2. [x] **Memoria**: `_save_window()` in `_exit_tree` salva geometria e stato massimizzato in
   `settings.json`; al riavvio si ripristinano. Senza, chi rimpicciolisce la finestra se la ritrova
   grande a ogni avvio. Una geometria si scarta se il centro non cade in nessuno schermo (monitor
   scollegato) o se è più piccola di 960×600: in quei casi si riparte dal default.
3. [x] **Test e CLI** (`_unattended()`: `--fresh`, `--screenshot`, `--selftest`, `--export`) restano
   ai 1600×900 del progetto e non scrivono la chiave `window`, così ui_smoke misura la stessa finestra
   sul Mac e sul PC e lo screenshot della guida non cambia formato.
4. [x] **Provato** sul Mac con `--quit-after`: primo avvio 3178×1858 a (138, 158) su uno schermo
   3456×2234 con area utile 3456×2020; riavvio che ripristina 1200×800; posizione fuori schermo
   (x 9000) e dimensione assurda (200×150) che ricadono sul default; massimizzata che si riapre
   massimizzata. ui_smoke, i18n_smoke e sky_smoke passano e la chiave `window` resta intatta.

Da sapere per dopo: su Retina Godot lavora in pixel fisici e non scala l'interfaccia (`scale 2.0`
sullo schermo, `content_scale_factor` 1.0), quindi testo e pannelli restano della stessa dimensione
fisica di prima e la finestra più grande dà solo più spazio a preview e mappa. Se un giorno si vuole
l'interfaccia più grande sul Mac, la leva è `content_scale_factor`, non la dimensione della finestra.
*(Fatto lo stesso giorno: vedi la sezione seguente.)*

### Revisione UX e sistema visivo — fatto il 23/09/2026

Una revisione indipendente (subagent `ux-reviewer`, definito in `.claude/agents/ux-reviewer.md`) ha
guardato l'app a schermo in inglese e italiano, a 1600×900 e 1280×800. Il punto più grave era la
leggibilità: su Retina tutto il testo usciva a metà grandezza, e la gerarchia era rovesciata (titoli a
15 px, testo a 16). Fatte le dieci correzioni prioritarie e quasi tutte quelle a basso costo:

1. [x] **Scala dello schermo**: `content_scale_factor` = densità dello schermo (macOS
   `screen_get_scale()`, Windows DPI/96) × *Text size* (90/100/110/125%, nuovo pannello *Interface*
   con la lingua), ricalcolata su `dpi_changed`; 1 nei modi non interattivi.
2. [x] **Tema unico** in `ui/ui_style.gd`: testo 15/13/11, etichette 0,78 e valori 0,96, sottotitoli di
   sezione piccoli e maiuscoli, caselle di spunta disegnate (quella vuota di default aveva contrasto
   1,16:1), campioni colore con bordo, pulsante *Export EXR…* d'accento, cornice scura come lo splash.
3. [x] **Spazi** 4/8/16/24 e un'unica linea fra i pannelli; **colonna etichette** unica a 104 px con i
   puntini (sette etichette erano troncate o spingevano il controllo).
4. [x] **Rotella** sugli slider disattivata: scorrendo il pannello cambiava i valori, senza undo.
5. [x] **Preview**: non più `SubViewportContainer` (a scala 2 rendeva il 3D a metà risoluzione), camera
   che inquadra sempre le tre sfere; **mappa** larga quanto la colonna, altezza ricordata.
6. [x] Suggerimenti che vanno a capo (il gradiente in italiano allargava la colonna di 68 px), barra di
   stato in due parti con le scorciatoie nel tooltip, messaggio prima dell'export, gradi e nomi della
   mappa leggibili, "Nessun file" al posto dei trattini, *Rotazione extra* con tooltip, live link nell'
   ordine d'uso con la destinazione, soglia del clipping su una riga sua, lucchetto monocromo, occhio
   barrato per le luci spente, Kelvin 1670–12000 sullo slider, titoli doppi delle schede tolti,
   contatori di preset e catalogo ritradotti, messaggio utile aprendo un EXR senza rig.
7. [x] **Provato**: ui_smoke, i18n_smoke, sky_smoke passano; catture a scala 1 (1600×900 e 1280×800,
   EN e IT) e a scala 2 sul Retina (3178×1858 fisici = 1589×929 logici): testo, icone e sfere nitidi.

Il 24/09, su richiesta: **margine di 16 px** fra il bordo dei pannelli laterali e tutto il contenuto
(prima 12, e sul lato destro il testo toccava la barra di scorrimento). Le barre di scorrimento ora
stanno sul bordo del pannello e il margine è dentro l'area che scorre.

Non fatti, elencati in `docs/stato.md`: colonna destra richiudibile, pannello proprietà riordinato,
unità come suffisso, area messaggi unica, pallino del live link, stato vuoto del catalogo, ⌘S/⌘O/⌘E,
export in thread, e il click sul vuoto della mappa (scelta di comportamento).

### 5.4 Fase 4 — test in C4D

> [!todo] Da fare sul PC
> 1. `git pull`, riavvia C4D. Nella scena crea un'**Octane Area Light**, mettile un ImageTexture nello
>    slot texture (qualsiasi EXR), chiamala `HS_TEMPLATE`.
> 2. Nell'app: live link attivo; su una luce spunta *Separata*, distanza per esempio 150 cm.
> 3. In C4D deve comparire il null `HDRI Studio Lights` con dentro `HS: <nome luce>`, nella direzione
>    giusta, con la texture della luce. Spostando la luce nell'app, la luce in C4D segue.
> 4. Da verificare e riferirmi: (a) la luce illumina verso il centro o via dal centro? (se via, cambio
>    il segno di `LIGHT_EMITS_ALONG_Z`); (b) la texture è dritta o specchiata? (c) con una sfera
>    diffusa al centro, la luce separata dà la stessa esposizione della stessa luce lasciata nell'HDRI?
>    Il rapporto fra i due è la calibrazione della Power.

### 5.3 Fase 3 — stato e test in C4D

> [!success] Verificato sul PC il 15/09/2026: click sul modello in C4D → la luce si sposta nell'app e
> il riflesso compare nel Live Viewer di Octane. Due intoppi risolti per strada: ID di plugin in
> collisione con `C4d_objects` e cartella `res/` obbligatoria per il ToolData.

> [!todo] Procedura (per riferimento)
> 1. `git pull` e riavvia C4D (il plugin registra il nuovo tool).
> 2. Nell'app: live link attivo, una luce selezionata (per esempio il Key scrim).
> 3. In C4D: attiva **HDRI Studio LightPaint** (Extensions, o Shift+C → "LightPaint"), clicca su un
>    punto del modello nel viewport. La luce deve spostarsi nell'app e, un istante dopo, il riflesso
>    deve comparire in quel punto nel Live Viewer di Octane. Trascinando, il riflesso segue il mouse.
> 4. Se non succede niente: console C4D (errori del tool) e stato del pannello Live link nell'app.
- Modalità fotometrica, ACEScg, texture nelle luci, libreria di preset, plugin per gli altri software.

## 6. Validazione fisica

Tre test da automatizzare in Fase 0 e rilanciare a ogni modifica del bake:

1. **Furnace.** HDRI uniforme di valore 1.0 → in Cycles una sfera diffusa bianca (albedo 1) deve rendere
   esattamente 1.0. Verifica che né noi né il renderer applichiamo correzioni spurie.
2. **Singola luce.** Luce piccola di radianza `L` e angolo solido `Ω` → l'irradianza su un piano che la
   guarda frontalmente è `E ≈ L · Ω`, quindi un piano diffuso bianco rende `E / π`. Confronto numerico
   con il pixel del render.
3. **Confronto con emissive plane.** In Blender: un piano emissivo con la stessa dimensione angolare,
   camera panoramica equirettangolare al centro, render Cycles → differenza pixel per pixel con il nostro
   bake. Deve essere sotto la soglia di rumore.

Più un test di orientamento (l'HDRI di taratura) per ogni preset di export.

## 7. Rischi

| Rischio | Impatto | Mitigazione |
|---|---|---|
| `save_exr` assente nei template di export | Export solo dall'editor | Verificato nel sorgente 4.7 che il modulo si compila ovunque; comunque il writer `.hdr` è il fallback, e un writer EXR non compresso è ~150 righe |
| Convenzioni di orientamento sbagliate | HDRI ruotate nel software 3D | Fase 0 le calibra prima di tutto il resto |
| Socket in C4D bloccante | Live link instabile | Polling nel main thread + fallback su `mtime` |
| Octane non rilegge la texture cambiata su disco | Live link inutile con Octane | Verificato in Fase 0 prima di scrivere il plugin; alternanza di due file come piano B; Redshift come piano C |
| Half float satura sulle luci "sole" | Sole clampato a 65504 | Passaggio automatico a float32 |
| Scope creep verso HDR Light Studio completo | Non si finisce mai | La Fase 1 è chiusa: luci, preview, export. Punto |

## 8. Domande aperte

Rispondi a quelle che sai, sul resto scelgo io e lo segno in [[#9. Decisioni]].

1. ~~Software 3D di destinazione per il primo live link~~ → Cinema 4D + Octane.
2. ~~Piattaforma~~ → Godot.
3. ~~Forme di luce~~ → rect, ellisse, anello, gradiente + **scrim**.
4. ~~Sfondo~~ → entrambi: gradiente di base e HDRI esistente da aumentare, già in Fase 1.
5. ~~Risoluzione~~ → 4k×2k per ora; 8k e `.hdr` in Fase 2.
6. ~~Unità di intensità~~ → lineare + EV; fotometrico dopo il prototipo.
7. ~~Preview~~ → tre sfere.
8. ~~Distribuzione~~ → tool personale.
9. ~~Altre feature~~ → rimandate a dopo la verifica di fattibilità; si procede per gradi.

Nessuna domanda bloccante. Prossimo passo: Fase 0.

## 10. Cosa manca rispetto al piano iniziale

Confronto con la v0.3 (il piano approvato prima di scrivere codice) e con le voci aperte aggiunte poi.

| Voce | Da dove viene | Stato |
|---|---|---|
| Radiance `.hdr` in export | Fase 1/2 | Fatto (16/09): RGBE codificato sul GPU, flat, verificato in rilettura |
| Codec EXR (ZIP, DWAA, DWAB…) | richiesta 15/09 | Fatto (17/09, Fase 7): OpenEXR dentro l'app con la GDExtension HsOpenEXR, scrittura e lettura di tutti i codec; Blender non serve più |
| Metadati nell'EXR (chromaticities Rec.709, JSON del rig dentro il file) | §4.5 | Fatto (16/09): scritti da OpenEXR insieme ai pixel (dal 17/09); nel fallback TinyEXR iniettati nell'header dopo la scrittura; il rig si riapre dall'EXR e, dal 23/09, anche dal `.hdr` |
| ACEScg come spazio di output | §2, Fase 3 | Fatto (16/09): conversione Rec.709 → AP1 (Bradford) nel bake dell'export, chromaticities AP1/D60 nei metadati, anche per le luci separate |
| Libreria di preset di studio | Fase 3 | Fatta: tab Preset, cartella di JSON + miniature, carica/aggiungi/elimina |
| Preset di orientamento **Houdini** e plugin Houdini | §3, Fase 3 | Fatto (23/09): preset misurato con Karma (nessun flip, nessuno shift), plugin con reload e luci separate (niente LightPaint) |
| Test 3 di §6 (diff pixel per pixel con un piano emissivo in Cycles) | §6 | Fatto in forma equivalente: furnace, singola luce, e ora piano emissivo vs HDRI (1.002) |
| Catalogo: anteprima al passaggio del mouse, tag/preferiti | aggiunta Fase 3 | Fatto: metadati in `user://catalog_meta.json`, filtri per preferiti e tag, anteprima 384×192 |
| Modalità fotometrica | Fase 3 | Fatta e validata |
| Fase 4, calibrazione Power di Octane e verso/specchio texture | Fase 4 | In attesa del test sul PC (spunte nel pannello Live link) |
| Fase 4 opzioni: luce invisibile alla camera, export in blocco | Fase 4 | Blender: fatto (visibilità); C4D: no |

Tutto il resto del piano iniziale è fatto e verificato: bake fisico, sei forme (scrim compresa),
sfondo gradiente/HDRI, export con preset, live link C4D+Octane e Blender, LightPaint da entrambi,
luci Texture e catalogo, luci separate, app standalone.

## 9. Decisioni

> [!note] Da compilare
> Qui finiranno le risposte alle domande e le scelte fatte durante lo sviluppo, con la data.

- 15/09/2026 — Piattaforma: **Godot 4.7**.
- 15/09/2026 — Primo live link: **Cinema 4D + Octane** (è lo stack del progetto in corso). Redshift e
  Blender dopo. Se il reload di Octane si rivelasse ostico in Fase 0, si valuta di passare a Redshift per
  questa fase — Ignazio è disponibile ad adattarsi.
- 15/09/2026 — Distribuzione: **tool personale**. Si lancia dall'editor Godot; export/installer non sono
  una priorità.
- 15/09/2026 — Forme in Fase 1: rect, ellisse, anello, gradiente, **scrim** (modello: sorgente dietro
  telo lambertiano, irradianza `depth / (|q|² + depth²)^(3/2)`).
- 15/09/2026 — Sfondo in Fase 1: gradiente **e** HDRI importata come layer base. Obiettivo principale del
  tool: luce da studio, spesso partendo da un'HDRI esistente da aumentare.
- 15/09/2026 — Risoluzione di default 4096×2048 half. 8k e `.hdr` rimandati a Fase 2.
- 15/09/2026 — Intensità lineare + EV, tre sfere di preview, nessuna feature extra prima del prototipo.
- 16/09/2026 — ID Octane per C4D 2026 misurati con la diagnostica del plugin: tag Octane Light 1029526
  (Texture 1155, Power 1151, Surface brightness 1166, Camera visibility 1163), shader Image Texture
  1029508 (File 1100, Reload 1127, Color space 1118 con Linear sRGB = 2), tag Octane Environment
  1029643 (Texture 1150, Power 1151, Imp. Samp. 1153, Type 1162 con Primary = 0). Luce separata di
  default e ambiente HDRI di default non dipendono più da ricerche per nome.
- 15/09/2026 — Orientamento **Cinema 4D**: C4D nativo mostra il punto bianco a sinistra → preset
  "Cinema 4D nativo" con specchio; **Octane** lo mostra a destra, come il preview → preset
  "Cinema 4D + Octane" senza specchio, che è il default. I due renderer non concordano fra loro.
- 23/09/2026 — Lingua: **inglese di base, italiano come traduzione**. Il default è `auto` (segue la
  lingua del sistema: italiano solo su un OS in italiano), la scelta esplicita nel selettore vince e
  viene ricordata. Le stringhe nel codice sono in inglese perché un testo non tradotto resti leggibile.
- 23/09/2026 — Houdini: **niente LightPaint** nel primo plugin. Reload dell'HDRI e luci separate
  coprono il grosso del valore; il picking nel viewport di Houdini è più indiretto che in Blender/C4D
  e si può aggiungere dopo senza toccare il resto.
- 23/09/2026 — Icona dell'app: la sfera del preview con il riflesso del softbox su tessera scura, stessa
  tavolozza dello splash. `tools/make_icon.py` (Pillow + numpy, riflesso calcolato come nell'app) genera
  `icon.png` per Godot, `icon.icns` per macOS e `icon.ico` per Windows; gli export puntano lì.
- 15/09/2026 — Assi in **Octane**: da dentro la sfera si vede esattamente il preview; le etichette
  degli assi differiscono solo su X perché C4D è left-handed (rosso = +X interno finisce su −X di C4D,
  Y e Z allineati). Conversione coordinate C4D → interne per LightPaint (Fase 3): `(x, y, z) → (−x, y, z)`.
- 15/09/2026 — Sfumatura: distanza da rettangolo arrotondato (parametro *Angoli °*) al posto della
  distanza a scacchiera, così la banda sfumata gira attorno agli angoli. Default 0 nella classe (rig
  vecchi e test invariati), 3° per le luci create dall'interfaccia.
- 15/09/2026 — Gradiente: le tacche (max 8, pos + rgb) stanno in un secondo SSBO indicizzato per luce;
  il colore del gradiente moltiplica il colore della luce come fa l'immagine per le luci Texture.
- 15/09/2026 — Fotometrico: K si misura sul GPU con lo stesso shader del bake (modalità `measure` nel
  frame locale della luce) invece di replicare i profili su CPU: una sola verità per le forme, precisione
  indipendente dalla dimensione della luce, costo ~ms solo quando cambia la forma.
- 15/09/2026 — Catalogo: solo riferimenti ai file originali (percorso nel rig), niente copie né
  database; i metadati opzionali stanno in un sidecar JSON accanto all'immagine, così la collezione
  resta leggibile e modificabile a mano.
- 15/09/2026 — Orientamento **Blender** misurato: centro immagine = +X, u = 0,25 = +Y, alto = +Z,
  nessuno specchio. L'EXR va in Blender così com'è.
- 15/09/2026 — Convenzione interna dell'equirettangolare: Y in alto, centro immagine = +Z, u = 0,25 = +X
  (identica a `PanoramaSkyMaterial` di Godot, così il preview non ha offset). Gli offset per software
  sono applicati solo all'export.
- 15/09/2026 — Spazio colore di output: lineare Rec.709. ACEScg rimandato a Fase 3.
- 17/09/2026 — EXR: **OpenEXR in una GDExtension nostra** (C++, BSD-3) invece di Blender in
  background. Statico, senza dipendenze di sistema, cross-compilata per Windows dal Mac con mingw.
  Il fallback TinyEXR resta nel codice (via `ClassDB.class_call_static`) per non rompere l'app se
  il binario manca, ma non è più la strada normale.
- 23/09/2026 — Il rig dentro il `.hdr` si scrive come **commento** dell'header Radiance
  (`#HDRISTUDIO_RIG=…`) e non come variabile: i lettori ignorano i commenti in silenzio, mentre una
  variabile che non conoscono la segnalano (Godot stampa un warning con tutto il JSON a ogni
  apertura dell'immagine). Il formato resta leggibile a occhio, senza base64.
  **Superata il 28/09** per la parte "una riga sola, senza base64": vedi sotto.
- 23/09/2026 — La finestra si apre al **92% dello schermo** al primo avvio e poi **ricorda**
  com'è stata lasciata, invece di essere massimizzata a forza ogni volta: massimizzare è una scelta
  dell'utente, non del programma, e una finestra rimpicciolita apposta deve restare rimpicciolita.
- 23/09/2026 — L'interfaccia si scala con **`content_scale_factor`** e non moltiplicando ogni misura
  del codice per un fattore (come fa l'editor di Godot): un solo punto, e tutto il codice resta in
  pixel logici. Il prezzo sono le icone del tema di default, ingrandite e un po' morbide sul Retina;
  quelle che contano (caselle di spunta, icone della lista) le disegniamo noi a 2×.
- 23/09/2026 — Valori di design in **`UiStyle`** e nessun numero di font, colore o spazio sparso nei
  pannelli: la revisione ne aveva contati sei di font e nove di separazione, cresciuti pannello per
  pannello.
- 28/09/2026 — Il rig nel `.hdr` si scrive **compresso e in base64, su righe da 117 byte al massimo**, e
  non più come JSON leggibile su una riga sola: `RGBELoader` di Three.js e `rgbe.c` hanno un limite per
  riga (1024 caratteri e 128 byte) e con un rig grande perdevano la riga di risoluzione. Leggibilità a
  occhio persa, ma nessun lettore conosciuto ha limiti sotto i 128 byte. Restano commenti (`#`) e la
  lettura accetta ancora il formato vecchio.
- 30/10/2026 — Release **0.10.0** e non 0.9.2: dopo la 0.9.1 sono entrate funzioni nuove (plugin
  Houdini, interfaccia bilingue, revisione UX), non solo correzioni.
