#!/bin/bash
# Compila o OpenNotch e monta o bundle .app em build/OpenNotch.app
set -euo pipefail
cd "$(dirname "$0")"

# OPENNOTCH_UNIVERSAL=1 gera um binário para Apple Silicon e Intel (usado ao publicar).
ARCH_FLAGS=()
if [ "${OPENNOTCH_UNIVERSAL:-}" = "1" ]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
APP="build/OpenNotch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/OpenNotch" "$APP/Contents/MacOS/OpenNotch"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Extension "$APP/Contents/Resources/BrowserExtension"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>OpenNotch</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>dev.opennotch.OpenNotch</string>
    <key>CFBundleName</key><string>OpenNotch</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>__VERSION__</string>
    <key>CFBundleVersion</key><string>__BUILD__</string>
    <key>CFBundleDevelopmentRegion</key><string>pt-BR</string>
    <key>CFBundleLocalizations</key><array><string>pt-BR</string><string>en</string></array>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAudioCaptureUsageDescription</key><string>O OpenNotch precisa disso para ajustar o volume de cada app separadamente. O áudio não é gravado.</string>
    <key>NSAppleEventsUsageDescription</key><string>O OpenNotch usa Apple Events para ler e controlar a música do Spotify e do Apple Music.</string>
    <key>NSCalendarsFullAccessUsageDescription</key><string>O OpenNotch mostra os eventos de hoje do seu calendário.</string>
</dict>
</plist>
PLIST

# A versão vem de OPENNOTCH_VERSION (usada pelo CI ao publicar) ou do arquivo VERSION.
VERSION="${OPENNOTCH_VERSION:-$(cat VERSION)}"
sed -i '' -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/${OPENNOTCH_BUILD:-1}/" "$APP/Contents/Info.plist"

# Com um certificado "Apple Development" a assinatura é estável e o macOS mantém as permissões
# (Automação, Gravação de Tela, Calendário) entre uma compilação e outra. Sem ele, assina ad hoc.
IDENTITY="${OPENNOTCH_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development/ {print $2; exit}')}"
# A notarização exige o "hardened runtime"; com ele, controlar o Spotify precisa do entitlement de Apple Events.
SIGN_FLAGS=(--force --deep)
if [ "${OPENNOTCH_HARDENED:-}" = "1" ]; then
    SIGN_FLAGS+=(--options runtime --timestamp --entitlements Resources/OpenNotch.entitlements)
fi
codesign "${SIGN_FLAGS[@]}" --sign "${IDENTITY:--}" "$APP"
echo "OK: $APP"
