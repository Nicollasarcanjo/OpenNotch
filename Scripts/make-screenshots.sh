#!/bin/bash
# Gera as imagens do README em docs/screenshots, com dados fictícios (modo de demonstração).
# As imagens saem do próprio app, sem capturar a tela: nada do seu Mac aparece nelas.
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh >/dev/null
BIN="build/OpenNotch.app/Contents/MacOS/OpenNotch"
OUT="docs/screenshots"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

shot() {  # shot <nome> [aba]
    OPENNOTCH_DEMO=1 OPENNOTCH_TAB="${2:-}" OPENNOTCH_SNAPSHOT="$TMP/$1.png" "$BIN" -AppleLanguages "(pt-BR)" 2>/dev/null
    swift Scripts/frame-screenshot.swift "$TMP/$1.png" "$OUT/$1.png"
}

shot fechado
for tab in home agents apps capture texts tray timers system; do shot "$tab" "$tab"; done

OPENNOTCH_DEMO=1 OPENNOTCH_SETTINGS_SNAPSHOT="$TMP" "$BIN" -AppleLanguages "(pt-BR)" 2>/dev/null
cp "$TMP/settings-modules.png" "$OUT/configuracoes.png"
echo "OK: $OUT"
