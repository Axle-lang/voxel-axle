// tile.glsl — sampling a tile of the atlas the way the software renderer does.
//
// Fragment stages only (it takes screen-space derivatives). Included after `voxel.glsl`.

// ── A tile of the atlas, crisp up close (the CPU's sharp bilinear) ─────────────

// Magnified, a texel is a square with a one-pixel soft edge, read from the full-size
// level; minified, the sampler's own trilinear and anisotropic filtering. A face that
// does not tile its texture (`wrap` false: not merged, not water) stops at the tile's
// edge rather than blending into the opposite one, as the CPU clamps it.
vec4 sampleTile(sampler2DArray atlas, vec2 uv, float layer, bool wrap) {
    vec2 size = vec2(textureSize(atlas, 0).xy);
    vec2 px = uv * size;
    vec2 dx = dFdx(px);
    vec2 dy = dFdy(px);
    float minor2 = min(dot(dx, dx), dot(dy, dy));
    if (minor2 > 1.0) {
        return texture(atlas, vec3(uv, layer));
    }
    float sharp = minor2 > 0.0000001 ? clamp(inversesqrt(minor2), 1.0, 16.0) : 16.0;
    float r = 0.5 - 0.5 / sharp;
    vec2 fl = floor(px);
    vec2 d = px - fl - 0.5;
    vec2 s = fl + 0.5 + (d - clamp(d, -r, r)) * sharp;
    if (!wrap) {
        s = clamp(s, vec2(0.5), size - 0.5);
    }
    return textureLod(atlas, vec3(s / size, layer), 0.0);
}
