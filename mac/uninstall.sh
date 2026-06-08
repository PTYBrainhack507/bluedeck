#!/bin/bash
# Desinstala BlueDeck: detiene el agente y borra la app instalada.
set -uo pipefail
PLIST="$HOME/Library/LaunchAgents/com.bluedeck.daemon.plist"

echo "› Deteniendo agente…"
launchctl unload "$PLIST" 2>/dev/null || true
pkill -f "Applications/BlueDeck.app" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "$HOME/Applications/BlueDeck.app"
echo "✅ BlueDeck desinstalado."
echo "   (Si quieres, quita BlueDeck de Ajustes › Privacidad › Accesibilidad y Bluetooth.)"
