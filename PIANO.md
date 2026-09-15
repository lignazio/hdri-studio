---
tags:
  - hdri-studio
tipo: nota
area: progetto
---

# HDRI Studio — Piano

> [!success] Stato: v1.0 — 15 settembre 2026 — le tre fasi del piano sono chiuse
> Verificato sul PC con Cinema 4D + Octane: live link e **LightPaint dal viewport**. Nell'app: luci
> parametriche (sei forme, scrim e Texture comprese), catalogo per sottocartelle, modalità fotometrica
> validata contro Cycles, fusione Normale, undo, export con preset per software, modello GLB nel
> preview. Da qui in poi: rifiniture d'uso e le voci aperte in [[#Fase 3 — LightPaint e maturità]].
> Progetto in `hdri_studio/`, repository privato: https://github.com/lignazio/hdri-studio. Ambiente rilevato sulla macchina: macOS 15.7 su M1 Pro,
> Godot 4.7.1, Blender 5.1.1, Cinema 4D 2025/2026, Houdini 20.0 e 21.0.

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
      fallback sulla data di modifica ogni secondo; comando "HDRI Studio: ricarica texture".
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

1. **Flag per luce** "separata": esclusa dal bake dell'HDRI; all'export scrive `<rig>_<luce>.exr`
   ritagliato al rettangolo della luce (margine = sfumatura), lineare, con la radianza già applicata.
2. **Messaggio live link** `separate_lights`: lista di `{name, azimuth, elevation, roll, width, height,
   distance, path}` inviata insieme a `hdri_updated`; slider *Distanza* nel pannello (globale, con
   override per luce in seguito).
3. **Plugin C4D**: un null `HDRI Studio Lights` con una luce per voce (Octane Light di tipo Area con
   ImageTexture → il file; in alternativa area light nativa), posizione `centro + D·dir` (con la X
   invertita per il sistema left-handed), orientamento look-at verso il centro più roll, scala alla
   dimensione fisica; aggiornata a ogni messaggio, rimossa se il flag viene tolto. Il centro è un null
   che l'utente può spostare sul soggetto.
4. **Calibrazione dell'intensità in Octane**: la Power dell'area light non è radianza; si tara con il
   furnace test di Fase 0 (luce separata vs stessa luce nell'HDRI → stesso pixel su una sfera diffusa).
5. Opzioni: luce invisibile alla camera, distanza per luce, esportare tutte le luci separate in blocco.

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
- 15/09/2026 — Orientamento **Cinema 4D**: C4D nativo mostra il punto bianco a sinistra → preset
  "Cinema 4D nativo" con specchio; **Octane** lo mostra a destra, come il preview → preset
  "Cinema 4D + Octane" senza specchio, che è il default. I due renderer non concordano fra loro.
- 15/09/2026 — Assi in **Octane**: da dentro la sfera si vede esattamente il preview; le etichette
  degli assi differiscono solo su X perché C4D è left-handed (rosso = +X interno finisce su −X di C4D,
  Y e Z allineati). Conversione coordinate C4D → interne per LightPaint (Fase 3): `(x, y, z) → (−x, y, z)`.
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
