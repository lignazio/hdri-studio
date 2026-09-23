# Stato del progetto

Aggiornato il **23 settembre 2026**, versione app **0.9.1**. La storia completa, con le misure e le
decisioni datate, è in [`PIANO.md`](../PIANO.md); qui c'è solo quello che serve per decidere cosa fare
adesso.

## Cosa c'è e funziona

- **App** (`hdri_studio/`): luci parametriche (rettangolo, ellisse, anello, gradiente, scrim, texture),
  bake su GPU in equirettangolare, preview 3D con tre sfere o un modello GLB, mappa con maniglie,
  catalogo di HDRI light con tag e preferiti, libreria di preset, undo, autosave, modalità fotometrica
  validata contro Cycles, esposimetro, clipping, LightPaint.
- **Export**: EXR (tutti i codec, via la GDExtension `HsOpenEXR` inclusa nel repo) e Radiance `.hdr`,
  half o float32, Rec.709 o ACEScg, metadati con il rig dentro il file — un EXR o un `.hdr` esportato
  si riapre come rig. Preset di orientamento per software, tutti misurati con l'HDRI di taratura.
- **Live link** (TCP 127.0.0.1:47820, JSON-lines): plugin per **Cinema 4D + Octane**, **Blender** e
  **Houdini**. Ricarica dell'HDRI a ogni modifica, luci separate ricreate come luci vere nel software
  3D, LightPaint dal viewport (C4D e Blender).
- **Finestra**: al primo avvio quasi tutto lo schermo (92% dell'area utile, centrata), poi ricorda
  dimensione, posizione e stato massimizzato in `settings.json`. Test e riga di comando restano ai
  1600×900 del progetto, così le verifiche misurano sempre la stessa finestra.
- **Interfaccia bilingue**: inglese di base, italiano automatico se il sistema è in italiano,
  selettore *Language* in fondo alla colonna destra.
- **Icona e boot splash** generati da script (`tools/make_icon.py`, `tools/make_splash.py`).

## Aperto

| Cosa | Dove si fa | Note |
|---|---|---|
| Calibrazione della **Power di Octane** per le luci separate | PC (C4D + Octane) | La luce modello `HS_TEMPLATE` va tarata una volta con un furnace test. È l'ultima voce fisica non chiusa. |
| Verso e **specchio della texture** delle luci separate in Octane | PC | Le due spunte nel pannello Live link esistono già: serve solo stabilire quali sono giuste e farle diventare il default. |
| Plugin C4D, stringhe in inglese | PC | Tradotto il 23/09 e controllato solo sintatticamente: sul Mac non c'è Cinema 4D. Da riaprire una volta in C4D per vedere menu e dialoghi. |
| Houdini: prova su una **scena vera** | Mac o PC (Houdini) | Il link è verificato end-to-end ma solo headless, con Karma CPU. |
| Houdini: **LightPaint** | Mac o PC | Escluso di proposito dal primo plugin: il picking nel viewport di Houdini è più indiretto che in Blender e C4D. |
| **Redshift** | macchina con Redshift installato | Vedi sotto. |
| Rendere il plugin Houdini installabile senza editare a mano il JSON | ovunque | Oggi `HDRIStudio.json` va aperto e corretto col percorso della cartella. |

### Redshift, in dettaglio

Sul Mac non è installato (in Houdini 22 non esiste nessun node type `rs*`, né OBJ né ROP). Se lo si
vuole supportare, **non basta il plugin Houdini che c'è**: è la stessa spaccatura che esiste in Cinema
4D fra Octane e il renderer nativo.

- Si porta dietro così com'è: il link (protocollo, avvio, shelf, watcher sulle date dei file) e, quasi
  certamente, il reload — il plugin cerca qualunque parametro di tipo file che punti all'EXR, quindi
  troverebbe anche il `tex0` di una dome light Redshift. Dubbio: Redshift ha una cache texture sua che
  `texcache -c` non tocca, serve il suo flush.
- Va rifatto: la **misura dell'orientamento** (le dome light Redshift hanno la loro rotazione di
  default: probabilmente nasce un preset *Houdini + Redshift* separato), la **creazione delle luci
  separate** (`rslight` con i suoi parametri invece di `hlight::2.0`) e la **calibrazione
  dell'intensità** (unità e normalizzazione diverse: il rapporto 0,984 misurato con Karma non vale).
- Costo stimato: una sessione sul plugin più due misure, su una macchina con Redshift.

## Le tre macchine di prova

- **Mac** (M1 Pro, macOS 15.7): Godot 4.7.1, Blender 5.1.1, Houdini 22.0.429, toolchain C++ per la
  GDExtension (compila anche la DLL Windows in cross con mingw-w64). Niente Cinema 4D.
- **PC Windows**: Cinema 4D 2025/2026 + Octane. La DLL `HsOpenEXR` è stata verificata qui il 17/09.
- I plugin si installano puntando alla cartella del repository, così un `git pull` li aggiorna.
