#version 450
// underwater.frag — a living volume of water: fog toward the water's colour by depth, a
// moving caustic pattern, and rising bubbles (`render/cpu/postfx`, `UnderwaterFX`).
#extension GL_GOOGLE_include_directive : require
#include "frame.glsl"
#include "voxel.glsl"
#include "post.glsl"

layout(location = 0) out vec4 outColor;

// Whether a bubble covers pixel `p` this frame.
bool bubbleAt(ivec2 p, ivec2 size, float phase) {
    int nb = int(U_BUBBLES.x);
    for (int bi = 0; bi < nb; ++bi) {
        int hx = (bi * 1664525 + 1013904223) & 0x7FFFFFFF;
        int hp = ((bi + 1) * 22695477 + 13) & 0x7FFFFFFF;
        int hs = ((bi + 7) * 40503 + 101) & 0x7FFFFFFF;
        float sp = 0.5 + float(hs % 1000) * 0.001;
        int trav = int(floor(phase * U_BUBBLES.y * sp));
        int yy = size.y - 1 - (((hp + trav) & 0x7FFFFFFF) % size.y);
        float wob = sin(phase * 0.4 + float(bi) * 1.7 + float(yy) * 0.07) * 3.0;
        int bx = (hx % size.x) + int(floor(wob));
        if (p == ivec2(bx, yy)) {
            return true;
        }
        if ((hs & 1) == 0 && (p == ivec2(bx + 1, yy) || p == ivec2(bx, yy - 1))) {
            return true;
        }
    }
    return false;
}

void main() {
    vec3 prev = bytesAt(prevColor, vUv);
    float depthRaw = texture(sceneDepth, vUv).r;
    float far = U_WATER_FOG.w;
    float depth = far;
    if (depthRaw < 1.0) {
        depth = dot(worldAt(vUv, depthRaw) - fr.eye.xyz, U_FORWARD.xyz);
    }
    float fog = min(depth / far, 1.0) * U_WATER_FX.x;
    float phase = U_WATER_FX.w;
    vec2 p = floor(gl_FragCoord.xy);
    float caustic = (sin(p.x * U_WATER_FX.y + phase) + sin(p.y * U_WATER_FX.y - phase * 1.3)) * U_WATER_FX.z;
    vec3 c = clamp(floor(prev * (1.0 - fog) + U_WATER_FOG.rgb * fog + caustic), 0.0, 255.0);
    if (bubbleAt(ivec2(p), ivec2(fr.target.xy), phase)) {
        c = floor((c + vec3(200.0, 228.0, 244.0)) * 0.5);
    }
    outColor = vec4(c / 255.0, 1.0);
}
