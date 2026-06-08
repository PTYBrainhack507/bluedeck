#!/bin/bash
# Ejecuta BlueDeck en primer plano mostrando los logs (Ctrl+C para parar).
cd "$(dirname "$0")"
[ -d BlueDeck.app ] || ./build.sh
exec ./BlueDeck.app/Contents/MacOS/BlueDeck
