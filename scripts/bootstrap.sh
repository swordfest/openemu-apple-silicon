#!/bin/bash
# Build an UNOFFICIAL native arm64 OpenEmu from upstream sources + the patches
# in this repository.
#
#   ./bootstrap.sh [workdir] [core-set]
#
#     workdir    where to clone/build   (default: ./build)
#     core-set   essential | all        (default: essential)
#
#   essential : N64, NES, GBA, PS1, SNES, Game Boy, Genesis, NDS   (8 cores)
#   all       : every core this project knows how to build         (26 cores)
#
# Produces: <workdir>/dist/OpenEmu-<ver>-arm64-unofficial/
#
# This builds software written by other people. See ../ATTRIBUTION.md.
# The result is an UNOFFICIAL build and must not be presented as an official
# OpenEmu release.
set -euo pipefail

WORK="${1:-$(pwd)/build}"
CORESET="${2:-essential}"
PATCHES="$(cd "$(dirname "$0")/../patches" && pwd)"
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
DD="$WORK/OpenEmu/build_arm64"
JOBS="$(sysctl -n hw.ncpu)"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- prerequisites
say "Checking prerequisites"
[ "$(uname -m)" = "arm64" ] || die "This script builds arm64; you are on $(uname -m)."
xcodebuild -version >/dev/null 2>&1 || die "Xcode not found (xcode-select -p)."
echo "  $(xcodebuild -version | head -1)"

if ! xcrun -f metal >/dev/null 2>&1; then
  say "Downloading the Metal toolchain (separate component in Xcode 26+)"
  xcodebuild -downloadComponent MetalToolchain
fi

# Nested submodules use SSH URLs; rewrite so cloning works without keys.
git config --global url."https://github.com/".insteadOf "git@github.com:" || true

mkdir -p "$WORK"

# ---------------------------------------------------------------------- sources
if [ ! -d "$WORK/OpenEmu/.git" ]; then
  say "Cloning OpenEmu (this takes a while)"
  git clone --recursive https://github.com/OpenEmu/OpenEmu.git "$WORK/OpenEmu"
else
  say "Reusing existing checkout at $WORK/OpenEmu"
  git -C "$WORK/OpenEmu" submodule update --init --recursive --force
fi

if [ "$CORESET" = "all" ] && [ ! -d "$WORK/PPSSPP-Core/.git" ]; then
  say "Cloning PPSSPP-Core (~3 GB of submodules)"
  git clone https://github.com/OpenEmu/PPSSPP-Core.git "$WORK/PPSSPP-Core"
  git -C "$WORK/PPSSPP-Core" submodule update --init --recursive --force
fi

# ---------------------------------------------------------------------- patches
say "Applying patches"
"$SCRIPTS/apply-patches.sh" "$WORK/OpenEmu" \
  $([ -d "$WORK/PPSSPP-Core" ] && echo "$WORK/PPSSPP-Core" || true)

say "Replacing Mupen64Plus's stale Intel static libraries"
"$SCRIPTS/fix-mupen64plus-libs.sh" "$WORK/OpenEmu/Mupen64Plus" || \
  echo "  (skipped — continuing)"

# ----------------------------------------------------------------------- builds
cd "$WORK/OpenEmu"

COMMON=(-derivedDataPath "$DD" -arch arm64 ONLY_ACTIVE_ARCH=YES
        CODE_SIGNING_ALLOWED=NO VERSIONING_SYSTEM="" GCC_TREAT_WARNINGS_AS_ERRORS=NO)

say "Building the SDK frameworks (Release)"
for s in OpenEmuBase OpenEmuSystem; do
  xcodebuild -workspace OpenEmu.xcworkspace -scheme "$s" -configuration Release \
    "${COMMON[@]}" build >/dev/null || die "SDK target $s failed"
  echo "  ok  $s"
done

say "Building OpenEmu.app (Release)"
xcodebuild -workspace OpenEmu.xcworkspace -scheme OpenEmu -configuration Release \
  "${COMMON[@]}" build >/dev/null || die "App build failed"
echo "  ok  OpenEmu.app"

ESSENTIAL=(Mupen64Plus Nestopia mGBA Mednafen BSNES Gambatte GenesisPlus)
ALL=("${ESSENTIAL[@]}" 4DO Atari800 Bliss CrabEmu FCEU JollyCV O2EM PokeMini
     Potator-Core ProSystem SNES9x Stella VecXGL VirtualJaguar blueMSX picodrive Reicast)

if [ "$CORESET" = "all" ]; then CORES=("${ALL[@]}"); else CORES=("${ESSENTIAL[@]}"); fi

build_core () {
  local dir="$1"; shift
  local proj scheme
  proj="$(ls -d "$dir"/*.xcodeproj 2>/dev/null | head -1)" || return 1
  [ -n "$proj" ] || { echo "  skip  $dir (no project)"; return 0; }
  scheme="$(basename "$proj" .xcodeproj)"
  if xcodebuild -project "$proj" -scheme "$scheme" -configuration Release \
       "${COMMON[@]}" "$@" build >/dev/null 2>&1; then
    echo "  ok    $scheme"
  else
    echo "  FAIL  $scheme"
  fi
}

say "Building cores ($CORESET)"
for c in "${CORES[@]}"; do
  case "$c" in
    Nestopia)  build_core "$c" OTHER_CPLUSPLUSFLAGS="-Wno-c++11-narrowing" ;;
    blueMSX)   # a command-line OTHER_CFLAGS REPLACES the project's -D defines
               build_core "$c" \
                 OTHER_CFLAGS="-DNO_EMBEDDED_SAMPLES -DNO_FILE_HISTORY -DNO_ASM -DNO_FRAMEBUFFER -DPIXEL_WIDTH=32 -DVIDEO_COLOR_TYPE_RGB888 -Wno-incompatible-function-pointer-types -Wno-implicit-function-declaration -Wno-int-conversion" \
                 OTHER_CPLUSPLUSFLAGS="-Wno-c++11-narrowing" ;;
    Reicast)   build_core "$c" EXCLUDED_ARCHS="" \
                 OTHER_CFLAGS="-Wno-implicit-function-declaration -Wno-int-conversion -Wno-incompatible-function-pointer-types" \
                 GCC_PREPROCESSOR_DEFINITIONS='TARGET_NO_JIT $(inherited)' ;;
    *)         build_core "$c" ;;
  esac
done

# DeSmuME lives at a non-standard path and uses its own scheme name.
if [ -d DeSmuME/src/cocoa ]; then
  say "Building DeSmuME (NDS)"
  if xcodebuild -project "DeSmuME/src/cocoa/DeSmuME (Latest).xcodeproj" \
       -scheme "DeSmuME (OpenEmu Plug-in)" -configuration Release \
       "${COMMON[@]}" OTHER_CPLUSPLUSFLAGS='$(inherited) -Wno-c++11-narrowing' \
       build >/dev/null 2>&1; then echo "  ok    DeSmuME"; else echo "  FAIL  DeSmuME"; fi
fi

# PPSSPP is a separate repository; its first build always fails on a generated
# file that isn't declared as a script-phase output, so build it twice.
if [ -d "$WORK/PPSSPP-Core" ]; then
  say "Building PPSSPP (PSP)"
  for attempt in 1 2; do
    xcodebuild -project "$WORK/PPSSPP-Core/PPSSPP.xcodeproj" -scheme PPSSPP \
      -configuration Release "${COMMON[@]}" \
      HEADER_SEARCH_PATHS="\$(inherited) \"$WORK/OpenEmu/OpenEmu/SystemPlugins/PSP\"" \
      build >/dev/null 2>&1 && break
    [ "$attempt" = 1 ] && echo "  (first pass failed as expected — retrying)"
  done
  [ -d "$DD/Build/Products/Release/PPSSPP.oecoreplugin" ] && echo "  ok    PPSSPP" || echo "  FAIL  PPSSPP"
fi

# --------------------------------------------------------------------- packaging
PROD="$DD/Build/Products/Release"
[ -d "$PROD/OpenEmu.app" ] || die "No app was produced."

VER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' \
        "$PROD/OpenEmu.app/Contents/Info.plist" 2>/dev/null || echo unknown)"
NAME="OpenEmu-${VER}-arm64-unofficial"
OUTDIR="$WORK/dist/$NAME"

say "Packaging $NAME"
rm -rf "$OUTDIR"; mkdir -p "$OUTDIR/Cores"
ditto "$PROD/OpenEmu.app" "$OUTDIR/OpenEmu.app"

for p in "$PROD"/*.oecoreplugin; do
  [ -d "$p" ] || continue
  ditto "$p" "$OUTDIR/Cores/$(basename "$p")"
done

# Ad-hoc sign so the build runs locally. This is NOT Developer ID signing:
# recipients will still have to clear the quarantine flag (see INSTALL.txt).
codesign --force --deep --sign - "$OUTDIR/OpenEmu.app" >/dev/null 2>&1 || true
for p in "$OUTDIR/Cores"/*.oecoreplugin; do
  codesign --force --deep --sign - "$p" >/dev/null 2>&1 || true
done

cp "$SCRIPTS/../INSTALL.txt" "$OUTDIR/INSTALL.txt" 2>/dev/null || true
cp "$SCRIPTS/../ATTRIBUTION.md" "$OUTDIR/ATTRIBUTION.md" 2>/dev/null || true

CORECOUNT=$(ls -d "$OUTDIR/Cores"/*.oecoreplugin 2>/dev/null | wc -l | tr -d ' ')
say "Done"
echo "  $OUTDIR"
echo "  OpenEmu.app  ($(lipo -archs "$OUTDIR/OpenEmu.app/Contents/MacOS/OpenEmu" 2>/dev/null))"
echo "  $CORECOUNT cores"
echo
echo "  This is an UNOFFICIAL build. Do not present it as an official OpenEmu release."
