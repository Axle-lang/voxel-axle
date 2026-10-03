#version 450
// composite.frag — the bloom added back over the frame it was taken from, where it shows.
#extension GL_GOOGLE_include_directive : require
#include "frame.glsl"
#include "voxel.glsl"
#include "post.glsl"

layout(location = 0) out vec4 outColor;

void main() {
    vec3 base = bytesAt(baseColor, vUv);
    vec3 add = texture(prevColor, vUv).rgb * 255.0 * U_BLOOM.y;
    vec3 c = base;
    if (add.r > 0.5 || add.g > 0.5 || add.b > 0.5) {
        c = min(base + floor(add), 255.0);
    }
    outColor = vec4(c / 255.0, 1.0);
}
