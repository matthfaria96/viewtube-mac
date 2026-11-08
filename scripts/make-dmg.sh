#!/bin/zsh
# Monta dist/ViewTube-<versão>-mac.dmg a partir de build/ViewTube.app (o app do Mac, em Swift).
# Rode scripts/build-app.sh antes. O DMG não é assinado/notarizado: o primeiro aberto mostra o
# aviso do Gatekeeper (o README explica o `xattr -dr com.apple.quarantine`).
set -euo pipefail
cd "${0:A:h}/.."

APP="build/ViewTube.app"
[[ -d "$APP" ]] || { echo "Falta $APP. Rode scripts/build-app.sh primeiro."; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/ViewTube.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
DMG="dist/ViewTube-$VERSION-mac.dmg"
rm -f "$DMG"
hdiutil create -volname "ViewTube $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
shasum -a 256 "$DMG"
echo "Pronto: $DMG"
