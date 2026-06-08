#!/bin/bash
# Instala BlueDeck: copia la app a ~/Applications (fuera de iCloud), la arranca
# automáticamente al iniciar sesión (LaunchAgent) y abre los paneles de permisos.
set -euo pipefail
cd "$(dirname "$0")"

SRC="$(pwd)/BlueDeck.app"
DST="$HOME/Applications/BlueDeck.app"
PLIST="$HOME/Library/LaunchAgents/com.bluedeck.daemon.plist"
BIN="$DST/Contents/MacOS/BlueDeck"

# 1) Compilar si hace falta
[ -d "$SRC" ] || ./build.sh

# 2) Copiar a ~/Applications (local, siempre disponible)
echo "› Instalando en $DST"
mkdir -p "$HOME/Applications"
[ -d "$DST" ] && rm -rf "$DST"
cp -R "$SRC" "$DST"
# quitar quarantine para que no salte Gatekeeper, sin re-firmar (preserva permisos)
xattr -dr com.apple.quarantine "$DST" 2>/dev/null || true

# 3) Crear el LaunchAgent (arranque automático + reinicio)
echo "› Configurando arranque automático"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.bluedeck.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>/tmp/bluedeck.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/bluedeck.log</string>
</dict>
</plist>
PLISTEOF

# 4) (Re)cargar el agente
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "✅ BlueDeck instalado y arrancado."
echo ""
echo "──────────────────────────────────────────────"
echo " FALTAN 2 PERMISOS (una sola vez). Abriendo Ajustes…"
echo " 1) Accesibilidad → activa BlueDeck   (para teclado/ratón)"
echo " 2) Bluetooth     → activa BlueDeck   (para conectar el teléfono)"
echo "──────────────────────────────────────────────"
sleep 1
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" || true
echo ""
echo "Logs en vivo:  tail -f /tmp/bluedeck.log"
