# HDRI Studio — plugin per Cinema 4D

`hdri_studio_link/` è il plugin del live link. `octane_reload_probe.py` è la sonda usata in Fase 0
(Script Manager), non serve più una volta installato il plugin.

## Installazione

1. Cinema 4D → **Edit → Preferences → Plugins** → *Add Folder…* → scegli questa cartella (`plugins/c4d`,
   quella che contiene `hdri_studio_link/`).
2. Riavvia Cinema 4D. Nella console (Extensions → Console) compare `[hdri-studio] plugin caricato`.
3. Nel menu **Extensions** compare anche "HDRI Studio: ricarica texture", per ricaricare a mano.

## Uso

1. In HDRI Studio: pannello **Live link** → *File di export…* (scegli un `.exr`, per esempio nella cartella
   `tex/` del progetto C4D) → spunta *Attivo*.
2. In Cinema 4D carica quello stesso file in un ImageTexture di Octane (Octane Environment / tag).
3. Da qui ogni modifica in HDRI Studio riscrive il file (300 ms dopo l'ultimo cambiamento) e il plugin
   preme Reload sui nodi che lo usano. Nella console: `[hdri-studio] nome.exr → 1 nodi ricaricati`.

Se l'app non è aperta o non è collegata, il plugin controlla comunque ogni secondo la data di modifica
dei file immagine usati nella scena e ricarica quelli cambiati.

Porta TCP: 47820 su 127.0.0.1 (costante in `link_core.py` e in `livelink/live_link.gd`).
