#!/usr/bin/env bash
# build_shaders.sh — regenerate src/engine/render/gpu/spirv.axle from shaders/.
#
# Usage:  tools/build_shaders.sh <path to glslang>
#
# Uses smalt's `tools/spirv_tables.py`, with smalt's `shaders/` on the include path for
# `frame.glsl` and `post.glsl`.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
glslang="${1:?usage: tools/build_shaders.sh <path to glslang>}"
# PYTHON overrides the interpreter; otherwise python3, or python where that is all there is.
python="${PYTHON:-$(command -v python3 || command -v python)}"
cd "$root"
"$python" vendor/smalt/tools/spirv_tables.py --glslang "$glslang" --include shaders \
    -I vendor/smalt/shaders \
    --out src/engine/render/gpu/spirv.axle --class Spirv --visibility "pub(crate)" \
    --header shaders/spirv_header.txt --doc "voxel's compiled GPU stages." \
    "terrain.vert:terrainVert:A world face's corner, lit as the CPU lights it" \
    "terrain.frag:terrainFrag:A world face's texel under its corner light" \
    "entity.vert:entityVert:A creature's, a torch's or an outline's corner" \
    "entity.frag:entityFrag:A creature's, a torch's or an outline's texel" \
    "sky.frag:sky:The sky, the deck, the sun and the moon" \
    "fog.frag:fog:Aerial perspective, toward the sky behind each surface" \
    "godrays.frag:godRays:Crepuscular shafts from the sun" \
    "underwater.frag:underwater:The water's fog, caustics and bubbles" \
    "bright.frag:bright:The bloom's extract" \
    "blur.frag:blur:One direction of the bloom's blur" \
    "composite.frag:composite:The bloom added back" \
    "dim.frag:dim:The frame behind the pause menu, darkened"
