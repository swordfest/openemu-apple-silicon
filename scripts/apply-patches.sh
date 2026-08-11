#!/bin/bash
# Apply the patches to an OpenEmu checkout.
#
#   ./apply-patches.sh /path/to/OpenEmu [/path/to/PPSSPP-Core]
#
# See ../ATTRIBUTION.md — all patched code belongs to its upstream authors.
set -euo pipefail

PATCHES="$(cd "$(dirname "$0")/../patches" && pwd)"
OE="${1:?usage: apply-patches.sh <OpenEmu checkout> [PPSSPP-Core checkout]}"
PPSSPP="${2:-}"

apply () { # repo  patch
  local repo="$1" patch="$2"
  if [ ! -d "$repo" ]; then
    echo "  skip  $(basename "$patch")  (missing $repo — submodule not initialised?)"
    return
  fi
  if git -C "$repo" apply --check "$patch" 2>/dev/null; then
    git -C "$repo" apply "$patch"
    echo "  ok    $(basename "$patch")"
  elif git -C "$repo" apply --reverse --check "$patch" 2>/dev/null; then
    echo "  done  $(basename "$patch")  (already applied)"
  else
    echo "  FAIL  $(basename "$patch")  (does not apply cleanly)"
  fi
}

echo "Applying patches to: $OE"
apply "$OE/OpenEmu-SDK"              "$PATCHES/01-openemu-sdk-controller-crash.patch"
apply "$OE/Nestopia"                 "$PATCHES/02-nestopia-return-nil.patch"
apply "$OE/DeSmuME"                  "$PATCHES/03-desmume-nds-arm64.patch"
apply "$OE/Reicast/reicast-emulator" "$PATCHES/04-reicast-dreamcast-arm64.patch"

if [ -n "$PPSSPP" ]; then
  echo "Applying to: $PPSSPP"
  apply "$PPSSPP" "$PATCHES/05-ppsspp-remove-agl.patch"
else
  echo "  skip  05-ppsspp-remove-agl.patch  (no PPSSPP-Core path given)"
fi

echo
echo "Done. Next: xcodebuild -downloadComponent MetalToolchain, then see README.md"
