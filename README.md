# voxel — a Minecraft-style survival world in Axle (SDL2)

A first-person **survival** voxel world software-rendered into an SDL2
window — no GPU, every pixel shaded on the CPU. You are a real entity:
gravity pulls you down, you stand and walk on **voxel-accurate** streamed
terrain, jump, swim, auto-step ledges, and take fall / drowning damage with
health that regenerates. The land is an **infinite, streamed** landscape of
~18 Minecraft-like biomes — ocean, beach, plains, forest, birch & cherry
groves, jungle, bamboo, savanna, badlands, swamp, taiga, snowy, mountains,
mushroom fields, frozen ocean — shaped by continentalness / erosion /
peaks-and-valleys noise, dressed with trees, oceans and thin variable-depth
snow, and roamed by texture-skinned **mobs** (chickens, sheep, cows, pigs,
creepers). Over it all runs a real **lighting engine**: a propagating
sky + block light field, a day/night cycle with a moving sun, soft
directional shadows, god-rays, bloom and an atmospheric sky — with the
audio, lighting and rasteriser spread across **threads** so it stays smooth.

## Screenshots

![Lighting engine — birch & cherry grove under sun glow, soft shadows and atmospheric sky](doc/lightengine.png)

*The lighting engine: warm sunlit ground, soft shadows under the canopy, a
sun glow with god-rays and a graded atmospheric sky.*

| Forest | Desert | Coast |
|--------|--------|-------|
| ![Forest biome with oak trees](doc/gameplay.png) | ![Desert biome with a water pool and a mob](doc/gameplay2.png) | ![Hills meeting a beach and ocean, with chickens](doc/gameplay3.png) |

## Controls

| Input            | Action                                   |
|------------------|------------------------------------------|
| Mouse            | look around (captured)                   |
| `W` `A` `S` `D`  | walk                                     |
| `LCtrl`          | sprint                                   |
| `Space`          | jump / swim up / fly up (creative)       |
| `LShift`         | fly down (creative)                      |
| Left-click       | dig the block / attack the mob in front  |
| Right-click      | place the held block                     |
| `1`–`9`          | select hotbar slot                       |
| `F3` + `F4`      | toggle survival ↔ creative (free flight) |
| `Esc` / close    | quit                                     |

## Prerequisites

You need two things: the **Axle compiler** (v0.2.11 or newer) and the
**SDL2** library.

### 1. Install the Axle compiler (v0.2.11+)

This project must be built with Axle **v0.2.11 or newer**. Check what you
have:

```bash
axle --version      # must print 0.2.11 or higher
```

If it's missing or older:

- **Windows** — install the Windows x64 `.msi` from the `v0.2.11` (or
  newer) release; it installs `axle.exe` to `C:\Program Files (x86)\Axle\`
  and onto your `PATH`. Or build from source from the `axle` compiler repo:
  ```powershell
  # needs Visual C++ Build Tools + LLVM 18 (see the axle repo's SETUP-WINDOWS.md)
  $env:LLVM_SYS_181_PREFIX = "C:\Program Files\LLVM"
  cargo build --release -p axle_cli   # -> target/release/axle.exe (add to PATH)
  ```
- **Linux (apt)** —
  ```bash
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://apt.axle-lang.dev/key.asc \
      | sudo gpg --dearmor -o /etc/apt/keyrings/axle.gpg
  echo "deb [signed-by=/etc/apt/keyrings/axle.gpg arch=amd64] https://apt.axle-lang.dev stable main" \
      | sudo tee /etc/apt/sources.list.d/axle.list
  sudo apt update && sudo apt install axle   # LLVM 18 + lld pulled in automatically
  ```
- **macOS / no apt** — use the Docker image or build from source (see the
  axle compiler repo's `docs/src/getting-started/install.md`).

### 2. Install the SDL2 library

The engine links against SDL2 and needs `SDL2.dll` next to the binary at
runtime.

- **Windows (vcpkg)** —
  ```powershell
  vcpkg install sdl2:x64-windows
  ```
  Then point `axle.toml`'s `[link] paths` at vcpkg's `lib` directory
  (e.g. `C:/vcpkg/installed/x64-windows/lib`) and copy
  `SDL2.dll` (from `C:/vcpkg/installed/x64-windows/bin`) into `target/`.
- **Linux** — `sudo apt install libsdl2-dev` (then set `[link] paths` to the
  system lib dir if needed).
- **macOS** — `brew install sdl2`.

## Build & run

From this directory, with `axle --version` reporting 0.2.11+ and SDL2
installed:

```bash
axle run            # compile + run
```

Other useful commands: `axle build` (compile to a binary without running)
and `axle check` (type-check only). Make sure `SDL2.dll` and `atlas.raw`
sit next to the produced binary (in `target/`).

## Architecture

The code is built as a small object hierarchy on top of a data-oriented
chunk world. Living things share one physics implementation through
inheritance; the world, renderer and HUD are plain engine modules. Hot
geometry and call-sites are bundled in value `struct`s (`Vec3`, `FrameBuf`,
`RasterVert`, `RasterTri`, `MipAtlas`, `Rgb`, `Band`) instead of long argument
lists. The two largest classes delegate to focused leaf mini-managers —
`ChunkManager` keeps its raw storage in a `VoxStore` and carves trees through the
leaf `treegen`; the `Renderer` runs its soft-glow pass through a `Bloom` module.

```
                 ┌────────────┐
                 │   Entity   │  pos, velY, hp, radius, gravity + VOXEL
                 │            │  AABB collision, auto-step up / step-down,
                 └─────┬──────┘  damage / heal
            extends    │    extends
        ┌──────────────┴───────────────┐
   ┌────▼─────┐                    ┌────▼────┐
   │  Player  │ FPS camera, input, │   Mob   │ AI + skins (chicken / sheep /
   │          │ jump / swim, fall  │         │ cow / pig / creeper), wander /
   │          │ & drown & regen,   │         │ graze / flee / die
   │          │ creative flight    │         │
   └──────────┘                    └─────────┘
```

### Source layout

Modules are grouped into folders by role. Within the package, a `use`
that crosses folders is written from the source root with a `crate::`
prefix (like Rust); same-folder siblings can be imported by bare name.

```
src/
  main.axle              thin entry: window + buffers + worker threads, then
                         the input → simulate → render loop (paced by the clock)
  config.axle            re-export hub for every tunable in configs/* …
  configs/               screen, render, atlas, light, time, water, noise,
                         world, biomes, blocks, trees, physics, mobs, gameplay,
                         health, hud, audio, face — change the feel here
  input.axle  mathx.axle  vec3.axle   keyboard axes, math helpers, Vec3 struct
  clock.axle             FrameClock: holds the loop to config::tickHz
  platform/ (mem · sdl · file)   libc/framebuffer helpers, SDL2 FFI, atlas load
  world/
    noise.axle           value noise + fbm; continentalness / erosion /
                         peaks-valleys terrain, climate, snow depth
    blocks.axle          block table: id → tile / colour / predicates,
                         blockBoxHeight category helpers
    biome.axle  biomes/  climate → biome; one module per biome + a registry
    voxstore.axle        VoxStore (leaf): the padded voxel field + face-Y
                         watermark + the shared voxIdx layout
    treegen.axle         tree / mushroom stamper (leaf): carves canopies into
                         a VoxStore — no dependency back on ChunkManager
    manager.axle         ChunkManager: streamed voxel chunks (over a VoxStore),
                         meshing, the block + sky LIGHT engine (own thread),
                         break/place
    blocksim.axle        block updates: falling sand/gravel, water flow
  entities/
    entity.axle          Entity base: gravity, voxel AABB collision, damage
    player.axle          Player: look, move, survival, hotbar, creative fly
    mob.axle  mobs.axle  Mob AI base + MobManager (spawn ring / cull / melee)
    chicken·sheep·cow·pig·creeper   per-animal skins & behaviour
  game/
    start.axle           start-position search + facing yaw
    ray.axle             Picker: look-ray voxel pick with real per-block boxes
    sfx.axle             AudioManager + audio thread (SDL mixing)
    tick.axle            fixed-timestep helpers
  gfx/
    color.axle  font.axle   colour math + bitmap text
    raster.axle          triangle rasteriser + z-buffer (textured + flat),
                         mip-chain + anisotropic sampling; the RasterTri /
                         MipAtlas / Rgb / Band geometry structs
    bloom.axle           Bloom (leaf): bright-extract → blur → composite glow,
                         owns its half-res buffers + worker jobs
    render.axle          project + cull + shade world; lighting, soft shadows,
                         god-rays, sky; mobs; selection box (threaded); runs
                         bloom through the Bloom module
    health·hotbar·hud·menu   heart row, inventory bar, HUD, pause menu
```

### Why inheritance here

`Player` and `Mob` are genuinely the same *kind* of thing physically: both
fall, both stand on terrain, both step up one-block ledges, both can be
hurt. That shared behaviour lives once in `Entity` and is reused by both
subclasses unchanged — `Player.update` and `Mob.aiStep` only decide *what
horizontal move to feed the shared `tick`*, and how to react to health and
the recorded landing `impact`. Adding a new animal is a new `Entity`
subclass plus a draw case.

## How it works

1. **Streaming.** A `span × span` ring of chunk slots is addressed by
   chunk-coordinate modulo `span`, so a chunk keeps its slot as the player
   moves; crossing a border only regenerates the newly entered chunks.
2. **Generation.** Per column, low-frequency *continentalness* raises land
   out of the ocean, *erosion* flattens or roughens it, and a ridged
   *peaks-and-valleys* term carves mountains and valleys; height splines tie
   them together into coherent 1.21-style landforms. A `temperature ×
   humidity × elevation` climate grid picks the biome (one module under
   `world/biomes/`), which decides the surface/filler blocks and tree
   density. Cold biomes lay a thin, noise-varied **snow layer** (random
   depth) on the ground and dust the tree canopies.
3. **Physics.** `Entity` integrates gravity into `velY` and resolves
   collision against the **real voxel field**: the body is a `radius`-wide,
   `height`-tall AABB tested against every voxel it overlaps, so you can't
   clip a cliff, a trunk or walk into a wall — and you *can* walk under
   overhangs and into dug tunnels. Gentle ledges (≤ `stepHeight`) auto-step
   up, and a **step-down assist** eases small drops so borders glide instead
   of stuttering. **Partial-height blocks** (snow today, slabs later) occupy
   their true box — one authority, `ChunkManager.blockBoxHeight`, feeds
   collision, meshing, the picker and the selection outline alike, so the
   hitbox always matches what you see. Hard landings become fall damage;
   submersion drains breath then health; time without damage regenerates it.
4. **Lighting.** A flood-filled **sky + block light** field gives every voxel
   corner a smooth (Gouraud) light value with ambient occlusion; torches
   inject warm block light. A **day/night cycle** moves a sun (and a
   procedural sun/moon disc) across an **atmospheric sky gradient**;
   **directional sun shadows** are cast with a soft, smoothed penumbra (no
   block staircase), warm sunlight reads against cool shade, and a one-bounce
   colour tint bleeds nearby surfaces. Bright pixels (sun, water glints) get
   **bloom**, and the sun throws screen-space **god-rays**. Mobs are lit by
   the same scene light, so they darken at night and under canopy. The whole
   light field is recomputed on a **dedicated thread**.
5. **Rendering.** World faces are near-plane clipped (so hugging a block
   never tears a hole), projected (`1/z`) and filled with their **128 px HD
   Minecraft texture** (perspective-correct atlas sampling, a mip-chain and
   **anisotropic filtering** for sharp near surfaces and shimmer-free
   distance), shaded by the baked corner light + shadows. Water draws as a
   sloped, scrolling surface with specular + Fresnel. Mobs are stacks of
   textured boxes with a walk-cycle bob, sharing the world z-buffer; a struck
   mob flashes red. The heart HUD, hotbar and crosshair are painted on top.
6. **Threading.** The work that used to stutter under load now runs in
   parallel: **audio** mixes on its own thread (no more crackle when a lot is
   happening), the **light** engine recomputes on its own thread, the world
   triangle queue is rasterised in **vertical tiles** across worker threads,
   and the sky / god-ray / bloom post-passes are split into row bands
   (`spawn` → `join`).
7. **Mobs.** `MobManager` keeps a live `Mob[]`, spawns animals on dry land in
   a ring around the player, steps each one's AI, despawns the distant, and
   resolves a left-click into damage on the nearest mob in the view cone.
   Each eases toward a target heading, alternates wandering with grazing,
   hops now and then, and bolts in a panic when hit (chickens flutter down
   slowly). Killing one plays a `dying` collapse (sink + squash + topple)
   before removal.

## Textures

Real Minecraft block textures are baked into `atlas.raw` as a vertical strip
of **128 px (HD)** tiles (grass top/side, dirt, stone, sand, snow, gravel,
oak/birch log side+top, leaves, water, …). The engine **loads `atlas.raw` at
runtime** (`sdl.loadAtlas`, tried from the project dir or `target/`) — it is
not embedded in the source, so textures can be re-baked without rebuilding.
`blocks.tileFor(id, dir)` maps a block face to its tile, the mesher stores
the tile per face, and `raster.rasterTriTex` samples it through the mip-chain
with anisotropic taps. Re-bake with `python bake_atlas.py` (reads the HD
resource pack, tints grass/leaves, writes `atlas.raw` to the root and
`target/`).

**Mobs** are skinned from the Minecraft entity textures under
`assets/textures/entity/`. `bake_mobs.py` crops a tile per body part and
appends them to the atlas; `config::useMobTextures` toggles textured vs
flat-colour mobs. Re-run `python bake_mobs.py` after editing the entity PNGs.

## Seams for new features

- **New block**: id in `configs/blocks`, tile/colour & predicates in
  `world/blocks`, place it in `manager`/`biome`.
- **New partial block** (slab, carpet): one `match` arm in
  `ChunkManager.blockBoxHeight` plus listing it in `blocks.isPartialShape` —
  collision, meshing, picking and the selection outline pick it up for free.
- **New biome**: a module under `world/biomes/` + an entry in the registry,
  with its climate band, surface/filler and tree density.
- **New animal**: a new `Entity` subclass (copy an existing one), a spawn
  case in `mobs`, and a draw case in `render`.
- **Editing the world** (dig / place): `ChunkManager.breakAt` / `placeAt`
  rewrite the chunk's voxel field (and neighbour skirts) and re-`buildMesh`
  the affected slots; the look-ray `Picker` (`game/ray.axle`) picks the
  targeted voxel against its real per-block box.

## Notes / limitations

- Collision is **voxel-accurate**: the body AABB is tested against every
  overlapping voxel (trunks and placed blocks included; leaf canopies stay
  passable), so overhangs and dug tunnels work. Partial blocks use their real
  box height.
- Edits are not persisted: a chunk that streams out of the loaded ring and
  back is regenerated, discarding edits made to it.
- The loop runs a **fixed timestep** (`config::tickHz`, default 60): the
  simulation advances by real elapsed time (catching up after a slow frame),
  so movement/jump speed is independent of the frame rate, and the frame
  clock (`platform::clock`) caps the CPU instead of relying on v-sync.
- `axle.toml`'s lib path is machine-specific; DLL + `atlas.raw` deployment
  next to the binary is manual.
