#!/usr/bin/env bash
# Costruisce i pacchetti di HDRI Studio e pubblica una release su GitHub.
#
#   tools/release.sh 0.9.0                # esporta macOS + Windows, impacchetta, crea la release v0.9.0
#   tools/release.sh 0.9.0 --no-publish   # solo i pacchetti in dist/release/
#
# Richiede: Godot 4.7.1 con i template di export installati, gh autenticato. Va lanciato dalla
# radice del repository. Il numero di versione viene scritto in project.godot prima dell'export.
set -euo pipefail

VERSION="${1:?uso: tools/release.sh <versione> [--no-publish]}"
PUBLISH=1
[[ "${2:-}" == "--no-publish" ]] && PUBLISH=0

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="$ROOT/hdri_studio"
OUT="$ROOT/dist/release"
STAGE="$ROOT/dist/stage"

cd "$ROOT"
sed -i '' "s|^config/version=.*|config/version=\"$VERSION\"|" "$PROJ/project.godot"
grep -q "config/version=\"$VERSION\"" "$PROJ/project.godot" || { echo "versione non scritta"; exit 1; }

rm -rf "$OUT" "$STAGE"; mkdir -p "$OUT" "$STAGE/macOS" "$STAGE/Windows"

echo "== import"
"$GODOT" --headless --path "$PROJ" --import >/dev/null 2>&1 || true
echo "== export macOS"
if "$GODOT" --headless --path "$PROJ" --export-release "macOS" "$STAGE/macOS/HDRI Studio.app" 2>&1 | grep -iE "^error"; then exit 1; fi
echo "== export Windows"
if "$GODOT" --headless --path "$PROJ" --export-release "Windows" "$STAGE/Windows/HDRI Studio.exe" 2>&1 | grep -iE "^error"; then exit 1; fi

for os in macOS Windows; do
  cp -R "$PROJ/plugins" "$STAGE/$os/plugins"
  find "$STAGE/$os/plugins" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
  cp "$ROOT/GUIDA.md" "$ROOT/LICENSE" "$STAGE/$os/"
  (cd "$STAGE/$os" && zip -qry "$OUT/HDRI-Studio-$VERSION-$os.zip" .)
  echo "   $(du -h "$OUT/HDRI-Studio-$VERSION-$os.zip" | cut -f1)  HDRI-Studio-$VERSION-$os.zip"
done

echo "== self-test del build macOS"
# il primo avvio di un binario nuovo è lento (scansione di macOS): attende il risultato fino a 90 s
"$STAGE/macOS/HDRI Studio.app/Contents/MacOS/HDRI Studio" -- --selftest > "$OUT/selftest.log" 2>&1 &
APP_PID=$!
for i in $(seq 1 90); do
  grep -q "\[selftest\]" "$OUT/selftest.log" 2>/dev/null && break
  kill -0 "$APP_PID" 2>/dev/null || break
  sleep 1
done
kill "$APP_PID" 2>/dev/null || true
if grep -q "\[selftest\].*OK" "$OUT/selftest.log"; then echo "   OK ($i s)"; else echo "   FALLITO:"; cat "$OUT/selftest.log"; exit 1; fi

if [[ $PUBLISH -eq 1 ]]; then
  echo "== release v$VERSION su GitHub"
  git add "$PROJ/project.godot"
  git commit -q -m "Versione $VERSION" || true
  git push -q
  NOTES="HDRI Studio $VERSION — build di test.

Archivi per macOS (universal) e Windows (x86_64), con dentro l'app, la cartella \`plugins/\` (Cinema 4D, Blender e Houdini) e \`GUIDA.md\`.

- macOS: l'app non è firmata → tasto destro → Apri, oppure \`xattr -dr com.apple.quarantine \"HDRI Studio.app\"\`.
- Windows: SmartScreen → Ulteriori informazioni → Esegui comunque.

Segnalazioni: Issues di questo repository, o le sei domande in fondo alla guida."
  gh release create "v$VERSION" "$OUT"/HDRI-Studio-"$VERSION"-*.zip --title "HDRI Studio $VERSION" --notes "$NOTES"
  echo "   pubblicata: $(gh release view "v$VERSION" --json url -q .url)"
fi
echo "== fatto"
