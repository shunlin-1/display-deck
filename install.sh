#!/usr/bin/env bash
# Display Deck installer — symlinks the launcher and QML into ~/.local so the
# repo stays the single source of truth (edit here, changes are live).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.local/bin"
SHARE="$HOME/.local/share/niri-displays/qml"

mkdir -p "$BIN" "$SHARE"
ln -sf "$REPO/bin/niri-displays" "$BIN/niri-displays"
ln -sf "$REPO/qml/shell.qml"     "$SHARE/shell.qml"

echo "Linked:"
echo "  $BIN/niri-displays  -> $REPO/bin/niri-displays"
echo "  $SHARE/shell.qml    -> $REPO/qml/shell.qml"
echo
echo "Launch with:  niri-displays   (ensure ~/.local/bin is on PATH)"
echo "Suggested niri bind:  Mod+Shift+T { spawn \"niri-displays\"; }"
