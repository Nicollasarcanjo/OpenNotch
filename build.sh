#!/bin/bash
# Compila o OpenNotch e monta o bundle .app em build/OpenNotch.app
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP="build/OpenNotch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/OpenNotch" "$APP/Contents/MacOS/OpenNotch"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Extension "$APP/Contents/Resources/BrowserExtension"

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
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>O OpenNotch usa Apple Events para ler e controlar a música do Spotify e do Apple Music.</string>
    <key>NSCalendarsFullAccessUsageDescription</key><string>O OpenNotch mostra os eventos de hoje do seu calendário.</string>
</dict>
</plist>
PLIST

# Com um certificado "Apple Development" a assinatura é estável e o macOS mantém as permissões
# (Automação, Gravação de Tela, Calendário) entre uma compilação e outra. Sem ele, assina ad hoc.
IDENTITY="${OPENNOTCH_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development/ {print $2; exit}')}"
codesign --force --deep --sign "${IDENTITY:--}" "$APP"
echo "OK: $APP"
