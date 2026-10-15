#!/usr/bin/env bash
# Fetch the ghostty submodule and build GhosttyKit.xcframework at the repo root.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! git config -f .gitmodules --get submodule.ghostty.path >/dev/null 2>&1; then
  git submodule add https://github.com/ghostty-org/ghostty ghostty
fi
git submodule update --init --recursive ghostty

# Zig breaks API between minor versions; use the one ghostty pins (brew zig@X.Y is keg-only).
want="$(sed -n 's/.*minimum_zig_version = "\([0-9]*\.[0-9]*\).*/\1/p' ghostty/build.zig.zon)"
ZIG="${ZIG:-$(brew --prefix "zig@$want" 2>/dev/null)/bin/zig}"
[ -x "$ZIG" ] || ZIG=zig
case "$("$ZIG" version 2>/dev/null)" in
  "$want".*) ;;
  *) echo "need zig $want.x: brew install zig@$want (or ZIG=/path/to/zig)" >&2; exit 1 ;;
esac

(cd ghostty && "$ZIG" build -Demit-xcframework=true -Dxcframework-target=universal -Doptimize=ReleaseFast)

rm -rf GhosttyKit.xcframework
cp -R ghostty/macos/GhosttyKit.xcframework .
echo "GhosttyKit.xcframework ready"
