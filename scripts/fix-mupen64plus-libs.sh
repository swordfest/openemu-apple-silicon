#!/bin/bash
# Mupen64Plus / GLideN64 ships prebuilt 2015 Intel static libraries that the
# modern macOS linker rejects:
#     ld: archive member '/' not a mach-o file in '.../libz.a'
#
# Fix, without touching any upstream source:
#   - libz.a   : removed, so the linker uses the system -lz
#   - libpng.a : replaced with an arm64 build from libpng's own sources
#
#   ./fix-mupen64plus-libs.sh /path/to/OpenEmu/Mupen64Plus
#
# libpng is (c) the PNG Development Group — see ../ATTRIBUTION.md
set -euo pipefail

MUPEN="${1:?usage: fix-mupen64plus-libs.sh <Mupen64Plus checkout>}"
LIBDIR="$MUPEN/GLideN64/src/GLideNHQ/lib"
PNG_VER="${PNG_VER:-1.6.43}"
SDK="$(xcrun --show-sdk-path)"
WORK="$(mktemp -d)"

[ -d "$LIBDIR" ] || { echo "not found: $LIBDIR"; exit 1; }

echo "==> Building libpng $PNG_VER for arm64"
cd "$WORK"
curl -sL -o libpng.tar.gz \
  "https://github.com/pnggroup/libpng/archive/refs/tags/v${PNG_VER}.tar.gz"
tar xzf libpng.tar.gz
cd "libpng-${PNG_VER}"
./configure --enable-static --disable-shared --disable-tools \
  --host=aarch64-apple-darwin \
  CC="clang" CFLAGS="-arch arm64 -isysroot $SDK -O2" \
  CPPFLAGS="-isysroot $SDK" LDFLAGS="-arch arm64 -isysroot $SDK" >/dev/null
make -j"$(sysctl -n hw.ncpu)" >/dev/null

echo "==> Installing into $LIBDIR"
[ -f "$LIBDIR/libpng.a" ] && cp -n "$LIBDIR/libpng.a" "$LIBDIR/libpng.a.intel.bak" || true
[ -f "$LIBDIR/libz.a" ]   && mv    "$LIBDIR/libz.a"   "$LIBDIR/libz.a.intel.bak"   || true
cp .libs/libpng16.a "$LIBDIR/libpng.a"

echo "==> libpng.a is now: $(lipo -archs "$LIBDIR/libpng.a")"
rm -rf "$WORK"
echo "Done. Originals kept as *.intel.bak"
