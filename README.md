# OpenEmu on Apple Silicon — build notes and patches

Notes and patch files for building [OpenEmu](https://github.com/OpenEmu/OpenEmu)
and its cores as **native arm64** on Apple Silicon, using a current Xcode.

> **This repository contains no upstream source code and no ROMs or BIOS files.**
> It is patches plus documentation. All credit for the software belongs to the
> projects listed in [ATTRIBUTION.md](ATTRIBUTION.md) — please read that first.

Built and tested on: **Mac (M4), macOS 26.5, Xcode 26.6**.

---

## Why

The official OpenEmu 2.4.1 release is **Intel-only**. Under Rosetta on Apple
Silicon it can crash with:

```
EXC_BAD_INSTRUCTION (SIGILL)
BUG IN CLIENT OF LIBPLATFORM: os_unfair_lock is corrupt, or owner thread exited without unlocking
```

which is reliably triggered by connecting a controller. Building natively removes
this entirely.

**The application code itself needed no arm64 changes.** OpenEmu is Intel-only by
release process, not by incompatibility. Everything patched here is either a
modern-toolchain strictness issue or a stale build setting.

---

## Result

| | |
|---|---|
| App | native arm64 |
| Cores built arm64 | 26 |
| Systems verified running a game | ~17 |

Verified playing: N64, NES, GBA, PS1, SNES, Game Boy, Game Boy Color, Master
System, Game Gear, Genesis, Atari 2600, Atari 7800, Atari Lynx, Vectrex,
ColecoVision, MSX, **Nintendo DS**.

Not verified: **PSP** (builds and initialises, but no legitimate test image was
available — see Status). **Dreamcast** builds but OpenEmu's importer will not
accept a disc (see Status).

---

## Patches

Each applies with `git apply` inside the corresponding checkout.

| Patch | Repo | What it fixes |
|---|---|---|
| `01-openemu-sdk-controller-crash` | OpenEmu-SDK | `NSAssert` abort when a device reports 0 controls (crashes app **and** helper on controller connect); mismatched enum comparison |
| `02-nestopia-return-nil` | Nestopia-Core | `return NO` from a method returning `NSData *` |
| `03-desmume-nds-arm64` | DeSmuME-Core | 4 legacy issues blocking NDS (see below) |
| `04-reicast-dreamcast-arm64` | reicast-emulator | Makes the existing arm64 path actually get selected |
| `05-ppsspp-remove-agl` | PPSSPP-Core | Removes `AGL.framework` (deleted from modern SDKs) |

### Detail worth knowing

**OpenEmu-SDK — the controller crash.** `OEDeviceManager.m` asserts that a
handler has `numberOfControls > 0`. Without the **Input Monitoring** privacy
permission, macOS hides a device's HID elements, so a controller legitimately
reports zero controls and the assert aborts the process. Because
`OpenEmuHelperApp` is a separate binary with its own TCC identity, this killed
game launches too. The patch skips such a handler instead of aborting.

**DeSmuME.** All 15 build errors came from four root causes: `strong` (ARC)
ownership on C++ classes; a `WIFI_LOG` macro written as `"WIFI: "__VA_ARGS__`
with no space (C++11 parses it as a user-defined literal — 13 of the 15 errors);
`~0 << N`, i.e. left-shift of a negative int, rejected in constant expressions;
and `src != '\0'` comparing a `const char *` to a char.

**reicast.** It already ships an arm64 code path *and* an arm64 dynarec
(`core/rec-ARM64/`). The blocker was that the Xcode project hardcodes
`TARGET_OSX_X64`, so `HOST_CPU` never became `CPU_ARM64` and the x86 assembly
paths were compiled. The patch adds an `__aarch64__` branch **first** in the
target chain, and fixes: a removed `sys_cache_control` API, Apple's nested arm64
`mcontext`, libpng's ancient `<fp.h>` branch, and a Linux-only header include.

---

## Building

Prerequisites: Xcode 26+, and the Metal toolchain, which is a separate download:

```bash
xcodebuild -downloadComponent MetalToolchain
```

Nested submodules use SSH URLs; rewrite them so cloning works without keys:

```bash
git config --global url."https://github.com/".insteadOf "git@github.com:"
```

### The app

```bash
git clone --recursive https://github.com/OpenEmu/OpenEmu.git
cd OpenEmu
git -C OpenEmu-SDK apply /path/to/patches/01-openemu-sdk-controller-crash.patch

xcodebuild -workspace OpenEmu.xcworkspace -scheme OpenEmu -configuration Release \
  -derivedDataPath build_arm64 -arch arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO VERSIONING_SYSTEM="" build
```

`VERSIONING_SYSTEM=""` is required: the apple-generic versioning stub creates a
`Cycle inside CSPIRVTools` dependency-cycle error with the current build system.
(`EAGER_LINKING=NO` and `ENABLE_USER_SCRIPT_SANDBOXING=YES` do **not** fix it.)

### Cores

Build the SDK frameworks in **Release** first, then each core. Cores refuse to
build in Debug (`#error "Cores should not be compiled in DEBUG!"`).

```bash
xcodebuild -project <Core>/<Core>.xcodeproj -scheme <Core> -configuration Release \
  -derivedDataPath build_arm64 -arch arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO VERSIONING_SYSTEM="" GCC_TREAT_WARNINGS_AS_ERRORS=NO build
```

See `scripts/` for per-core extras. Notable ones:

- **Nestopia** — add `OTHER_CPLUSPLUSFLAGS="-Wno-c++11-narrowing"` (28 files).
- **blueMSX** — a command-line `OTHER_CFLAGS` **replaces** the project value, so
  re-add its `-D` defines (`-DNO_FRAMEBUFFER` etc.) or the build breaks.
- **Mupen64Plus** — `GLideN64/src/GLideNHQ/lib/` ships 2015 Intel static libs the
  modern linker rejects. Delete `libz.a` (the system `-lz` is used instead) and
  replace `libpng.a` with an arm64 build from libpng source.
- **Reicast** — build with `GCC_PREPROCESSOR_DEFINITIONS='TARGET_NO_JIT $(inherited)'`
  and `EXCLUDED_ARCHS=""`. Keep `$(inherited)`, or FLAC/libpng config is lost.
  `build.h` unconditionally `#define`s `FEAT_SHREC` from `TARGET_NO_*` macros, so
  `-DFEAT_SHREC=...` is ignored; `TARGET_NO_JIT` selects the portable recompiler.
- **PPSSPP** — a first build fails on the generated `git-version.cpp` (undeclared
  script output); building again succeeds. Needs
  `HEADER_SEARCH_PATHS='$(inherited) "<OpenEmu>/OpenEmu/SystemPlugins/PSP"'`.

### Installing

Copy `.oecoreplugin` bundles into
`~/Library/Application Support/OpenEmu/Cores/` and ad-hoc sign each one, plus
the app:

```bash
codesign --force --deep --sign - <bundle>
```

**After every re-sign, Input Monitoring must be granted again** (System Settings
→ Privacy & Security → Input Monitoring), because ad-hoc signing changes the code
hash and macOS treats it as a new binary.

---

## Status / known gaps

- **PSP** — builds, installs, initialises, and reaches its frame loop, but has
  not been verified running an actual game. OpenEmu's PSP importer only accepts
  a real UMD image (`.cso`, or `"PSP GAME"` at offset `0x8008`); no legitimate
  test image was on hand. Unverified, not claimed working.
- **Dreamcast** — reicast builds arm64 and the Dreamcast system plugin loads, but
  OpenEmu never imports a `.gdi`. The disc parses fine and the system is enabled;
  the importer path was traced without finding the cause. Likely the same
  incomplete integration as other never-shipped systems.
- **Jaguar, Pokémon Mini, Watara Supervision, 3DO** — cores and system plugins
  build, but the importer will not take their files.
- **GameCube / Wii (Dolphin)** — not attempted. Dolphin is not a submodule of the
  OpenEmu repo; it lives at https://github.com/OpenEmu/dolphin.
- Auto-update (Sparkle) will replace a local build with the official Intel one.
  Don't use "Check for Updates" on a custom build.

---

## Licensing

Patches are derivative works of their upstream projects and are offered under
each project's own license (BSD-3-Clause for OpenEmu components; GPL-2.0 or later
for DeSmuME, reicast, and PPSSPP). See [ATTRIBUTION.md](ATTRIBUTION.md).
