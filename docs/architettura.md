# Architettura

Mappa per orientarsi. Il dettaglio con la matematica del bake, le formule delle forme e il protocollo
del live link è in [`PIANO.md` §4](../PIANO.md).

## Cartelle

```
hdri_studio/          progetto Godot
  core/               il modello: rig, luci, impostazioni, utilità
  bake/               compute shader GLSL + il baker che lo esegue
  preview/            preview 3D (sfere, modello GLB, materiali) e shader del viewport
  ui/                 i pannelli, uno per file, costruiti in codice (non ci sono .tscn)
  export/             scrittura EXR/HDR, preset di orientamento, metadati
  livelink/           server TCP
  scenes/main.gd      il direttore d'orchestra: costruisce l'interfaccia e collega tutto
  tools/              script di test e di servizio, lanciati con `-s res://tools/…`
  plugins/            i plugin per C4D, Blender e Houdini (Python)
  addons/hs_openexr/  la GDExtension già compilata (dylib + DLL)
gdextension/          sorgenti C++ dell'estensione OpenEXR
tools/                script della macchina: release, build dell'estensione, icona, splash
docs/                 questa documentazione
```

## I pezzi principali

| File | Ruolo |
|---|---|
| `core/rig_light.gd` | Una luce: forma, posizione (azimut/elevazione/rotazione), dimensione angolare, intensità o illuminamento, colore, fusione, gradiente, texture, flag "separata". Serializza sé stessa in JSON. |
| `core/light_rig.gd` | Il rig completo: elenco di luci + sfondo + HDRI di base. È il file `.json` che si salva e che finisce nei metadati dell'EXR. |
| `bake/bake.glsl` | Il cuore: per ogni pixel della equirettangolare somma il contributo delle luci. Ogni forma è una funzione di copertura sulla sfera. |
| `bake/baker.gd` | Prepara i buffer, lancia il compute shader, tiene la texture RGBA32F. La stessa texture va al preview (`Texture2DRD`) senza passare dalla CPU. |
| `preview/preview_3d.gd` | Sfere di prova o modello GLB, materiali, LightPaint, camera dal live link. |
| `ui/*.gd` | Un pannello per file, tutti costruiti in `_init()`. `param_row.gd` è la riga slider+spinbox usata ovunque. |
| `export/hdri_export.gd` | Scrive EXR (via `ExrCodec` → GDExtension, fallback TinyEXR) e `.hdr`. Qui stanno i **preset di orientamento** per software e i metadati (chromaticities, rig JSON). |
| `livelink/live_link.gd` | Server TCP su 127.0.0.1:47820, protocollo JSON-lines. |
| `core/i18n.gd` + `core/lang_it.gd` | Autoload delle lingue e dizionario italiano (vedi [convenzioni.md](convenzioni.md)). |
| `scenes/main.gd` | Costruisce le tre colonne, collega i segnali, gestisce file dialog, export, autosave, undo e i messaggi del live link. È il file più grosso: se cerchi "dove succede X", di solito succede qui. |

## Flusso dei dati

1. L'utente muove uno slider → il pannello scrive nel `RigLight` → `main` chiede un bake.
2. `HdriBaker` esegue `bake.glsl` e riempie la texture equirettangolare.
3. La stessa texture alimenta il preview 3D (riflessi in tempo reale) e la mappa.
4. All'export (o a ogni modifica, se il live link è attivo) `HdriExport` riscrive il bake su disco in
   EXR, applicando il preset di orientamento del software scelto.
5. Il server manda `hdri_updated` ai plugin collegati, che ricaricano la texture nel software 3D.
6. Le luci marcate **separate** non entrano nell'HDRI esportata: vengono scritte come EXR planari
   singoli e ricreate nel software 3D come luci vere (piani emissivi in Blender, area light in Houdini,
   cloni di una luce modello in C4D) tramite il messaggio `separate_lights`.
7. Dal software 3D tornano indietro `lightpaint` (click sul modello → la luce si sposta sul riflesso) e
   `camera` (il preview segue l'inquadratura).

## Convenzione degli assi

Internamente: **Y in alto**, centro dell'immagine su **+Z**, angoli in gradi, distanze in centimetri
(il messaggio del live link porta `unit_scale` 0.01). Ogni software 3D ha la sua convenzione e la sua
traduzione, misurata con l'HDRI di taratura `out/calibration.exr` (dischi colorati sugli assi e un
punto bianco ad az +25° / el +12°):

- **Blender**: interno (x, y, z) → (z, x, y), nessuno specchio.
- **Houdini**: interno (x, y, z) → (−x, y, −z), nessuno specchio (misurato con Karma il 23/09).
- **Cinema 4D**: Y in alto ma left-handed → le basi delle luci separate si specchiano su X con Octane;
  il renderer nativo mostra l'immagine specchiata e ha un preset suo.
