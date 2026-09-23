# Documentazione di lavoro

Questa cartella è il passaggio di consegne fra una macchina e l'altra: quello che serve a chi (o a
Claude) riprende il progetto senza aver seguito le sessioni precedenti.

| File | Cosa c'è dentro |
|---|---|
| [stato.md](stato.md) | Dove siamo, cosa è chiuso, cosa è aperto e su quale macchina si può fare |
| [setup.md](setup.md) | Far girare tutto su una macchina nuova: Godot, Python, i tre plugin (Windows e macOS) |
| [test.md](test.md) | Tutti i comandi di verifica, nelle due versioni PowerShell e shell |
| [architettura.md](architettura.md) | Mappa dei moduli, flusso dei dati, dove mettere le mani |
| [convenzioni.md](convenzioni.md) | Lingua, stile, i18n, commit, cosa aggiornare quando |
| [trappole.md](trappole.md) | Le cose che fanno perdere un'ora, imparate a caro prezzo |

Fuori da qui: [`PIANO.md`](../PIANO.md) è il diario del progetto (storia, misure, decisioni datate),
[`GUIDA.md`](../GUIDA.md) è la guida per chi prova l'app, `hdri_studio/README.md` descrive l'uso
dell'app funzione per funzione, e ogni plugin ha il suo README in `hdri_studio/plugins/*/`.

## Primo avvio su una macchina nuova

1. `git clone https://github.com/lignazio/hdri-studio.git` (o `git pull` se il clone c'è già:
   **sempre prima di iniziare**, il progetto si muove fra Mac e PC).
2. Installa quello che serve seguendo [setup.md](setup.md) — come minimo Godot 4.7.1.
3. Costruisci la cache del progetto: `<godot> --headless --path hdri_studio --import`.
4. Lancia lo smoke test dell'app ([test.md](test.md)): se stampa `TUTTO OK` la macchina è a posto,
   estensione OpenEXR compresa.
5. Leggi [stato.md](stato.md) e scegli da lì.

## Cosa è specifico di una macchina

- **Mac** (M1 Pro): Godot, Blender, Houdini 22, toolchain C++ per la GDExtension (anche la DLL
  Windows si compila da qui, in cross con mingw-w64). Non ha Cinema 4D.
- **PC Windows**: Cinema 4D + Octane. Qui si fanno le prove che sul Mac non si possono fare —
  calibrazione della Power di Octane, verso e specchio della texture, plugin C4D.

Se un lavoro richiede l'altra macchina, in [stato.md](stato.md) è scritto quale.
