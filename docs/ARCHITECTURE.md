# Architecture

How the source tree is cut, which way dependencies are allowed to point, and
how a frame gets from the game to a backend.

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
    light/         volumes (the flood's levels) · flood · surface (what the ray bakes
                   leave, per column, only where faces read it) · sun · skyaccess ·
                   bake · sample · engine
    sim/           blocksim (falling blocks, flowing water)
  entity/        bodies
    seams          ActorVisual — what a creature exposes to whoever draws it
    model          BoxModel / BoxPart — a creature's body as data
    entity         physics shared by player and mobs
    player · mob · mobs
  shade/         backend-neutral shading formulas: gamma, corner light, face
                 light, the day model (sun direction, sky colours, curve)
  sky/           backend-neutral sky MODEL: atmosphere (SkyDome), cloud field,
                 cloud light on the ground, view ray, the cloud deck
                 (cloudsky marches it, clouddome reads it)
  render/
    backend        RenderBackend — the one call the game makes per frame
    view/          backend-neutral: View, Camera, Lens, Projected · frustum
    frame/         backend-neutral: what a frame shows, decided once
      framedesc      FrameDesc — camera, hour, deck, creature boxes, torches,
                     aimed block, HUD state
      framebuilder   FrameBuilder — reads the game into a FrameDesc
      boxpose        where a creature's box stands (corners, faces, the light on
                     each), and a torch as a box
    cpu/           the software backend
      cpubackend     CpuBackend — the target, the pass order, the overlay
      renderer       SoftRenderer — the passes it composes
      raster/        framebuf · triangle · mip
      world/         chunkview (terrain faces → triangle queues → banded fill)
      mobs/          mobview (draws the frame's creature boxes)
      sky/           the sky PAINTER: skyengine · backdrop · fogtables · viewrays
      atlas · bloom · postfx · selection
    gpu/           the GPU backend, on smalt's `Renderer`
      gpubackend     GpuBackend — the scene, its passes, the overlay
      terrainmesh    one chunk's faces → the terrain shader's vertices
      terrainmeshes  the ring's meshes, rebuilt when a chunk's mesh or light moves
      entitymesh     creatures, torches and the outline, one mesh a frame
      uniforms       the frame's `user` vectors (`shaders/voxel.glsl` reads them)
      clouddeck      the cloud deck as a texture
      voxelshaders   the shaders, uploaded · spirv (generated from `shaders/`)
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
      └ engine/block, engine/shade, engine/sky        (models — no pixels)
          └ engine/world                              (may read the sky model: cloud shadows)
              └ engine/entity, engine/audio, engine/io
                  └ engine/render/view                (neutral: camera, frustum)
                      └ engine/render/frame           (neutral: reads the game into a frame)
                          └ engine/render/cpu, engine/render/gpu, engine/ui
                                                      (the backends, and the overlay they draw)
                              └ game                  (content: implements the engine's seams)
                                  └ app               (wires everything, runs the loop)
                                      └ checks, main
```

What that rule means in practice, and what it bought:

- **Nothing in `engine/` imports `game/`, `app/` or `checks/`.** Content
  reaches the engine through injection seams declared next to their consumer:
  `Generator` (world::chunks), `MobSpawner` (entity::mob), and
  `ActorVisual.buildModel` (entity::seams), which each species overrides.
- **Nothing under `engine/render` or `engine/sky` names the player.** The app
  hands the frame builder a `View` once a frame (`app/view.axle` is the one
  place that maps the body to the eye); the frame's `Camera` is built from it
  and every pass projects through that one value.
- **A backend reads the game only through its frame.** `engine/render/cpu`
  and `engine/render/gpu` import no creature, not the world's manager, light
  or block sim, and not the frame builder; the world reaches them read-only
  through `world::seams::TerrainView`. Neither names the other.
- **The sky model does not import the renderer.** `sky/atmosphere` answers a
  direction's colour; the pixel-to-direction inverse, the dithered packing and
  the screen-space fog grid are the CPU painter's and live under `render/cpu/sky`.
- **Adding an animal touches no engine file** for its looks: a class in
  `game/entities` with its `buildModel`, a spawn weight in `Fauna`, tiles in the
  atlas. (Its voice is still in `engine/audio/sfx` — see *Known debts*.)

Same-domain files may import each other freely. A `seams.axle` file holds the
contracts its domain *provides*; injection seams live with their consumer.

`tools/check_layers.sh` enforces the engine-below-game rule and the backend
rules (`--selftest` proves each rule rejects what it is for).

## One frame, one call

The game calls one function to put a frame on screen:

```
const frame = self.frames.build(FrameSource { man, mobs }, FrameRequest { view, clock, aim, hud });
self.backend[0].draw(frame, self.man, self.display.win);
```

`FrameBuilder.build` is where everything a frame shows is decided, once: the
hour's light, the camera, the cloud deck (the one piece of state a frame moves
on — it is marched here, and how fast depends on whether the sky can be seen,
judged from the view and the world rather than from what a backend painted),
every creature's boxes and the light it stands in, the torches in view, the
aimed block's outline, the HUD. `RenderBackend.draw` translates that into
pixels and decides nothing the game reads back. Two backends handed the same
frame cannot disagree about what is in it, and a change to the game is made
on the frame side, once.

`--frame-check` prints what a swept set of frames contains, so a change to
what is drawn shows up there, for every backend at once.

## The GPU backend

`render/gpu` is a second `RenderBackend`, on smalt's `Renderer` (Vulkan). At
start-up the game opens it (`app/session/boot.openBackend`) and falls back to
the software one when there is no GPU; `--cpu` asks for the software one,
`--gpu` for the GPU and nothing else. A GPU lost mid-run hands over to the
software backend too.

It draws the same `FrameDesc` with the same arithmetic. The light is not
approximated: the shaders in `shaders/` are the CPU's formulas
(`shade::gamma`, `shade::facelight`, `shade::cornerlight`,
`sky::atmosphere`, `sky::clouddome`, `render/cpu/postfx`) written again,
line for line, and `shaders/voxel.glsl` says so at its top. A change to one
of those is a change to both.

Where the two still differ, on purpose:

- a texture seen from afar is filtered by the GPU's trilinear and
  anisotropic sampler, not the CPU's mip and tap choice (up close both read
  the full-size tile the same way);
- the bloom runs at full resolution with twice the radius, where the CPU
  blurs at half resolution;
- the fog's sky is computed per pixel, where the CPU interpolates a coarse
  grid;
- the GPU draws faces past `DRAW_DIST` (wholly fogged) that the CPU skips;
- water faces take no bounce tint (their colour bytes carry the flow);
- the aimed block's outline is in the 3-D scene, so it is fogged and
  bloomed with it, where the CPU draws it after the post effects.

Two pinned captures show the same cloud deck only when they drew about as
many frames before the capture: the deck is marched a slice a frame. The
`--snap` report gives the count (`over N builds`); a slower start means a
different sky, not a different renderer.

| CPU | GPU |
|---|---|
| `chunkview` lights each face corner every frame | `terrainmesh` copies what a corner reads of the light volumes into its vertex when the chunk's mesh (`meshGen`) or light (`lightGen`) changes; `terrain.vert` does the rest per frame |
| shadow runs split per frame | split the same way when the chunk is meshed |
| `mobview`, `renderTorches`, `selection` | `entitymesh`, one mesh a frame, from the same `boxpose` |
| the sky painter | `sky.frag` (a background), the deck a texture rewritten each frame |
| fog tables | `fog.frag`, a pass reading the depth |
| `postfx`, `bloom` | `godrays`, `underwater`, `bright` / `blur` / `composite` passes |
| `drawHud`, `drawPauseMenu` into the framebuffer | the same calls into smalt's overlay; the pause veil is a pass |
| `--snap` writes the framebuffer | smalt reads the frame back |

Coordinates on the GPU are measured from the eye's chunk corner, so a 32-bit
float keeps its precision far from the origin; chunk meshes are chunk-local.

The shaders are compiled into `render/gpu/spirv.axle` by
`tools/build_shaders.sh <glslang>` (smalt's `tools/spirv_tables.py`); the
Axle build does not run it. The frame's `user` vectors are one contract
between `render/gpu/uniforms.axle` and `shaders/voxel.glsl`.

## Verifying a refactor

The headless checks are the safety net, and most of them print enough to be
diffed byte for byte:

```bash
axle build -O 3
./target/voxel --physics-check   # body vs real terrain
./target/voxel --light-check     # flood, shadows, cloud light, against a real ring
./target/voxel --biome-scan      # biome tally over a wide grid
./target/voxel --cull-check      # frustum never drops a visible chunk
./target/voxel --frame-check     # what a swept set of frames contains
./target/voxel --surface-check   # the baked sun, sky access and bounce every face reads
./target/voxel --model-check     # every species describes a body
tools/check_layers.sh            # the dependency rules above
```

Capture their output before a structural change and `diff` it after: a pure
restructure leaves them identical. They do not exercise the game loop or the
renderer, so finish with one pinned capture on each backend, side by side:
`./target/voxel --cpu --snap 4000 --at 294456 109296 --look 225 -8 --daytime 0.42`,
then the same with `--gpu`.

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
  levels and surface tables, the mesh, the sky tables). Harmless for a process that is exiting,
  but a renderer that can be torn down and rebuilt — a GPU backend falling back
  to software — will need `close()` all the way down.
- `render/cpu/world/chunkview` (about 1050 lines) mixes scene extraction
  (corner probes, shadow-run splitting) with CPU clipping and queueing; it
  splits along a `FaceSink` seam as part of GPU step 2.
- The headless checks build into the release binary; an Axle workspace
  (core lib + game bin + checks bin) would keep them out.
