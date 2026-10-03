#version 450
// godrays.frag — crepuscular shafts: each pixel marches toward the sun on screen and
// counts the sky it crosses, with decay, and gains the halo's colour by that much
// (`render/cpu/postfx`, `GodRayFX`). Run only when the sun is up and in front.
#extension GL_GOOGLE_include_directive : require
#include "frame.glsl"
#include "voxel.glsl"
#include "post.glsl"

layout(location = 0) out vec4 outColor;

void main() {
    vec3 prev = bytesAt(prevColor, vUv);
    int n = int(U_RAYS.w);
    vec2 size = fr.target.xy;
    vec2 sun = U_RAYS.xy * size;
    vec2 p = floor(gl_FragCoord.xy);
    vec2 step = (sun - p) / float(n) * U_RAYS_B.y;
    vec2 at = p;
    float illum = 0.0;
    float dec = 1.0;
    for (int i = 0; i < n; ++i) {
        at += step;
        ivec2 ix = ivec2(floor(at));
        if (ix.x >= 0 && ix.y >= 0 && ix.x < int(size.x) && ix.y < int(size.y)
            && texelFetch(sceneDepth, ix, 0).r >= 1.0) {
            illum += dec;
        }
        dec *= U_RAYS_B.x;
    }
    float f = illum / float(n) * U_RAYS.z;
    vec3 c = min(prev + floor(U_HALO.rgb * f), 255.0);
    outColor = vec4(c / 255.0, 1.0);
}
