# Convenzioni

## Lingua

- **Interfaccia in inglese nel codice.** Le stringhe visibili all'utente si scrivono in inglese: se una
  traduzione manca, il testo resta leggibile invece di sparire.
- **Italiano per commenti, docstring (`##`) e documentazione.**
- **Console, log CLI, `--selftest` e metadati EXR solo in inglese**: non sono interfaccia, non si
  traducono.

### Aggiungere una stringa nuova

1. Scrivila in inglese nel codice.
2. Aggiungi la coppia in `hdri_studio/core/lang_it.gd` (`"English": "Italiano"`). Il dizionario è
   ordinato per pannello, non alfabeticamente.
3. Se il testo è **statico** (`label.text`, `tooltip_text`, voci di un `OptionButton`, nome di una
   scheda) non serve altro: Godot lo ritraduce da solo al cambio di lingua.
4. Se è **composto a mano** (`%` o concatenazione) va passato da `tr()`, e il punto che lo ricalcola va
   aggiunto a `Main._retranslate()`, altrimenti resta nella lingua di prima finché non si riaggiorna.
5. Fuori da un `Node` (classi `RefCounted`) non c'è `tr()`: usa `TranslationServer.translate()`.
6. Lancia `i18n_smoke.gd`: controlla che ogni voce del dizionario venga applicata davvero.

La politica delle lingue: la scelta salvata in `settings.json` vince sempre; con `auto` (il default) si
segue la lingua del sistema, quindi italiano solo su un OS in italiano. Un codice sconosciuto ricade
sull'inglese.

## Codice GDScript

- Tipi statici ovunque (`var x := 1.0`, `func f(a: float) -> void`).
- L'interfaccia si costruisce **in codice**, dentro `_init()` dei pannelli: non ci sono `.tscn` a parte
  `main.tscn`, che è un nodo vuoto con lo script.
- I pannelli non conoscono `main`: comunicano con **segnali**. `main.gd` li collega tutti in
  `_build_layout()`.
- Un pannello per file in `ui/`. Le righe slider+spinbox si fanno con `ParamRow`.
- Docstring `##` sopra classi e funzioni non ovvie, con il *perché*, non il *cosa*. I commenti inline
  spiegano le scelte strane (una costante misurata, un aggiramento di un bug di Godot).
- Niente dipendenze nuove senza motivo: l'app deve restare "scarica Godot e parte".

## Python (plugin e strumenti)

- Stessa regola sulla lingua: stringhe visibili in inglese, commenti in italiano.
- `link_core.py` è **identico** nei tre plugin (C4D, Blender, Houdini): se ne cambi uno, copialo negli
  altri due.
- I plugin non devono mai far cadere il timer/event loop del software ospite: il polling sta dentro un
  `try/except` che stampa e tira avanti.

## Git

- Si lavora su `main`. `git pull` prima di iniziare, commit + push alla fine: il progetto si muove fra
  Mac e PC.
- Messaggi in italiano: prima riga imperativa e breve, poi il corpo che spiega *perché* e cosa è stato
  verificato. Chiudi con la riga `Co-Authored-By` di Claude, come nei commit precedenti.
- Non versionare artefatti: `dist/`, `hdri_studio/out/`, `.godot/` e `__pycache__/` sono nel
  `.gitignore`. Fanno eccezione, di proposito, `out/calibration.exr` (l'HDRI di taratura) e i binari
  della GDExtension in `addons/hs_openexr/bin/`.
- I file `.uid` che Godot genera accanto agli script **vanno committati**.

## Cosa aggiornare quando

| Se tocchi… | Aggiorna anche |
|---|---|
| Una funzione dell'app | `GUIDA.md` se cambia l'uso, `hdri_studio/README.md` se cambia una schermata |
| Un plugin | il README di quel plugin, e `GUIDA.md` se cambiano i nomi dei comandi |
| Qualsiasi pezzo di lavoro chiuso | `PIANO.md` (sezione + decisione datata) e `docs/stato.md` |
| Una stringa dell'interfaccia | `core/lang_it.gd` |
| `bake/bake.glsl` | `python3 hdri_studio/tools/embed_shader.py` |
