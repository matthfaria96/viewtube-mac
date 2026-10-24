#!/bin/zsh
# Compila e monta build/ViewTube.app (sem projeto Xcode).
#
#   scripts/build-app.sh [--install]
#
#   --install       copia para /Applications e registra o esquema viewtube:// no sistema.
#   --devtools      inclui viewtube://eval e devsize (só para desenvolvimento; ver CLAUDE.md).
#   SKIP_TESTS=1    pula os testes do núcleo.
set -euo pipefail
cd "${0:A:h}/.."

# SwiftUI (macros) e XCTest precisam do toolchain do Xcode, não só das Command Line Tools.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

NAME="ViewTube"
APP="build/$NAME.app"
INSTALL=0
SWIFT_FLAGS=()
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --devtools) SWIFT_FLAGS=(-Xswiftc -DVIEWTUBE_DEVTOOLS) ;;
  esac
done

if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
  echo "Rodando testes do núcleo..."
  swift test --filter ViewTubeCoreTests
fi

# Universal: Apple Silicon e Intel.
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}" "${SWIFT_FLAGS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" "${SWIFT_FLAGS[@]}" --show-bin-path)/$NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Versão: última tag (v1.2.3 -> 1.2.3); build: número de commits.
VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')" || true
[[ "$VERSION" =~ '^[0-9]+(\.[0-9]+){0,2}$' ]] || VERSION="0.1.0"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"

# O SwiftPM grava o alvo mínimo como versão do SDK, e o macOS novo roda o app
# no visual antigo (sem Liquid Glass). Grava o SDK real.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
if [[ -n "$SDK_VERSION" ]]; then
  vtool -set-build-version macos 14.0 "$SDK_VERSION" -replace \
    -output "$APP/Contents/MacOS/$NAME" "$APP/Contents/MacOS/$NAME"
fi

codesign --force --sign - "$APP"
echo "Pronto: $APP ($VERSION, build $BUILD)"

if (( INSTALL )); then
  pkill -x "$NAME" 2>/dev/null && sleep 1 || true
  rm -rf "/Applications/$NAME.app"
  cp -R "$APP" /Applications/
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$NAME.app"
  echo "Instalado em /Applications/$NAME.app"
fi
