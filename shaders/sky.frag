#version 450
// sky.frag — the background behind everything: the dome's gradient and halo, the cloud
// deck over it, the sun and the moon (`render/cpu/sky/backdrop` on the CPU). In display
// units, rolled off at the shoulder and dithered, as the CPU packs it. Under water there
// is no sky: the deep water's colour.
#extension GL_GOOGLE_include_directive : require
#include "frame.glsl"
#include "voxel.glsl"

layout(set = 1, binding = 0) uniform sampler2DArray deck;

layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 outColor;

// A sun texel: white-hot at the centre, gold at the rim.
vec3 sunTexel(float nd) {
    return vec3(255.0, floor(253.0 - 42.0 * nd), floor(218.0 - 150.0 * nd));
}

// A moon texel: a pale disc darkened inside two faint maria.
vec3 moonTexel(vec2 d, float radius) {
    float m1 = length(d + radius * vec2(0.30, 0.32));
    float m2 = length(d - radius * vec2(0.36, 0.10));
    if (m1 < radius * 0.26 || m2 < radius * 0.20) {
        return vec3(198.0, 206.0, 220.0);
    }
    return vec3(226.0, 231.0, 240.0);
}

// The body in `disc` over `back`, hidden behind the deck along `dir` as the CPU hides it.
vec3 overlayDisc(vec4 disc, vec3 back, vec3 dir, bool sun) {
    if (disc.w < 0.5) {
        return back;
    }
    vec2 centre = disc.xy * fr.target.xy;
    float radius = disc.z * fr.target.y;
    vec2 d = gl_FragCoord.xy - centre;
    if (dot(d, d) > radius * radius) {
        return back;
    }
    vec3 c = sun ? sunTexel(length(d) / radius) : moonTexel(d, radius);
    vec4 cl = cloudSample(deck, dir);
    if (cl.a > 0.002) {
        c = floor(c * (1.0 - cl.a) + back * cl.a);
    }
    return c;
}

void main() {
    if (U_HORIZON.w > 0.5) {
        outColor = vec4(U_DEEP.rgb / 255.0, 1.0);
        return;
    }
    vec3 dir = viewRay(vUv);
    vec3 c = skyWithCloud(deck, dir);
    float d = dither(ivec2(gl_FragCoord.xy));
    vec3 s = clamp(floor(shoulderRgb(c) + d), 0.0, 255.0);
    s = overlayDisc(U_SUN_DISC, s, U_SUN.xyz, true);
    s = overlayDisc(U_MOON_DISC, s, -U_SUN.xyz, false);
    outColor = vec4(s / 255.0, 1.0);
}
