# HDRI Studio — guida rapida per chi prova

HDRI Studio è un'app che costruisce **HDRI da studio** a partire da luci parametriche disposte su una
sfera a 360°: le luci si spostano in tempo reale, il risultato si vede su tre sfere di prova (cromata,
glossy, diffusa) e si esporta come EXR lineare fisicamente corretto. Con il **live link** l'HDRI si
aggiorna dentro Cinema 4D (Octane) o Blender mentre lavori, e con il **LightPaint** clicchi sul modello
nel software 3D e la luce va dove serve per produrre quel riflesso.

## 1. Installazione

**Strada semplice — l'app già pronta.** Scarica dalla pagina *Releases* del repository l'archivio per
il tuo sistema (`HDRI-Studio-<versione>-macOS.zip` o `-Windows.zip`), scompattalo: dentro trovi l'app,
la cartella `plugins/` (C4D e Blender) e questa guida.

- **macOS**: l'app non è firmata, quindi la prima volta macOS la blocca ("sviluppatore non
  identificato"). Tasto destro sull'app → *Apri* → *Apri* di nuovo; oppure da Terminale
  `xattr -dr com.apple.quarantine "HDRI Studio.app"`. Serve una sola volta.
- **Windows**: SmartScreen avvisa "editore sconosciuto" → *Ulteriori informazioni → Esegui comunque*.
  Se vedi tutto nero, lancia `HDRI Studio.console.exe` (accanto all'exe) e riporta le righe che
  iniziano con `Baker:` o `ERROR`.

All'avvio la riga di stato del pannello Export dice `OpenEXR 3.4.9 caricata`: se invece dice
"non caricata", segnalalo. Auto-test da terminale (bake, export, rilettura, libreria EXR):
macOS `"HDRI Studio.app/Contents/MacOS/HDRI Studio" -- --selftest`; Windows, da PowerShell nella
cartella dell'app, `& ".\HDRI Studio.console.exe" --% -- --selftest` (da cmd: `"HDRI Studio.console.exe" -- --selftest`).
Il risultato è anche in `%APPDATA%\Godot\app_userdata\HDRI Studio\selftest.log`
(macOS: `~/Library/Application Support/Godot/app_userdata/HDRI Studio/selftest.log`).

**Strada per chi vuole il codice.** Serve Godot 4.7.1 (godotengine.org → Download → versione *Standard*,
non .NET): clona il repository, apri Godot → *Import* → `hdri_studio/project.godot` → **Play (F5)**. Il
primo avvio rigenera la cache in qualche secondo.

Gli EXR (tutti i codec, DWAA/DWAB compresi) li scrive e legge l'app da sola, con OpenEXR incluso:
Blender serve solo se vuoi il live link con Blender.

## 2. La finestra

Al primo avvio si apre grande, quasi tutto lo schermo. Da lì in poi ricorda com'era quando l'hai
chiusa — dimensione, posizione e se era massimizzata — e si riapre così. Se cambi monitor e la
posizione salvata non esiste più, torna al comportamento del primo avvio invece di aprirsi fuori
schermo.

Tre colonne, ridimensionabili trascinando i bordi.

| Sinistra | Centro | Destra |
|---|---|---|
| **Luci**: elenco con le icone di stato per riga (occhio = visibile, pallino = solo, lucchetto = bloccata; bianca = attiva, grigia = off), aggiungi / duplica / elimina / ⇋ specchia / ▲▼ o drag & drop per riordinare, pannello proprietà della luce selezionata | **Preview 3D**: tre sfere (o il tuo modello GLB) illuminate dall'HDRI · sotto, la **mappa** equirettangolare con le maniglie delle luci | **Set** (ruota tutto) · **Sfondo** · **Export** · **Live link** · **Preview** (esposizione, clipping, esposimetro) · **Modello nel preview** |
| **Catalogo**: la tua cartella di HDRI light con miniature, tag, preferiti | | |
| **Preset**: rig salvati come libreria | | |

La barra in basso mostra az/el e il valore RGB del pixel sotto il cursore sulla mappa.

**Lingua.** L'app è in inglese; in fondo alla colonna destra c'è *Language*: **Automatic (system)**
(default) la mette in italiano se il sistema è in italiano e in inglese in tutti gli altri casi,
**English** e **Italiano** la forzano. Il cambio è immediato e viene ricordato. Le schermate di questa
guida e i nomi dei pannelli qui sotto sono quelli italiani.

## 3. Primi cinque minuti

1. All'avvio c'è un set di prova (key scrim, fill, rim, top ring). Seleziona **Key scrim** nell'elenco
   e trascina la sua maniglia sulla mappa: le sfere seguono in tempo reale.
2. Nel pannello proprietà prova *Larghezza*, *Sfumatura*, *Angoli*, *Kelvin* (o i pulsanti 3200 / 5600),
   *Intensità*. Ogni parametro si applica al volo.
3. **Shift + trascina sulla sfera cromata**: la luce selezionata si sposta dove serve per riflettersi
   sotto il cursore (LightPaint). **Click** semplice su un riflesso: seleziona la luce che lo produce.
4. *+ Aggiungi* → scegli una forma: **Rettangolo**, **Ellisse**, **Anello**, **Gradiente** (radiale o
   lineare, con tacche colorate), **Scrim** (telo con la sorgente dietro: hotspot fisico), **Texture**
   (un'immagine EXR/HDR di una luce vera).
5. **Esporta EXR…** nel pannello Export: 4k×2k, half, preset *Cinema 4D + Octane* (o *Godot / Blender*).
   Il file è radianza lineare, primari Rec.709, e porta dentro il rig: *Apri rig…* lo rilegge da lì
   (vale anche per l'export `.hdr`, quindi il progetto si riapre da qualunque HDRI esportata).

## 4. Le cose da sapere

- **Fusione**: *Somma* è quella fisica. *Normale* fa coprire la luce (con le sue parti scure) a quello
  che c'è sotto: per pannelli con un corpo dietro e per le HDRI light con il proprio fondo. Con Normale
  l'ordine dell'elenco conta (chi sta sotto copre): riordina trascinando o con ▲▼.
- **Fotometrico**: spunta *Fotometrico* e la luce è definita dall'illuminamento al centro invece che
  dalla radianza: allargandola diventa più morbida, non più forte. L'**esposimetro** (pannello Preview)
  dice quanto illumina tutto il set in una direzione, in E e EV100.
- **Sfondo**: nero / colore / gradiente, oppure un'HDRI esistente da "aumentare" con le luci
  (rotazione, EV, *Sfocatura* per tenere solo la dominante).
- **Catalogo**: *Cartella…* → la tua collezione. Click su una miniatura inserisce la luce; trascinala
  sulla mappa (nasce lì) o sul preview (nasce sul riflesso). Tasto destro: ★ preferito, tag. Sidecar
  `nome.json` accanto a un'immagine = default della luce; *Salva default* lo scrive dalla luce corrente.
- **Luci separate** (⇗): escluse dall'HDRI, esportate come EXR planare e ricreate nel software 3D come
  area light alla distanza scelta. In C4D serve una luce modello `HS_TEMPLATE` (Octane Area Light con
  un ImageTexture); in Blender diventano piani emissivi.
- **Undo** ⌘Z / ⇧⌘Z. L'app riapre l'ultimo rig e fa un autosave al minuto.

## 5. Live link con Cinema 4D (Octane)

1. C4D → *Edit → Preferences → Plugins → Add Folder…* → `hdri_studio/plugins/c4d` → riavvia. In
   console: `[hdri-studio] plugin … caricato`.
2. Nell'app: pannello **Live link** → *File di export…* (un `.exr` nella cartella `tex/` del progetto) →
   *Attivo*. Lo stato deve dire "1 client (c4d …)".
3. In C4D carica quello stesso file nell'ImageTexture dell'Octane Environment. Da qui ogni modifica
   nell'app aggiorna il Live Viewer da sola (il plugin preme *Reload* per te).
4. **LightPaint da C4D**: tool *HDRI Studio LightPaint* (menu Extensions, o Shift+C) → click o trascina
   sul modello. **Camera dal live link** (pannello Preview): il preview segue l'inquadratura di C4D.

## 6. Live link con Blender

*Edit → Preferences → Add-ons → Install…* → zip della cartella `hdri_studio/plugins/blender/hdri_studio_link`
→ attiva. Sidebar N → tab *HDRI Studio*: stato, LightPaint, *Reload textures*. Nell'app scegli *Godot / Blender*
come software di export. Il reload è automatico, le luci separate diventano piani emissivi
(calibrazione zero: strength 1 = valore del pixel).

## 7. Live link con Houdini

Copia `plugins/houdini/HDRIStudio.json` in `$HOUDINI_USER_PREF_DIR/packages/`, dentro metti il percorso
di `plugins/houdini` e riavvia: compare la shelf *HDRI Studio*. Nell'app scegli **Houdini** come
software di export, attiva il live link, poi in Houdini premi *Create HDRI environment*. Da lì ogni
modifica ricarica l'HDRI da sola e le luci separate diventano area light dentro
`/obj/HDRI_Studio_Lights`. Non c'è il LightPaint. Dettagli in `plugins/houdini/README.md`.

## 8. Tastiera

| Tasto | Azione |
|---|---|
| Frecce / Shift+frecce | sposta le luci selezionate di 1° / 10° |
| H | accende/spegne le selezionate |
| ⌘D · Canc | duplica · elimina |
| Q / E | esposizione del preview (solo visualizzazione) |
| ⌘Z · ⇧⌘Z | undo · redo |
| Shift + trascina (3D) | LightPaint |
| Tasto destro (3D) | ruota il modello caricato |
| Rotella (3D) | zoom |

## 9. Cosa ci interessa sapere da te

Segnala per favore, anche in due righe ciascuna:

1. **Prima impressione**: cosa non hai capito senza leggere questa guida?
2. **Fisica**: metti la stessa luce una volta nell'HDRI e una volta come luce separata: illumina uguale?
   L'esposimetro ti torna con il render?
3. **Live link**: si aggiorna sempre? Con che ritardo? Ti è mai rimasto indietro o bloccato?
4. **LightPaint**: il riflesso finisce dove clicchi? Su mesh poco suddivise salta?
5. **Catalogo**: la tua collezione si apre tutta? Le miniature sono leggibili (prova *Miniature EV*)?
6. **Cosa manca** per usarla su un lavoro vero, e cosa faresti diversamente rispetto a HDR Light Studio.

Per ogni problema: sistema operativo, cosa stavi facendo, cosa ti aspettavi, e se possibile il rig
(*Salva rig…*) o l'EXR esportato (contiene il rig). Le righe della console di C4D, Blender o Houdini che
iniziano con `[hdri-studio]` sono d'oro.

## 10. Limiti noti

- In C4D la Power delle luci separate va tarata una volta nella luce modello (*Surface brightness* on,
  furnace test); in Blender no.
- L'output è Rec.709 lineare; nel pannello Export puoi scegliere ACEScg (con i metadati AP1/D60).
