#!/usr/bin/env bash
# Install this mod into Transport Fever 2's local mods folder as auto_line_namer_plus_1.
# The folder is found under your Steam userdata directory (1066780 is the game's app id).
# Override it with TPF2_LOCAL_MODS=/path/to/local/mods, for example for a Flatpak or Windows/Proton layout.
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -n "${TPF2_LOCAL_MODS:-}" ]; then
  MODS="$TPF2_LOCAL_MODS"
else
  shopt -s nullglob
  candidates=("$HOME"/.local/share/Steam/userdata/*/1066780/local)
  shopt -u nullglob
  if [ "${#candidates[@]}" -eq 0 ]; then
    echo "Could not find Transport Fever 2 under ~/.local/share/Steam/userdata." >&2
    echo "Set TPF2_LOCAL_MODS=/path/to/userdata/<your Steam id>/1066780/local/mods and run again." >&2
    exit 1
  fi
  if [ "${#candidates[@]}" -gt 1 ]; then
    echo "Found more than one Steam account with Transport Fever 2:" >&2
    printf '  %s/mods\n' "${candidates[@]}" >&2
    echo "Set TPF2_LOCAL_MODS to the one you want and run again." >&2
    exit 1
  fi
  MODS="${candidates[0]}/mods"
fi

DEST="$MODS/auto_line_namer_plus_1"
mkdir -p "$DEST"
rsync -a --delete \
  --exclude .git --exclude docs --exclude test --exclude tf2-api \
  --exclude .vscode --exclude .luacheckrc --exclude .gitignore \
  --exclude README.md --exclude install.sh --exclude .superpowers \
  "$SRC/" "$DEST/"
echo "installed to $DEST"
