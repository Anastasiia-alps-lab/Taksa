#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: 2026 Anastasiia-alps-lab
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Builds Taksa.app out of the Swift package.
#
#   ./build-app.sh              -> macos/dist/Taksa.app
#   ./build-app.sh --install    -> the same, then copied to /Applications
#
# Needs the Xcode command line tools (xcode-select --install) and nothing else.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The artwork is shared with the GNOME build: one file, one dog. TAKSA_FIGURE
# points somewhere else — the same variable the app itself reads — which is what
# lets this directory be built on its own, away from the rest of the repository.
FIGURE="${TAKSA_FIGURE:-$HERE/../taksa@alps/taksa.png}"
APP="$HERE/dist/Taksa.app"

install=false
case "${1:-}" in
    --install) install=true ;;
    '') ;;
    *) printf 'usage: %s [--install]\n' "$(basename "$0")" >&2; exit 1 ;;
esac

if [ ! -f "$FIGURE" ]; then
    printf 'taksa: no artwork at %s\n' "$FIGURE" >&2
    printf 'taksa: copy the repository whole, or set TAKSA_FIGURE to a taksa.png\n' >&2
    exit 1
fi

cd "$HERE"

# One binary for both Apple silicon and Intel.
archs=(--arch arm64 --arch x86_64)
swift build -c release "${archs[@]}"
binary="$(swift build -c release "${archs[@]}" --show-bin-path)/Taksa"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$binary" "$APP/Contents/MacOS/Taksa"
cp "$HERE/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$FIGURE" "$APP/Contents/Resources/taksa.png"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# An ad hoc signature is enough to run on the machine that built the app. A
# build for other people would need an Apple Developer account to sign and
# notarise it.
codesign --force --sign - "$APP"

printf 'taksa: built %s\n' "$APP"

if $install; then
    # Replacing a running copy leaves the old process alive with a deleted
    # bundle underneath it, so ask it to quit first.
    osascript -e 'quit app "Taksa"' 2>/dev/null || true
    rm -rf /Applications/Taksa.app
    cp -R "$APP" /Applications/Taksa.app
    printf 'taksa: installed /Applications/Taksa.app\n'
fi
