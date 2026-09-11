#!/bin/bash
# One-shot setup for running Mlaser (NexCut) under Wine.
#   ./setup-wine-mlaser.sh /path/to/Mlaser-v0.0.0.52
set -e
APPDIR="${1:?usage: $0 /path/to/Mlaser-v0.0.0.52}"
[ -f "$APPDIR/MainApp.exe" ] || { echo "MainApp.exe not found in $APPDIR"; exit 1; }
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-mlaser}"
export WINEARCH=win32
export DISPLAY="${DISPLAY:-:0}"

command -v wine >/dev/null || { echo "install wine first: sudo apt install wine winetricks"; exit 1; }

echo "==> 1/4 creating 32-bit prefix at $WINEPREFIX"
wineboot --init >/dev/null 2>&1

echo "==> 2/4 installing MFC 4.2 (needed by Dxf2Grp.dll / AutoNest.dll)"
winetricks -q mfc42 >/dev/null 2>&1

echo "==> 3/4 linking app onto the C: drive"
ln -sfn "$(readlink -f "$APPDIR")" "$WINEPREFIX/drive_c/Mlaser"

echo "==> 4/4 pre-creating \\Technology\\{Fiber,CO2}"
mkdir -p "$WINEPREFIX/drive_c/Technology/Fiber" "$WINEPREFIX/drive_c/Technology/CO2"

echo
echo "done. launch with:  $(dirname "$0")/mlaser"
