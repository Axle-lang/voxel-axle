#version 450
// fog.frag — aerial perspective: every surface dissolves into the sky behind it, by how
// deep it stands (`render/cpu/sky/fogtables` on the CPU) — the sky as it is painted, rolled
// off at the shoulder, so a fogged silhouette meets the sky without a seam. The background
// is left alone.
#extension GL_GOOGLE_include_directive : require
#include "frame.glsl"
#include "voxel.glsl"
#include "post.glsl"

layout(location = 0) out vec4 outColor;

void main() {
    vec3 prev = bytesAt(prevColor, vUv);
    float depth = texture(sceneDepth, vUv).r;
    if (depth >= 1.0) {
        outColor = vec4(prev / 255.0, 1.0);
        return;
    }
    vec3 world = worldAt(vUv, depth);
    vec3 rel = world - fr.eye.xyz;
    float z = dot(rel, U_FORWARD.xyz);
    float t = z / U_FOG.x;
    float fog = z >= U_FOG.y ? 1.0 : 1.0 - exp(-t * t);
    if (z < 0.0 || fog <= 0.002) {
        outColor = vec4(prev / 255.0, 1.0);
        return;
    }
    vec3 sky = shoulderRgb(skyWithCloud(tex, rel / max(length(rel), 0.0001)));
    vec3 c = floor(prev * (1.0 - fog) + sky * fog);
    outColor = vec4(clamp(c, 0.0, 255.0) / 255.0, 1.0);
}
