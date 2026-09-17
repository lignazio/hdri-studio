#!/usr/bin/env bash
# Compila la GDExtension HsOpenEXR (OpenEXR dentro Godot) e la copia in hdri_studio/addons/hs_openexr/bin.
#
#   tools/build_gdextension.sh            # macOS universal + Windows x86_64 (mingw)
#   tools/build_gdextension.sh macos      # solo una piattaforma
#   tools/build_gdextension.sh windows
#
# Richiede: cmake ≥ 3.24, Xcode CLT; per Windows `brew install mingw-w64`. Scarica OpenEXR 3.4.9 (e Imath
# tramite il suo CMake) e godot-cpp al primo avvio; tutto finisce in gdextension/build/ (ignorata da git).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GD="$ROOT/gdextension"
BUILD="$GD/build"
BIN="$ROOT/hdri_studio/addons/hs_openexr/bin"
OPENEXR_VERSION="3.4.9"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || nproc)"
PLATFORMS="${1:-macos windows}"

mkdir -p "$BUILD" "$BIN"
if [[ ! -d "$BUILD/openexr-src" ]]; then
  echo "== scarico OpenEXR $OPENEXR_VERSION"
  curl -sL "https://github.com/AcademySoftwareFoundation/openexr/archive/refs/tags/v$OPENEXR_VERSION.tar.gz" -o "$BUILD/openexr.tgz"
  tar xzf "$BUILD/openexr.tgz" -C "$BUILD" && mv "$BUILD/openexr-$OPENEXR_VERSION" "$BUILD/openexr-src"
fi

build_one() {
  local plat="$1"; shift
  local dir="$BUILD/$plat"
  local prefix="$dir/prefix"
  mkdir -p "$dir"
  echo "== OpenEXR statico ($plat)"
  cmake -S "$BUILD/openexr-src" -B "$dir/openexr" "$@" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF \
    -DOPENEXR_BUILD_TOOLS=OFF -DOPENEXR_INSTALL_TOOLS=OFF -DOPENEXR_BUILD_EXAMPLES=OFF \
    -DOPENEXR_INSTALL_PKG_CONFIG=OFF -DOPENEXR_BUILD_PYTHON=OFF \
    -DOPENEXR_FORCE_INTERNAL_IMATH=ON -DOPENEXR_FORCE_INTERNAL_DEFLATE=ON -DOPENEXR_FORCE_INTERNAL_OPENJPH=ON \
    -DIMATH_INSTALL_PKG_CONFIG=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON >"$dir/openexr-configure.log" 2>&1 \
    || { tail -30 "$dir/openexr-configure.log"; exit 1; }
  cmake --build "$dir/openexr" -j"$JOBS" --target install >"$dir/openexr-build.log" 2>&1 \
    || { tail -30 "$dir/openexr-build.log"; exit 1; }
  cp "$dir/openexr/external/OpenJPH/src/core/libopenjph.a" "$prefix/lib/"
  echo "== GDExtension ($plat)"
  cmake -S "$GD" -B "$dir/ext" "$@" -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$prefix" \
    >"$dir/ext-configure.log" 2>&1 || { tail -30 "$dir/ext-configure.log"; exit 1; }
  cmake --build "$dir/ext" -j"$JOBS" >"$dir/ext-build.log" 2>&1 || { tail -30 "$dir/ext-build.log"; exit 1; }
  cp "$dir/ext/out/"*hs_openexr.* "$BIN/"
}

for p in $PLATFORMS; do
  case "$p" in
    macos)
      build_one macos -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0
      ;;
    windows)
      command -v x86_64-w64-mingw32-g++ >/dev/null || { echo "manca mingw-w64: brew install mingw-w64"; exit 1; }
      build_one windows -DCMAKE_TOOLCHAIN_FILE="$GD/mingw-x86_64.cmake"
      ;;
    *) echo "piattaforma sconosciuta: $p"; exit 1;;
  esac
done
echo "== binari in $BIN"
ls -la "$BIN"
