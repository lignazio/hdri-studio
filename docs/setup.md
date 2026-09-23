# Setup di una macchina

## Godot (obbligatorio)

**Godot 4.7.1, versione Standard** (non .NET), da godotengine.org. Non serve altro per far girare
l'app: l'estensione OpenEXR è già compilata dentro il repo (`hdri_studio/addons/hs_openexr/bin/`, dylib
universale per macOS e DLL x86_64 per Windows).

Conviene mettere il percorso dell'eseguibile in una variabile, perché tutti i comandi di
[test.md](test.md) lo usano:

```powershell
# Windows, PowerShell — adatta il percorso a dove hai scompattato Godot
$env:GODOT = "C:\Tools\Godot_v4.7.1-stable_win64.exe"
& $env:GODOT --headless --path hdri_studio --import
```

```bash
# macOS
export GODOT=/Applications/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path hdri_studio --import
```

L'`--import` costruisce `.godot/` (cache e class name): va rifatto dopo ogni `git pull` che aggiunge
script con `class_name`, altrimenti Godot non li trova.

Per aprire l'app a mano: `& $env:GODOT --path hdri_studio` (oppure apri `hdri_studio/project.godot`
dall'editor e premi F5).

Per esportare i pacchetti servono anche i **template di export** della 4.7.1 (Editor → Manage Export
Templates). `tools/release.sh` è uno script bash con `sed -i ''` alla BSD: gira sul Mac, su Windows va
lanciato da Git Bash e la riga del `sed` va adattata.

## Python (per gli strumenti)

Serve Python 3 con **Pillow** e **numpy**, usati da `tools/make_icon.py`, `tools/make_splash.py` e
`hdri_studio/tools/embed_shader.py` (quest'ultimo solo standard library).

```powershell
python -m pip install pillow numpy
```

## Cinema 4D (solo PC)

Edit → Preferences → Plugins → *Add Folder…* → `hdri_studio\plugins\c4d` (la cartella che contiene
`hdri_studio_link\`), poi riavvia. Punta alla cartella del repository, non copiarla: così ogni pull
aggiorna il plugin. Dettagli e uso in [`plugins/c4d/README.md`](../hdri_studio/plugins/c4d/README.md).

## Blender

Edit → Preferences → Add-ons → Install… → lo zip di `hdri_studio/plugins/blender/hdri_studio_link/`,
poi attiva *HDRI Studio Link*. Dettagli in
[`plugins/blender/README.md`](../hdri_studio/plugins/blender/README.md).

## Houdini

Copia `hdri_studio/plugins/houdini/HDRIStudio.json` in `$HOUDINI_USER_PREF_DIR/packages/`
(Windows: `%USERPROFILE%\Documents\houdini22.0\packages\`, macOS:
`~/Library/Preferences/houdini/22.0/packages/`) e dentro metti il percorso della cartella
`plugins/houdini`. Dettagli in [`plugins/houdini/README.md`](../hdri_studio/plugins/houdini/README.md).

`hython` serve per i test headless di Houdini:

- Windows: `C:\Program Files\Side Effects Software\Houdini 22.0.429\bin\hython.exe`
- macOS: `/Applications/Houdini/Houdini22.0.429/Frameworks/Houdini.framework/Versions/22.0/Resources/bin/hython`

## GDExtension OpenEXR (solo se la si deve ricompilare)

Sorgenti in `gdextension/`, build con `tools/build_gdextension.sh [macos|windows]` **dal Mac**: compila
OpenEXR 3.4.9 statico e l'estensione con godot-cpp, e per Windows fa cross-compiling con `mingw-w64`
(`brew install mingw-w64`). I binari risultanti sono committati, quindi sul PC non serve toccarla:
si ricompila solo se cambia il C++ in `gdextension/src/`.

Se l'estensione non si carica, l'app continua a funzionare ma scrive solo EXR PIZ (fallback TinyEXR di
Godot): la riga di stato del pannello Export lo dice all'avvio.
