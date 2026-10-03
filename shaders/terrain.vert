#version 450
// terrain.vert — one corner of a world face, lit as the software renderer lights it.
//
// The CPU lights each corner of each face (`render/cpu/world/chunkview`, `emitSpan`)
// and interpolates the colour across the quad; so does this, per vertex, with the
// same formula (`shade::facelight`, `shade::cornerlight`). What the corner carries is
// written by `render/gpu/terrainmesh` when its chunk is meshed or its light rebaked:
//
//   position   chunk-local; the model matrix places the chunk
//   normal     xyz the face's; w the soft sun visibility at the corner, 0 .. 1 stored
//              across the whole snorm8 range (-1 .. 1), for 255 steps rather than 127
//   colour     rgb the one-bounce tint (byte / 128 is the multiplier), a the sky access;
//              on water, r and g are the flow along x and z instead (byte / 15 - 8)
//   layer      bits 0-7 the tile; 8-11 sky light, 12-15 / 16-19 / 20-23 block light
//              red / green / blue (0 .. 15 each); 24-25 the ambient occlusion (0 .. 3);
//              bit 26 water; bit 27 the texture tiles (a merged face, or water)
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
layout(location = 2) flat out uint vTile;
layout(location = 3) flat out uint vWrap;

// The brightness curve: FALLOFF^(15 - level), and nothing at level 0.
float curve(uint level) {
    return level == 0u ? 0.0 : pow(U_LIGHT_B.y, float(15u - level));
}

// The sky term's colour: warm where the sun reaches, cool where only the sky does,
// carrying the bounce where the light came by bouncing; hue only.
vec3 skyTint(float direct, vec3 sun, vec3 bounce) {
    float k = clamp(direct, 0.0, 1.0);
    float ind = 1.0 - k;
    vec3 shade = U_SHADE.rgb;
    vec3 c = (shade + (sun - shade) * k) * (1.0 + (bounce - 1.0) * ind);
    float l = max(0.299 * c.r + 0.587 * c.g + 0.114 * c.b, 0.0001);
    return c / l;
}

// The sun's own light coming back off a rough surface toward the eye.
float sunSheen(vec3 n, vec3 v, vec3 sun, float vis) {
    if (U_SHEEN.z < 0.5 || vis <= 0.0) {
        return 0.0;
    }
    vec3 h = v + sun;
    float hl = length(h);
    if (hl < 0.0001) {
        return 0.0;
    }
    float ndh = dot(n, h) / hl;
    if (ndh <= 0.0) {
        return 0.0;
    }
    float lobe = pow(ndh, U_SHEEN.x);
    float om = 1.0 - max(dot(n, v), 0.0);
    float om2 = om * om;
    return U_SHADE.w * lobe * vis * (1.0 + U_SHEEN.y * om2 * om2 * om);
}

void main() {
    vec4 world = dr.model * vec4(inPos, 1.0);
    gl_Position = fr.viewProj * world;

    vec3 n = inNormal.xyz;
    float vis = clamp(inNormal.w * 0.5 + 0.5, 0.0, 1.0);
    bool water = ((inLayer >> 26) & 1u) != 0u;
    vec3 toEye = fr.eye.xyz - world.xyz;

    // The face's two halves of light: the body's (Lambert), and the sky's (how much of
    // the dome the face can see). A water face seen from beneath is dimmer on both.
    float ndl = max(dot(n, U_DIR.xyz), 0.0);
    float skyView = U_LIGHT_A.y + (1.0 - U_LIGHT_A.y) * (0.5 + 0.5 * n.y);
    float direct = (1.0 - U_LIGHT_A.x) * ndl * U_DIR.w;
    float ambient = U_LIGHT_A.x * skyView * U_TINT.w;
    if (water && dot(toEye, n) <= 0.0) {
        direct *= 0.62;
        ambient *= 0.62;
    }
    float keep = U_LIGHT_A.w + (1.0 - U_LIGHT_A.w) * vis;
    float d = U_LIGHT_A.z * keep * direct;
    float bright = ambient + d;
    float share = (d + ambient) < 0.000001 ? 0.0 : d / (d + ambient);

    float skyAO = U_LIGHT_B.w + (1.0 - U_LIGHT_B.w) * inColor.a;
    float sky = curve((inLayer >> 8) & 15u) * skyAO;
    vec3 block = vec3(curve((inLayer >> 12) & 15u), curve((inLayer >> 16) & 15u), curve((inLayer >> 20) & 15u));
    float ao = 1.0 - U_LIGHT_B.z * float(3u - ((inLayer >> 24) & 3u)) / 3.0;
    vec3 bounce = water ? vec3(1.0) : inColor.rgb * (255.0 / 128.0);
    vec3 tint = skyTint(share, U_TINT.rgb, bounce);
    float lo = U_LIGHT_B.x * ao;
    float span = (1.0 - U_LIGHT_B.x) * ao;
    vec3 c = lo + span * (bright * sky * tint + block);

    vec3 v = toEye / max(length(toEye), 0.0001);
    vec2 uv = inUv;
    if (water) {
        // The sun's glint, and the sky's sheen at grazing angles.
        vec3 h = v + U_SUN.xyz;
        float ndh = max(dot(n, h) / max(length(h), 0.0001), 0.0);
        float s2 = ndh * ndh;
        float s4 = s2 * s2;
        float s8 = s4 * s4;
        float s16 = s8 * s8;
        float spec = s16 * s16 * vis * U_DIR.w * U_WATER.x;
        float om = 1.0 - max(dot(n, v), 0.0);
        float om2 = om * om;
        float fres = U_WATER.y + (1.0 - U_WATER.y) * om2 * om2 * om;
        float fboost = 1.0 + fres * U_WATER.z;
        c *= fboost * vec3(1.0 + spec * 1.10, 1.0 + spec * 1.00, 1.0 + spec * 0.72);
        vec2 flow = floor(inColor.rg * 255.0 + 0.5) / 15.0 - 8.0;
        uv += flow * U_SUN.w;
    } else {
        c += sunSheen(n, v, U_DIR.xyz, vis) * U_DIR.w * U_TINT.rgb;
    }

    vUv = uv;
    vLight = c;
    vTile = inLayer & 0xFFu;
    vWrap = (inLayer >> 27) & 1u;
}
