#version 450
// dim.frag — the frame behind the pause menu, darkened by `dr.user.x`.
#extension GL_GOOGLE_include_directive : require
#include "frame.glsl"
#include "post.glsl"

layout(location = 0) out vec4 outColor;

void main() {
    outColor = vec4(texture(prevColor, vUv).rgb * dr.user.x, 1.0);
}
