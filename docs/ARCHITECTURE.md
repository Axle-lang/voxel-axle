# Architecture

How the source tree is cut, which way dependencies are allowed to point, and
where a GPU renderer will plug in.

## The four roots

```
src/
  main.axle     dispatch: one of the headless checks, or the game
  engine/       the reusable voxel engine — never names a biome, a block rule or a species
  game/         the content the engine is dressed with, injected at startup
  app/          the running program: the window, the loop, input, the CLI
  checks/       headless regression checks, one flag each (`--physics-check` …)
  configs/      one class of `static` tunables per area, plus the content enums
```

`engine/` is split by domain:

```
engine/
  math/          vec3 · mathx · narrow (f32/u16 packing) · noise2 · noise3
  block/         the block table
    traits         the capability traits (Occluding, Collidable, Fluid, …)
    props          one value struct + `match id` factory per capability
    surface        per-face atlas tiles, bounce albedo, fallback colour
    box            BlockBox and `boxOf` — the one authority on a block's shape
    blocks         the free-function facade the rest of the engine calls
  world/         the streamed voxel world
    seams          the contracts the world provides (VoxelQuery, VoxelEdit, LightSample)
    ring           RingView — world cell → ring slot, the one copy of that walk
    voxstore       the voxel field + per-slot face watermark
    chunks         ChunkManager: streaming, edits, mesh flush; composes the rest
    mesh/          mesher (voxels → faces, torches, collision tops) · meshbuf
    light/         volumes · flood · sun · skyaccess · bake · sample · engine
    sim/           blocksim (falling blocks, flowing water)
  entity/        bodies
    seams          ActorVisual — what a creature exposes to whoever draws it
    model          BoxModel / BoxPart — a creature's body as data
    entity         physics shared by player and mobs
    player · mob · mobs
  shade/         backend-neutral shading formulas: gamma, corner light, face
                 light, the day model (sun direction, sky colours, curve)
  sky/           backend-neutral sky MODEL: atmosphere (SkyDome), cloud field,
                 cloud light on the ground, view ray
  render/
    view/          backend-neutral: View, Camera, Lens, Projected · frustum
    cpu/           the software renderer
      renderer       the frame conductor
      raster/        framebuf · triangle · mip
      world/         chunkview (terrain faces → triangle queues → banded fill)
      mobs/          mobview (draws the BoxModel each actor describes)
      sky/           the sky PAINTER: skyengine · backdrop · fogtables ·
                     viewrays · clouddome (read side) · cloudsky (marcher)
      atlas · bloom · postfx · selection
  ui/            the overlay, drawn through smalt's `Frame`: hud · health ·
                 hotbar · menu · uiscale · widget
  audio/         sfx
  io/            input · assets
```

## Dependency rule

Dependencies point down this list and never up:

```
configs, smalt
  └ engine/math
      └ engine/block, engine/shade, engine/sky        (models — no pixels, no threads)
          └ engine/world                              (may read the sky model: cloud shadows)
              └ engine/entity, engine/audio, engine/io
                  └ engine/render/view                (neutral: camera, frustum)
                      └ engine/render/cpu, engine/ui  (the backend and the overlay)
                          └ game                      (content: implements the engine's seams)
                              └ app                   (wires everything, runs the loop)
                                  └ checks, main
```

What that rule means in practice, and what it bought:

- **Nothing in `engine/` imports `game/`, `app/` or `checks/`.** Content
  reaches the engine through injection seams declared next to their consumer:
  `Generator` (world::chunks), `MobSpawner` (entity::mob), and
  `ActorVisual.buildModel` (entity::seams), which each species overrides.
- **Nothing under `engine/render` or `engine/sky` names the player.** The app
  hands the renderer a `View` once a frame (`app/view.axle` is the one place
  that maps the body to the eye); the renderer builds the frame's `Camera` from
  it and every pass projects through that one value.
- **The sky model does not import the renderer.** `sky/atmosphere` answers a
  direction's colour; the pixel-to-direction inverse, the dithered packing and
  the screen-space fog grid are the CPU painter's and live under `render/cpu/sky`.
- **Adding an animal touches no engine file** for its looks: a class in
  `game/entities` with its `buildModel`, a spawn weight in `Fauna`, tiles in the
  atlas. (Its voice is still in `engine/audio/sfx` — see *Known debts*.)

Same-domain files may import each other freely. A `seams.axle` file holds the
contracts its domain *provides*; injection seams live with their consumer.

## Where a GPU renderer goes

The cut above is the one a second backend needs. `render/view`, `shade` and
`sky` are shared; a GPU backend is a sibling of `render/cpu`:

```
engine/render/
  view/   shared — Camera (→ view/projection matrices), frustum (→ draw list)
  cpu/    software rasteriser
  gpu/    the new backend, on smalt's `gpu::Renderer` (Vulkan, software fallback)
```

What each piece becomes on the GPU side:

| Today (CPU) | GPU counterpart |
|---|---|
| `render/view::Camera`, `frustum` | shared as is: uniforms + per-chunk draw list |
| `sky::atmosphere::SkyDome`, `shade::daymodel::DayState` | uniforms of a fullscreen sky pass |
| `render/cpu/sky/*` (painter, fog grid, cloud table) | the sky shader (and a compute pass for the cloud march) |
| `entity::model::BoxModel` | per-instance box data |
| `world::mesh` face records (`meshbuf`) | per-chunk instanced-quad buffers |
| `world::light::volumes` | 3-D textures sampled per fragment |
| `render/cpu/{bloom,postfx}` | post-process passes |
| `ui/*` drawn into `Frame` | smalt's overlay layer (see the caveat below) |

Steps that remain before a GPU backend can be written, in order:

1. **A `RenderBackend` seam** (`beginFrame(FrameView)`, `submit(scene)`,
   `post()`, `overlay()`, `present()`), implemented by the CPU renderer, held as
   a one-slot `dyn RenderBackend[]` (a trait-typed field cannot hold a class).
2. **Make the chunk mesh self-contained.** Today `render/cpu/world/chunkview`
   re-reads the world every frame for sun visibility, sky access, bounce, water
   corner heights and partial-block heights, and splits quads along shadow
   edges. A retained GPU mesh cannot: bake the static terms (water heights,
   block heights, flood light, AO) into the face record, sample the sun / sky /
   bounce volumes per fragment, and add a per-slot mesh generation counter so a
   backend knows when to re-upload.
3. **Overlay on a transparent layer.** smalt's GPU overlay treats 0 as
   transparent, so the pause dim and black drop shadows must change, the
   crosshair must become a `Frame` op, and the selection outline belongs in the
   3-D pass (it needs depth).

## Verifying a refactor

The headless checks are the safety net, and most of them print enough to be
diffed byte for byte:

```bash
axle build -O 3
./target/voxel --physics-check   # body vs real terrain
./target/voxel --light-check     # flood, shadows, cloud light, against a real ring
./target/voxel --biome-scan      # biome tally over a wide grid
./target/voxel --cull-check      # frustum never drops a visible chunk
./target/voxel --model-check     # every species describes a body
```

Capture their output before a structural change and `diff` it after: a pure
restructure leaves them identical. They do not exercise the game loop or the
renderer, so finish with one pinned capture:
`./target/voxel --snap 4000 --at 294456 109296 --look 225 -8 --daytime 0.42`.

## Known debts

Kept here so they are not mistaken for the design:

- `engine/entity/mob` imports `world::sim::BlockSim` and `audio::sfx` because a
  `think` step can explode (the creeper) and every mob can speak; both belong
  behind seams.
- `engine/audio/sfx` lists one line per species (`mobVoice("chicken")`), and
  `MobKind` / `Mobs::KIND_COUNT` live in `configs`, so a new species still
  touches both; a species left out is silent rather than a stray read.
- The game sometimes ends with a segfault after it has finished (seen on
  `main` before this layout, intermittent, after `--snap` has written its
  capture). The worker threads are stopped and joined before anything is
  released, so the suspect is the teardown of the composed objects; it needs a
  debugger, not more guessing.
- Nothing allocated with `Mem::take` is released at shutdown (the light
  volumes, the mesh, the sky tables). Harmless for a process that is exiting,
  but a renderer that can be torn down and rebuilt — a GPU backend falling back
  to software — will need `close()` all the way down.
- `render/cpu/world/chunkview` (1250 lines) mixes scene extraction (corner
  probes, water heights, shadow-run splitting) with CPU clipping and queueing;
  it splits along a `FaceSink` seam as part of GPU step 2.
- The headless checks build into the release binary; an Axle workspace
  (core lib + game bin + checks bin) would keep them out.
