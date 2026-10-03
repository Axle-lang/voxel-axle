#version 450
// blur.frag — one direction of the bloom's box blur: the mean of the pass before over a
// run of pixels along `dr.user.xy`, the bloom's radius either side.
#extension GL_GOOGLE_include_directive : require
#include "frame.glsl"
#include "voxel.glsl"
#include "post.glsl"

layout(location = 0) out vec4 outColor;

void main() {
    int r = int(U_BLOOM.z);
    ivec2 size = ivec2(fr.target.xy);
    ivec2 p = ivec2(gl_FragCoord.xy);
    ivec2 dir = ivec2(dr.user.xy);
    vec3 sum = vec3(0.0);
    for (int k = -r; k <= r; ++k) {
        ivec2 q = clamp(p + dir * k, ivec2(0), size - 1);
        sum += texelFetch(prevColor, q, 0).rgb;
    }
    outColor = vec4(sum / float(2 * r + 1), 1.0);
}
