#!/usr/bin/env bash
# Builds Papla from source and installs it to /Applications.
set -euo pipefail

[[ "$(uname)" == "Darwin" ]] || { echo "Papla działa tylko na macOS."; exit 1; }
[[ "$(uname -m)" == "arm64" ]] || { echo "Papla wymaga Maca z Apple Silicon."; exit 1; }
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Brakuje Xcode Command Line Tools. Uruchamiam instalator — po jego zakończeniu odpal ten skrypt ponownie."
  xcode-select --install
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
git clone --depth 1 https://github.com/deusdexsd/papla.git "$WORK/papla"
cd "$WORK/papla"
make install
xattr -cr /Applications/Papla.app 2>/dev/null || true
open /Applications/Papla.app
echo
echo "Gotowe. Przy pierwszym uruchomieniu nadaj uprawnienia: Mikrofon, Dostępność, Nagrywanie ekranu."
