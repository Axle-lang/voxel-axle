#version 450
// entity.frag — a textured or flat face of a creature, a torch or an outline: its colour
// in linear light times its face's light, through the tone curve. Fogged by the frame's
// fog pass with the terrain.
#extension GL_GOOGLE_include_directive : require
#include "frame.glsl"
#include "voxel.glsl"
#include "tile.glsl"

layout(set = 1, binding = 0) uniform sampler2DArray atlas;

layout(location = 0) in vec2 vUv;
layout(location = 1) in vec3 vLight;
layout(location = 2) flat in uint vWord;

layout(location = 0) out vec4 outColor;

void main() {
    uint tile = vWord & 0xFFu;
    vec3 base;
    if (tile == 255u) {
        uint rgb = vWord >> 8;
        base = toLinear(vec3(float((rgb >> 16) & 0xFFu), float((rgb >> 8) & 0xFFu), float(rgb & 0xFFu)) / 255.0);
    } else {
        base = sampleTile(atlas, vUv, float(tile), false).rgb;
    }
    outColor = vec4(encode(base * vLight), 1.0);
}
