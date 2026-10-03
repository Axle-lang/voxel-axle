# CLAUDE.md — voxel-axle

A Minecraft-style voxel game written in **Axle** and software-rendered into a
window opened by [**smalt**](https://github.com/Axle-lang/smalt), the platform layer —
also Axle, calling
Win32 or X11 + ALSA depending on the build's target. Source under `src/**.axle`,
config in `axle.toml`. See `README.md` for the controls and
`docs/ARCHITECTURE.md` for the source layout, the dependency rule and the GPU
plan — read it before moving or adding a file.

## Where code goes

- `src/engine/` never imports `src/game/`, `src/app/` or `src/checks/`;
  content reaches it through injection seams (`Generator`, `MobSpawner`,
  `ActorVisual.buildModel`).
- Backend-neutral rendering (`engine/render/view`, `engine/shade`,
  `engine/sky`) never imports `engine/render/cpu` — that is the line a GPU
  backend (`engine/render/gpu`, next to `cpu`) will plug in at.
- Nothing under `engine/render` or `engine/sky` names the player: the
  renderer is handed a `View` (`app/view.axle`) and builds one `Camera`.
- A file that grows past ~700 lines is doing more than one job: split it
  along the jobs, not by line count.

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

## What comes from smalt, and what is ours

Reach for the platform layer before writing one. smalt now carries the
pieces this game used to duplicate, and a change that re-adds one of them
here is almost certainly in the wrong repository:

| Need | Use | Not |
|---|---|---|
| A 2-D drawing surface with a clip | `smalt::Frame`, from `screen.frame()` | a `Canvas` of our own |
| Rectangles, rounded boxes, rules, blends | `Frame`'s methods | a hand-rolled `fillRect` |
| Text | `smalt::BitmapFont` (`Face::Ui` for prose, `Face::Headline` for figures) | a glyph table of our own |
| Text bigger than the face | `drawScaled` + `baselineFor` | a second font |
| Packing, channels, mixing, clamping | `smalt::Color`'s statics | open-coded shifts |
| Frame pacing and the fixed timestep | `smalt::FramePacer` — `tick`, then `steps` / `alpha` | a `GameClock` |
| Pumping the audio device off-thread | `spawn smalt::mixerLoop(mixer)` | a loop and a spinlock |
| A screenshot | `smalt::Bmp::write(path, frame)` | a BMP writer |
| Interned text, key → slot | `smalt::BytePool`, `smalt::SlotIndex` | a pool of our own |

**Take a `Frame` fresh each repaint** (`screen.frame()`), never store one:
it carries the surface's address, and a resize moves it.

What stays ours is what is a *game* decision: the hurt tint, the `Widget`
seam the overlay composes through, the block table, the mip chain, the
anisotropic sampler, and the world rasteriser in `engine/render/cpu/`.

smalt's own limits are in `vendor/smalt/LIMITATIONS.md` — read it before
concluding something is impossible.

## Runtime prerequisites for THIS project

- The **`vendor/smalt` submodule**, initialised — `axle.toml` names it as the
  path dependency `vendor/smalt` and its `src/` compiles with ours. Clone with
  `git clone --recurse-submodules`, or run `git submodule update --init` in an
  existing checkout; without it `axle build` stops immediately with
  ``dependency `smalt` … has no axle.toml at …/vendor/smalt``.
- Nothing to install on Windows. On Linux the binary links `libX11` and
  `libasound`, which any desktop already has; building needs their `-dev`
  packages.
- `atlas.raw` is loaded at runtime from the working directory or its parent,
  so run from the repo root (as `axle run` does) or from `target/`. Re-bake
  it with `python tools/bake_atlas.py`.

## Build & run — ALWAYS with `-O 3`

`axle`'s default is `-O 1`: every HIR transform, and **no LLVM pipeline behind
it**. This game is a software rasteriser, so that default costs it a fifth of
its frame rate — 51 fps against 60 on the reference capture, for a compiler
flag. `-O 3` is numerically identical here: `--physics-check` and
`--light-check` agree to the last digit at both levels.

```powershell
axle --version        # 0.12.1+ required
axle run -O 3         # from the project root
axle run -O 3 -- --snap    # play 3 s, write voxel.bmp, quit — a headless check
axle run -O 3 -- --at 294456 109296   # start at a named column, reproducibly
axle run -O 3 -- --snap --at 294456 109296 --look 225 -8   # the same framed image, twice
```

`--target-cpu native` is **not** accepted (LLVM wants a real name); `znver5`
measured no better than plain `-O 3`, so the portable build is also the fast
one.

Two captures are only comparable if `--look` pins the view: without it the
spawn picks the yaw and the mouse grab moves it.

The start column is random per run and printed on stdout. If you are
comparing two runs, pass `--at` or you are comparing two worlds.

Before and after any structural change, run the headless checks and diff
their output: `--physics-check`, `--light-check`, `--biome-scan`,
`--cull-check` print byte-identical text when behaviour is unchanged, and
`--model-check` exits non-zero if a species lost its body. They do not cover
the game loop or the renderer — finish with one pinned `--snap`.

Useful Axle commands: `axle build <in>`, `axle run <in>`,
`axle check <in>` (type-check only).
