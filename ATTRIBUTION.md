# Attribution & Credits

**This repository contains no upstream source code.** It holds only patch files
(unified diffs) plus build instructions. Every line of the software these patches
apply to was written by the projects and people credited below. All copyright and
licensing remains theirs.

The patches here are small compatibility fixes (a few dozen lines in total) that
let the existing code build for Apple Silicon with a modern Xcode toolchain. They
are derivative works of the projects listed below and are offered under each
project's own license.

---

## Upstream projects

### OpenEmu — the application, SDK, and core plugins
- **Copyright (c) 2009–present, OpenEmu Team**
- License: **BSD 3-Clause**
- https://github.com/OpenEmu/OpenEmu
- Patched here: `OpenEmu-SDK` (`OEDeviceManager.m`,
  `OESwitchProControllerHIDDeviceHandler.m`)

OpenEmu is the macOS front end that makes all of this work: the library, the
plugin architecture, the shader pipeline, the controller layer. This project is
nothing more than a handful of build fixes on top of their design.

### Nestopia / Nestopia-Core (NES)
- **Copyright (c) 2018, OpenEmu Team** (core plugin)
- Nestopia emulator by **Martin Freij** and contributors
- License: **BSD 3-Clause** (plugin) / **GPL-2.0** (emulator)
- https://github.com/OpenEmu/Nestopia-Core
- Patched here: `NESGameCore.mm`

### DeSmuME (Nintendo DS)
- **Copyright (C) 2007 Tim Seidel**
- **Copyright (C) 2008–2015 DeSmuME team**
- License: **GNU General Public License v2 or later**
- https://github.com/OpenEmu/DeSmuME-Core · https://desmume.org
- Patched here: `MMU_timing.h`, `cocoa/cocoa_input.h`,
  `utils/libfat/directory.cpp`, `wifi.cpp`

### reicast (Sega Dreamcast)
- **Copyright (c) reicast team and contributors**
- License: **GNU General Public License v2**
- https://github.com/reicast/reicast-emulator
- OpenEmu core wrapper: https://github.com/OpenEmu/Reicast-Core
- Patched here: `core/build.h`, `core/linux/posix_vmem.cpp`,
  `core/linux/context.cpp`, `core/linux/common.cpp`,
  `core/hw/sh4/interpr/sh4_opcodes.cpp`, `core/deps/libpng/pngpriv.h`

Note: reicast already contained a complete arm64 code path and an arm64 dynarec
backend (`core/rec-ARM64/`). The patches here only make the build **select** it —
the arm64 work itself is theirs.

### PPSSPP (Sony PSP)
- **Copyright (c) 2012– PPSSPP Project** (Henrik Rydgård and contributors)
- License: **GNU General Public License v2 or later**
- https://github.com/hrydgard/ppsspp
- OpenEmu core wrapper: https://github.com/OpenEmu/PPSSPP-Core
- Patched here: `PPSSPP.xcodeproj/project.pbxproj` (build settings only)

### Mupen64Plus / GLideN64 (Nintendo 64)
- Mupen64Plus team; GLideN64 by **Sergey Lipskiy** (gonetz) and contributors
- License: **GNU General Public License v2+**
- https://github.com/OpenEmu/Mupen64Plus-Core · https://github.com/gonetz/GLideN64
- Not patched. Requires only replacing two stale prebuilt Intel static libraries
  with an arm64 build — see `README.md`. No upstream source is modified.

### Other cores built unchanged
These required **no source changes** and are credited for completeness:
mGBA (Jeffrey Pfau / endrift), Mednafen (Mednafen team), SNES9x, BSNES (near),
Genesis Plus GX (Charles MacDonald, ekeeke), Picodrive (notaz), Gambatte
(sinamas), Stella, Atari800, ProSystem, VecXGL, O2EM, Bliss, 4DO, JollyCV,
PokeMini, Potator, VirtualJaguar, blueMSX, CrabEmu, FCEU, and their contributors.

### Supporting libraries
libpng (PNG Development Group), zlib (Jean-loup Gailly & Mark Adler),
glslang / SPIRV-Tools / SPIRV-Cross (The Khronos Group), Sparkle, XADMaster,
UniversalDetector, ZIPFoundation, swift-collections.

---

## Assets and data referenced (not redistributed here)

- **libretro-thumbnails** — box art used for the local library.
  https://github.com/libretro-thumbnails · community-maintained.
- **No-Intro** — ROM naming conventions used for matching. https://no-intro.org
- **OpenVGDB** — the game metadata database shipped with OpenEmu.

No ROMs, BIOS images, game assets, or copyrighted media are included in this
repository, and none should be added to it.

---

## What is original to this repository

Only the following, and it is deliberately small:
- The unified diffs in `patches/`
- The build documentation and scripts
- This attribution file

If any attribution above is incomplete or incorrect, that is an oversight, not a
claim — please open an issue and it will be fixed.
