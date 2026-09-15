# HDRI Studio — add-on per Blender

`hdri_studio_link/` è l'add-on del live link (`__init__.py` + `link_core.py`, quest'ultimo è una copia
identica di quello del plugin C4D: se cambia uno, cambia l'altro).

## Installazione

Zippa la cartella `hdri_studio_link/` (o usa lo zip in una release), poi **Edit → Preferences → Add-ons
→ Install…** → scegli lo zip → attiva *HDRI Studio Link*. In alternativa copia la cartella in
`scripts/addons/` di Blender. Nella console di sistema compare `[hdri-studio] add-on … caricato`.

Nel viewport 3D, sidebar (N) → tab **HDRI Studio**: stato del collegamento, LightPaint, Ricarica
texture, visibilità in camera delle luci separate.

## Uso

1. In HDRI Studio: pannello **Export → Software: Godot / Blender**; pannello **Live link** → *File di
   export…* → *Attivo*.
2. In Blender carica lo stesso EXR nell'Environment Texture del World. A ogni modifica nell'app
   l'immagine viene ricaricata (`image.reload()`), Cycles ed EEVEE la rileggono da soli.
3. **LightPaint**: pulsante nel pannello, poi click o trascina sul modello nel viewport; Esc o tasto
   destro per uscire. Normali interpolate sulle mesh smooth.
4. **Luci separate**: ogni luce con il flag *Separata* nell'app diventa un piano emissivo (Emission
   strength 1 + l'EXR planare) nella collezione `HDRI Studio Lights`, figlio dell'empty `HDRI Studio
   Center` (spostalo sul soggetto: i piani seguono). Direzione, distanza (cm → m), dimensione fisica e
   texture sono automatiche. Verificato in Cycles: il piano illumina il centro come la stessa luce
   nell'HDRI (rapporto 1.002). *Luci separate visibili in camera* nel pannello le nasconde alla camera
   lasciandole nei riflessi e nell'illuminazione.

Senza app collegata, l'add-on controlla ogni secondo la data di modifica dei file EXR/HDR usati nella
scena e ricarica quelli cambiati.

## Test (dal Mac, headless)

    /Applications/Godot.app/Contents/MacOS/Godot --path hdri_studio -s res://tools/blender_link_host.gd &
    /Applications/Blender.app/Contents/MacOS/Blender -b --python hdri_studio/tools/blender_link_test.py

    /Applications/Godot.app/Contents/MacOS/Godot --path hdri_studio -s res://tools/separate_verify_export.gd
    /Applications/Blender.app/Contents/MacOS/Blender -b --python hdri_studio/tools/blender_separate_verify.py
