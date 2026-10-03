#version 450
// terrain.frag — the tile's texel, in linear light, times the corner light the vertex
// stage worked out, through the tone curve to a display value. Unfogged: the fog is a
// pass over the whole frame (`fog.frag`), so the terrain and the creatures dissolve
// into the same sky.
#extension GL_GOOGLE_include_directive : require
#include "frame.glsl"
#include "voxel.glsl"
#include "tile.glsl"

layout(set = 1, binding = 0) uniform sampler2DArray atlas;

layout(location = 0) in vec2 vUv;
layout(location = 1) in vec3 vLight;
layout(location = 2) flat in uint vTile;
layout(location = 3) flat in uint vWrap;

layout(location = 0) out vec4 outColor;

void main() {
    vec3 texel = sampleTile(atlas, vUv, float(vTile), vWrap != 0u).rgb;
    outColor = vec4(encode(texel * vLight), 1.0);
}
