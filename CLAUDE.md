# CLAUDE.md — voxel-axle

A Minecraft-style voxel game written in **Axle** and software-rendered into a
window opened by [**smalt**](https://github.com/Axle-lang/smalt), the platform layer —
also Axle, calling
Win32 or X11 + ALSA depending on the build's target. Source under `src/**.axle`,
config in `axle.toml`. See `README.md` for the architecture and controls.

## Axle toolchain — REQUIRED: v0.12.1 or newer

This project must be compiled with **Axle v0.12.1+**: it uses the primitive
numeric method surface (`x.floorToInt()`, not a `Math` class) and per-platform
module overlays, neither of which the 0.7 line has. Always check the version
before building:

```powershell
axle --version        # must print 0.12.1 or higher
```

If the version is < 0.12.1 (or `axle: command not found`), install/upgrade the
compiler (see below) **before** compiling anything. Do not fall back to an
older version: codegen and the stdlib evolve between releases, and an older
binary can surface errors that no longer exist in 0.12.1+.

## Install / upgrade Axle

The compiler lives in the sibling repo `../axle` (Rust + LLVM 18 backend).

### Windows (this machine)

The binary is installed via the MSI at `C:\Program Files (x86)\Axle\axle.exe`.
Two ways to get 0.12.1+:

1. **MSI release (recommended)** — install the Windows x64 `.msi` from the
   `v0.12.1` version, then reopen the terminal and
   recheck `axle --version`.
2. **Build from source** — from `../axle`:
   ```powershell
   # Prerequisites: Visual C++ Build Tools + LLVM 18 (see ../axle/SETUP-WINDOWS.md)
   $env:LLVM_SYS_181_PREFIX = "C:\Program Files\LLVM"
   cargo build --release -p axle_cli
   # binary: ../axle/target/release/axle.exe — add it to PATH or call it directly
   ```

### Linux / macOS

- **Linux (apt)**: official repo — `sudo apt install axle`, then
  `sudo apt upgrade` to move to 0.12.1+. Details in
  `../axle/docs/src/getting-started/install.md`.
- **macOS / no apt**: Docker image or build from source
  (`../axle/docs/src/getting-started/build.md`).

## Runtime prerequisites for THIS project

- The **`vendor/smalt` submodule**, initialised — `axle.toml` names it as the
  path dependency `vendor/smalt` and its `src/` compiles with ours. Clone with
  `git clone --recurse-submodules`, or run `git submodule update --init` in an
  existing checkout; without it `axle build` stops immediately with
  ``dependency `smalt` … has no axle.toml at …/vendor/smalt``.
- Nothing to install on Windows. On Linux the binary links `libX11` and
  `libasound`, which any desktop already has; building needs their `-dev`
  packages.
- `atlas.raw` must sit next to the binary or in `target/` (loaded at runtime).

## Build & run

```powershell
axle --version        # 0.12.1+ required
axle run              # from the project root
```

Useful Axle commands: `axle build <in>`, `axle run <in>`,
`axle check <in>` (type-check only).
