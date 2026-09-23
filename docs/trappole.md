# Trappole

Cose che hanno fatto perdere tempo almeno una volta. Se una sessione ne scopre un'altra, aggiungila qui.

## Godot

- **Classi che "non esistono"**: manca l'`--headless --import` dopo un pull che ha aggiunto script con
  `class_name`. Godot li registra in `.godot/`, che non è versionata.
- **Autoload invisibili negli script `-s`**: uno script lanciato con `-s res://tools/…` viene compilato
  prima che gli autoload esistano, quindi `I18n.qualcosa` non compila. Prendilo dal tree:
  `root.get_node("/root/I18n")`. Dentro l'app (nodi normali) l'autoload si usa per nome senza problemi.
- **`bake.glsl` ha due copie**: il file e la stringa incorporata in `bake_glsl_source.gd`, usata
  dall'app esportata. Dopo ogni modifica: `python3 hdri_studio/tools/embed_shader.py`. `ui_smoke` controlla.
- Il rig salva i percorsi delle immagini in **assoluto**: un rig portato da un'altra macchina va
  ricaricato a mano nella parte delle texture.

## EXR

- Senza la GDExtension l'app scrive solo **PIZ** (fallback TinyEXR di Godot) e non legge DWAA/DWAB/B44.
  La riga di stato del pannello Export lo dice all'avvio: se c'è scritto "not loaded", il binario non è
  stato caricato (su Windows la DLL deve stare accanto all'exe).
- `exr_smoke` stampa errori di TinyEXR sui codec che non conosce: sono attesi, conta l'ultima riga.
- Sopra 65504 il salvataggio half ricade su float32 e avvisa: è voluto.

## Live link

- La porta è **47820**, solo su 127.0.0.1. Se il plugin dice "app unreachable", nell'app il live link
  non è *Active* oppure manca il file di export.
- Quando un plugin si collega, l'app gli manda subito l'HDRI corrente e le luci separate: se non
  succede niente, il file di export non esiste ancora su disco.
- I test del link sono a due processi (host Godot + software 3D): l'host resta in ascolto 25 secondi,
  vanno lanciati in quest'ordine e con quel margine.

## Cinema 4D / Octane

- Gli ID dei parametri di Octane sono fissati nel plugin (misurati con la diagnostica, C4D 2026): se
  una versione nuova li cambia, si rimisurano con *Extensions → HDRI Studio: Octane diagnostics*.
- Le luci separate hanno bisogno di una luce modello `HS_TEMPLATE` nella scena (Octane Area Light con
  un ImageTexture): senza, il plugin crea una luce di default e lo scrive in console.
- La **Power** va tarata una volta nella luce modello (*Surface brightness* attivo): è ancora aperta.

## Blender

- Il piano emissivo con Emission strength 1 ha la semantica della radianza: nessuna calibrazione.
  Verificato in Cycles, rapporto 1.002 contro la stessa luce dentro l'HDRI.

## Houdini

- `light_contribprimary` dell'`envlight` è **0 di default**: il dome illumina ma non si vede dalla
  camera. Il primo render di taratura è uscito nero per questo.
- Le grid light emettono lungo il proprio **−Z**: la base delle luci separate è (−R, U, F), destrorsa.
- `normalizearea` va **spento** perché intensità 1 significhi la radianza del pixel. Rapporto misurato
  con Karma: 0,984.
- Il ROP Karma ignora la risoluzione della camera: serve `override_camerares` + `resolutionx/y`.
- `hython` ha numpy, Pillow e **OpenImageIO**: per leggere pixel float da un EXR si usa OIIO, non PIL.

## macOS / Windows

- `tools/release.sh` usa `sed -i ''` (BSD): gira sul Mac, su Windows va adattato.
- La DLL della GDExtension si compila **dal Mac** in cross con mingw-w64; sul PC non serve toccarla.
- Su macOS, in una sessione automatica, dai un timeout agli smoke test
  (`perl -e 'alarm 240; exec @ARGV' …`) e **non** usare `pkill -f ui_smoke.gd` dalla stessa shell:
  uccide la shell (exit 144).
