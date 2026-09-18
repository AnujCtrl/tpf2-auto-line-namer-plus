#!/usr/bin/env bash
# Install this fork into Transport Fever 2's local mods folder as auto_line_namer_plus_1.
# Override the destination root with TPF2_LOCAL_MODS=/path/to/local/mods.
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODS="${TPF2_LOCAL_MODS:-$HOME/.local/share/Steam/userdata/204184616/1066780/local/mods}"
DEST="$MODS/auto_line_namer_plus_1"
mkdir -p "$DEST"
rsync -a --delete \
  --exclude .git --exclude docs --exclude test --exclude tf2-api \
  --exclude .vscode --exclude .luacheckrc --exclude .gitignore \
  --exclude README.md --exclude install.sh --exclude .superpowers \
  "$SRC/" "$DEST/"
echo "installed to $DEST"
