#version 450
// bright.frag — the first step of the bloom: what is brighter than the threshold, by how
// much it is (`render/cpu/bloom`, its extract).
#extension GL_GOOGLE_include_directive : require
#include "frame.glsl"
#include "voxel.glsl"
#include "post.glsl"

layout(location = 0) out vec4 outColor;

void main() {
    vec3 c = bytesAt(prevColor, vUv);
    float lum = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
    float thr = U_BLOOM.x;
    vec3 b = lum > thr ? c * ((lum - thr) / lum) : vec3(0.0);
    outColor = vec4(b / 255.0, 1.0);
}
