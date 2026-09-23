# HDRI Studio Link — Houdini

Live link fra HDRI Studio e Houdini: l'HDRI si ricarica da sola a ogni modifica e le luci *separate*
diventano area light con la loro texture. Niente LightPaint, per ora.

Provato su Houdini 22.0.429 (macOS, Karma CPU). L'API usata è quella stabile di `hou`, quindi
dovrebbe andare anche su 20.x.

## Installazione

1. Copia `HDRIStudio.json` in `$HOUDINI_USER_PREF_DIR/packages/`
   (macOS: `~/Library/Preferences/houdini/22.0/packages/`, Windows: `%USERPROFILE%\Documents\houdini22.0\packages\`).
2. Aprilo e metti in `HDRI_STUDIO_LINK` il percorso di **questa** cartella (`plugins/houdini`).
3. Riavvia Houdini. In console compare `[hdri-studio] plugin 0.1 loaded da … (porta 47820)` e fra le
   shelf c'è **HDRI Studio** con tre pulsanti.

Il link parte da solo all'avvio e a ogni apertura di scena (`scripts/123.py` e `456.py`); il pulsante
*Live link on/off* lo stacca e riattacca.

## Uso

1. Nell'app: **Live link** → *Export file…* (un `.exr` dentro il progetto) → *Active*. Come software
   di export scegli **Houdini**.
2. In Houdini premi **Create HDRI environment**: nasce `/obj/HDRI_Studio_Environment`, un Environment
   Light con quell'EXR e *Contribute to Primary Rays* attivo (senza, il dome illumina ma non si vede
   dalla camera: è il default di Houdini, non un bug dell'app). Se l'HDRI ce l'hai già in scena, salta
   il pulsante: il plugin ricarica qualunque nodo usi quel file.
3. Da qui ogni modifica nell'app svuota la cache delle texture e ricarica i nodi: Karma nel viewport si
   aggiorna da solo. **Reload textures** fa la stessa cosa a mano su tutti gli EXR/HDR della scena.
4. Senza app collegata il plugin controlla ogni secondo la data di modifica dei file e ricarica quelli
   cambiati.

## Luci separate

Ogni luce con *Separate* nell'app diventa una **area light (grid)** dentro il subnet
`/obj/HDRI_Studio_Lights`, figlia del null `HDRI_Studio_Center` — sposta il null sul soggetto e le luci
lo seguono. Direzione, distanza (cm → m), dimensione fisica e texture arrivano dall'app.

Intensità 1 con *Normalize Light Intensity to Area* **spento**: così il valore del pixel della texture
è la radianza, come il piano emissivo in Blender. Verificato in Karma con
`tools/houdini_separate_verify.py`: la stessa luce dentro l'HDRI e come area light illuminano un piano
diffuso al centro con un rapporto di 0,984 (1,6% di scarto, dentro la tolleranza del test).

La texture non va specchiata: vista dal centro appare come nella mappa dell'app (verificato con un
quadrante luminoso di prova). L'opzione *Mirror texture* del pannello Live link serve a Cinema 4D.

## Orientamento

Misurato con `tools/houdini_calibrate.py` (HDRI di taratura con i dischi sugli assi, sei render stretti
con Karma): in Houdini il centro dell'immagine cade su **−Z** e il +X interno su **−X**, cioè una
rotazione di 180° attorno a Y, la stessa relazione che hanno Godot e Blender. Il punto bianco di
controllo (az +25°, el +12°) esce a destra e in alto come nel preview dell'app: niente specchio.
Da qui il preset **Houdini** dell'app: nessun flip, nessuno shift.

## Test (dal Mac, headless)

```
Godot --path hdri_studio -s res://tools/blender_link_host.gd -- --target Houdini
hython hdri_studio/tools/houdini_link_test.py

Godot --path hdri_studio -s res://tools/separate_verify_export.gd
hython hdri_studio/tools/houdini_separate_verify.py

hython hdri_studio/tools/houdini_calibrate.py    # rimisura l'orientamento
```
