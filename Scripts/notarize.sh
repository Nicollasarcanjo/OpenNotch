#!/bin/bash
# Gera uma versão assinada e notarizada, que abre em qualquer Mac sem aviso do Gatekeeper.
# Exige uma conta paga do Apple Developer Program. Antes de rodar:
#   1. Instale no Keychain um certificado "Developer ID Application".
#   2. Guarde as credenciais de notarização uma vez:
#        xcrun notarytool store-credentials opennotch --apple-id SEU_EMAIL --team-id SEU_TEAM_ID
# Uso: ./Scripts/notarize.sh "Developer ID Application: Seu Nome (TEAMID)"
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${1:?Informe a identidade Developer ID Application}"
PROFILE="${OPENNOTCH_NOTARY_PROFILE:-opennotch}"

OPENNOTCH_UNIVERSAL=1 OPENNOTCH_SIGN_IDENTITY="$IDENTITY" OPENNOTCH_HARDENED=1 ./build.sh
ditto -c -k --keepParent build/OpenNotch.app build/OpenNotch.zip
xcrun notarytool submit build/OpenNotch.zip --keychain-profile "$PROFILE" --wait
xcrun stapler staple build/OpenNotch.app
ditto -c -k --keepParent build/OpenNotch.app build/OpenNotch.zip
echo "OK: build/OpenNotch.zip (notarizado)"
