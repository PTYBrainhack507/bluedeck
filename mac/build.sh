#!/bin/bash
# Compila BlueDeck.app (daemon BLE) y lo firma ad-hoc para que macOS recuerde permisos.
set -euo pipefail
cd "$(dirname "$0")"

APP="BlueDeck.app"
MACOS_DIR="$APP/Contents/MacOS"
BIN="$MACOS_DIR/BlueDeck"

echo "› Limpiando build anterior…"
rm -rf "$APP"
mkdir -p "$MACOS_DIR"

echo "› Compilando main.swift (Swift 5 mode)…"
# -sectcreate __TEXT __info_plist embebe el Info.plist DENTRO del binario,
# para que TCC encuentre las descripciones de permisos aunque se ejecute
# el binario directamente (no solo vía `open`/LaunchServices).
swiftc -O -swift-version 5 \
    -framework Cocoa \
    -framework CoreBluetooth \
    -framework CoreGraphics \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist \
    main.swift -o "$BIN"

echo "› Copiando Info.plist…"
cp Info.plist "$APP/Contents/Info.plist"

echo "› Limpiando atributos extendidos (iCloud añade FinderInfo/provenance)…"
find "$APP" -type f -name '._*' -delete 2>/dev/null || true
find "$APP" -exec xattr -c {} \; 2>/dev/null || true

echo "› Firmando ad-hoc…"
codesign --force --sign - "$APP"

echo "✅ Listo: $(pwd)/$APP"
echo "   Ejecuta:  open $(pwd)/$APP    (o ./run.sh para ver logs)"
