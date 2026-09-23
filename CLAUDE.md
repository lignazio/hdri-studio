# HDRI Studio — istruzioni per Claude

App desktop in **Godot 4.7.1** che costruisce HDRI da studio: luci parametriche su una sfera a 360°,
bake su GPU (compute shader), export EXR/HDR lineare fisicamente corretto e **live link** verso Cinema
4D (Octane), Blender e Houdini. Repo privato `lignazio/hdri-studio`, ramo `main`, sincronizzato fra un
Mac e un PC Windows.

## Leggi in quest'ordine, prima di toccare il codice

1. `docs/README.md` — indice della documentazione e primo avvio su una macchina nuova.
2. `docs/stato.md` — dove siamo, cosa è chiuso, cosa è aperto e su quale macchina si può fare.
3. `docs/convenzioni.md` — come è scritto questo codice (lingua, stile, i18n, commit).
4. `docs/test.md` — i comandi di verifica, prima di dire che una cosa funziona.

`PIANO.md` è il diario del progetto: 50 KB di storia e decisioni datate. Cercaci dentro quello che ti
serve, non leggerlo tutto.

## Regole del progetto

- **Lingua**: le stringhe dell'interfaccia sono in **inglese** nel codice, l'italiano è una traduzione
  in `hdri_studio/core/lang_it.gd`. Commenti, docstring e documentazione in **italiano**. Ogni stringa
  nuova visibile all'utente va aggiunta al dizionario: vedi `docs/convenzioni.md`.
- **Niente "fatto" senza prova**: ogni modifica si chiude lanciando il test che la copre
  (`docs/test.md`). Se un test non si può lanciare su questa macchina, dillo esplicitamente invece di
  darlo per buono.
- Dopo aver aggiunto uno script con `class_name`: `--headless --import`.
- Dopo aver modificato `bake/bake.glsl`: `python3 hdri_studio/tools/embed_shader.py` (l'app esportata usa la copia
  incorporata in `bake_glsl_source.gd`, e `ui_smoke` controlla che siano allineate).
- **Git**: `git pull` prima di iniziare, commit + push alla fine. Messaggi in italiano, prima riga
  imperativa e breve, corpo che spiega il perché; chiudi con la riga `Co-Authored-By` di Claude come
  nei commit precedenti. Non creare branch se non te lo chiedono: si lavora su `main`.
- Quando chiudi un pezzo di lavoro aggiorna **`PIANO.md`** (sezione dei lavori + una decisione datata)
  e **`docs/stato.md`**. Se tocchi l'interfaccia, guarda anche `GUIDA.md` (la guida per chi prova
  l'app) e i README dei plugin.
- `dist/`, `hdri_studio/out/` e `.godot/` non sono versionati: gli artefatti non viaggiano fra le
  macchine, si rigenerano.
