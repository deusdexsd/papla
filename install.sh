#!/usr/bin/env bash
# Builds Papla from source and installs it to /Applications.
set -euo pipefail

[[ "$(uname)" == "Darwin" ]] || { echo "Papla działa tylko na macOS. / Papla only runs on macOS."; exit 1; }
[[ "$(uname -m)" == "arm64" ]] || { echo "Papla wymaga Maca z Apple Silicon. / Papla needs an Apple Silicon Mac."; exit 1; }
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Brakuje Xcode Command Line Tools — uruchamiam instalator, potem odpal ten skrypt ponownie. / Xcode Command Line Tools are missing — starting their installer, then run this script again."
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
echo "Gotowe. Nadaj uprawnienia: Mikrofon, Dostępność, Nagrywanie ekranu. / Done. Grant permissions: Microphone, Accessibility, Screen Recording."
