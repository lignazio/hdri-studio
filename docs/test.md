# Verifiche

Nessuna modifica si dà per buona senza aver lanciato il test che la copre. Tutti i test stampano
`TUTTO OK` o `FALLITO` come ultima riga ed escono con codice 0 o 1.

I comandi qui sotto vanno lanciati **dalla radice del repository**, con `$env:GODOT` (PowerShell) o
`$GODOT` (shell) impostato come in [setup.md](setup.md).

## I test dell'app

| Test | Cosa copre |
|---|---|
| `ui_smoke.gd` | Il grosso: aggiungi/duplica/elimina, slider, mappa, LightPaint, catalogo, preset, undo, export EXR/HDR/ACEScg, metadati, riordino della lista, luce bloccata, esposimetro, materiali. È quello da lanciare sempre. |
| `i18n_smoke.gd` | Lingue: politica auto/esplicita, dizionario italiano applicato, barra di stato ritradotta, selettore che ricorda la scelta. |
| `sky_smoke.gd` | Che la sfera diffusa del preview segua i cambiamenti del rig (con luci → senza → di nuovo con luci). |
| `exr_smoke.gd` | 10 codec EXR × half/float32: scrittura, rilettura, errore massimo, metadati. Headless, richiede l'estensione. |
| `link_smoke.gd` | Il server del live link, con un client Python in parallelo (`plugins/c4d/hdri_studio_link/link_core.py`). |
| `fase0_spike.gd` | Rigenera le HDRI di prova in `out/` (taratura, furnace, forme, studio). |

```powershell
& $env:GODOT --path hdri_studio -s res://tools/ui_smoke.gd -- --fresh
& $env:GODOT --path hdri_studio -s res://tools/i18n_smoke.gd
& $env:GODOT --headless --path hdri_studio -s res://tools/exr_smoke.gd
```

L'app esportata ha un autotest suo: `"HDRI Studio.console.exe" -- --selftest` (Windows) o
`"HDRI Studio.app/Contents/MacOS/HDRI Studio" -- --selftest` (macOS): bake, export, rilettura e stato
della libreria EXR, con il risultato anche in `%APPDATA%\Godot\app_userdata\HDRI Studio\selftest.log`.

## I test dei plugin

Sono a due processi: prima l'app fa da host, poi il software 3D si collega. L'host resta in ascolto 25
secondi, quindi lancialo in background e poi lancia il test.

```powershell
# Blender
Start-Process -NoNewWindow $env:GODOT "--path hdri_studio -s res://tools/blender_link_host.gd"
& "C:\Program Files\Blender Foundation\Blender 4.2\blender.exe" -b --python hdri_studio\tools\blender_link_test.py

# Houdini (stesso host, preset diverso)
Start-Process -NoNewWindow $env:GODOT "--path hdri_studio -s res://tools/blender_link_host.gd -- --target Houdini"
& $HYTHON hdri_studio\tools\houdini_link_test.py
```

Verifiche fisiche delle luci separate (prima l'app scrive la coppia di EXR, poi il renderer misura):

```powershell
& $env:GODOT --path hdri_studio -s res://tools/separate_verify_export.gd
& $BLENDER -b --python hdri_studio\tools\blender_separate_verify.py   # Cycles, rapporto atteso ~1.002
& $HYTHON hdri_studio\tools\houdini_separate_verify.py                # Karma, rapporto misurato 0.984
```

Orientamento in Houdini (rimisura il preset): `& $HYTHON hdri_studio\tools\houdini_calibrate.py`.

## Prove a occhio

```powershell
& $env:GODOT --path hdri_studio -- --screenshot     # scrive out\app.png e chiude
```

Export da riga di comando, senza toccare l'interfaccia:

```powershell
& $env:GODOT --path hdri_studio -- --rig <file.json|.exr> --export <file.exr|.hdr> [--res 4096x2048] [--target "Houdini"]
```

## Trappole dei test

- Su macOS conviene mettere un timeout (`perl -e 'alarm 240; exec @ARGV' ...`) perché uno smoke test
  che si pianta blocca la sessione; **non** usare `pkill -f ui_smoke.gd` dalla stessa shell: uccide la
  shell (exit 144). Su Windows, se un processo resta appeso: `Stop-Process -Name Godot* -Force`.
- `ui_smoke` controlla che `bake_glsl_source.gd` sia allineato a `bake.glsl`: se fallisce lì, lancia
  `python3 hdri_studio/tools/embed_shader.py`.
- Se un test si lamenta di una classe che non esiste, manca l'`--headless --import` dopo il pull.
- `exr_smoke` stampa errori attesi di TinyEXR sui codec che Godot non sa leggere: conta l'ultima riga.
