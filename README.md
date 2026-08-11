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
| Systems where a test ROM loads and runs | 17 |
| Systems confirmed *visually* playable | 4 (N64, SNES, Game Boy, GBA) |

17 systems load and run a test ROM, including **Nintendo DS**. Only N64 has been
confirmed *visually* playable; for the rest, "runs" means the core loads and
executes — see **Known issues** for exactly what was and was not verified, and
for the systems that stay black, refuse to import, or have no core yet.

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

## Building your own unofficial release

One command does everything — clone upstream, patch, build, package:

```bash
./scripts/bootstrap.sh ./build essential   # 8 cores, quicker
./scripts/bootstrap.sh ./build all         # 26 cores, adds ~3 GB of PPSSPP submodules
```

Output: `build/dist/OpenEmu-<version>-arm64-unofficial/` containing `OpenEmu.app`,
a `Cores/` folder, `INSTALL.txt` and `ATTRIBUTION.md`. Roughly 132 MB with all
cores.

### Automated releases

`.github/workflows/release.yml` builds the same thing on GitHub's Apple Silicon
runners (`macos-15`). Run it from the Actions tab, or push a tag:

```bash
git tag v1 && git push origin v1
```

That publishes a GitHub Release with a `.zip` and its SHA-256.

### Please keep "unofficial" in the name

The packaged folder is named `OpenEmu-<version>-arm64-unofficial` deliberately.
These builds are not produced or endorsed by the OpenEmu project, and their team
should not receive bug reports for them. Keep the naming, keep `INSTALL.txt` and
`ATTRIBUTION.md` in the archive, and link back to the upstream projects.

### Distribution obligations

- **GPL.** DeSmuME, reicast, PPSSPP, Mupen64Plus, Nestopia and others are
  GPL-licensed. If you hand someone a binary, they are entitled to the
  corresponding source. The practical way to satisfy this is to keep the
  repository containing these patches **public** and link it from every release.
  A private patch repository plus public binaries does not comply.
- **Signing.** Ad-hoc signing means recipients must clear the quarantine flag
  manually. For a frictionless install you need an Apple Developer ID
  (99 USD/year) and notarisation.
- **Never ship ROMs or BIOS files.**

## Known issues

### How "verified" was measured — read this first

Unless stated otherwise, a system marked working was checked by confirming that
`OpenEmuHelperApp` **starts, stays alive, and burns CPU** on the expected core,
built for arm64. That proves the core loads and executes. It does **not** prove a
picture appears — PSP passed exactly that check and still renders a black screen.
Read the list below as "the core runs", not "the game is playable", except where
noted.

### Confirmed playable

Games render and play, confirmed by eye on the machine listed at the top.

| System | Core | Verified with |
|---|---|---|
| N64 | Mupen64Plus | Super Mario 64 — video and controller input |
| SNES | BSNES | commercial ROMs |
| Game Boy | Gambatte | commercial ROMs |
| Game Boy Advance | mGBA | commercial ROMs |

### Runs, picture not visually confirmed

The core loads and executes a test ROM; nobody has confirmed a visible image.

| System | Core | Test ROM |
|---|---|---|
| NES | Nestopia | user's library |
| PS1 | Mednafen | user's library (BIOS present) |
| Game Boy Color | Gambatte | `ucity` (homebrew) |
| Master System | GenesisPlus | `2048grz` (homebrew) |
| Game Gear | GenesisPlus | `HelloWorld` (homebrew) |
| Genesis | GenesisPlus | `Klax` |
| Atari 2600 | Stella | `anguna` (homebrew) |
| Atari 7800 | ProSystem | `bforest` demo |
| Atari Lynx | Mednafen | `lynxvirus` (homebrew, BIOS present) |
| Vectrex | VecXGL | `revector` (homebrew) |
| ColecoVision | blueMSX | `airbattle` (homebrew) |
| MSX | blueMSX | `transball` (homebrew) |
| Nintendo DS | DeSmuME | GBARunner2 (homebrew) |

### Loads, but black screen

- **PSP** (PPSSPP) — imports, the core initialises and reaches
  `-[PPSSPPGameCore executeFrame]`, but no video appears. **It has never been
  tested with a real game**: OpenEmu's PSP importer only accepts a genuine UMD
  image (`.cso`, or `"PSP GAME"` at offset `0x8008`), and no legitimate PSP disc
  was available. Every test image was improvised from memory-stick homebrew,
  which is not a bootable UMD, so the black screen is more likely the image than
  the core — but that is unproven in both directions. **Needs a real
  `.iso`/`.cso` to settle.**

### Core starts and exits, or never starts

The required BIOS files are present and hash-verified in both cases, so this is
not a BIOS problem — most likely the homebrew test ROMs are not in a format these
cores accept.

- **Atari 5200** (Atari800) — helper starts, then exits. `5200.rom` present.
- **Intellivision** (Bliss) — helper never starts. `exec.bin` + `grom.bin` present.

### Won't import at all

The core builds and the system plugin loads, but OpenEmu's importer refuses the
file, so the game never reaches the core.

- **Dreamcast** (reicast) — `.gdi` never imports. The disc parses correctly
  (verified directly against `OEFile`), the system is enabled, `.gdi`/`.cdi` are
  registered as document types, and the BIOS is installed. The entire importer
  path was traced without finding the cause.
- **Atari Jaguar** (VirtualJaguar) — `.j64` never imports.
- **Pokémon Mini** (PokeMini) — `.min` never imports.
- **Watara Supervision** (Potator) — `.sv` never imports.

None of these four shipped in a stable OpenEmu release; their system plugins
exist only as unused Xcode targets that must be built and injected by hand, and
their importer integration appears to be incomplete upstream.

### No core built

- **GameCube / Wii** — Dolphin is not a submodule of the OpenEmu repo; it lives
  at https://github.com/OpenEmu/dolphin and has not been attempted here.

### Never tested (no ROM at hand)

These cores build and install, but no test ROM was available: **3DO** (4DO — also
needs a BIOS and a real disc image), **Odyssey²** (O2EM — needs BIOS), **Atari
8-bit** (Atari800), **SG-1000** (CrabEmu), **NeoGeo Pocket**, **PC Engine / PC
Engine CD**, **PC-FX**, **Virtual Boy**, **WonderSwan**, **Saturn** (Mednafen),
**Sega CD**, **Sega 32X** (Picodrive), **Nintendo FDS**, plus the alternate cores
**SNES9x**, **FCEU** and **JollyCV**.

### Everything else

- **Xbox controllers do not work over USB** on macOS. Wired Xbox pads speak
  Microsoft's proprietary GIP protocol and macOS ships no driver for it, so the
  system never enumerates them and no application can see them. Use Bluetooth;
  use the cable for charging.
- **Input Monitoring must be granted again after every rebuild**, because ad-hoc
  signing changes the code hash and macOS treats the binary as new.
- **Do not use "Check for Updates"** — Sparkle will replace a native build with
  the official Intel release.

---

## Licensing

Patches are derivative works of their upstream projects and are offered under
each project's own license (BSD-3-Clause for OpenEmu components; GPL-2.0 or later
for DeSmuME, reicast, and PPSSPP). See [ATTRIBUTION.md](ATTRIBUTION.md).
