#version 450
// entity.vert — one corner of a creature's box, a torch post, or the aimed block's
// outline, lit by what the CPU worked out for its face (`render/gpu/entitymesh`):
//
//   position   render-origin relative
//   colour     rgb the face's light, byte / 127 — 1.0 exactly at 127, and up to 2 for a
//              torch's glow or a struck creature's red (past it is clipped)
//   layer      bits 0-7 the tile, or 255 for a flat face; for a flat face bits 8-31 are
//              its colour, 0xRRGGBB
#extension GL_GOOGLE_include_directive : require
#include "frame.glsl"
#include "voxel.glsl"

layout(location = 0) in vec3 inPos;
layout(location = 1) in vec2 inUv;
layout(location = 2) in vec4 inNormal;
layout(location = 3) in vec4 inColor;
layout(location = 4) in uint inLayer;

layout(location = 0) out vec2 vUv;
layout(location = 1) out vec3 vLight;
layout(location = 2) flat out uint vWord;

void main() {
    gl_Position = fr.viewProj * dr.model * vec4(inPos, 1.0);
    vUv = inUv;
    vLight = inColor.rgb * (255.0 / 127.0);
    vWord = inLayer;
}
