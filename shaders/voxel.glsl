// voxel.glsl — what voxel's own GPU stages share.
//
// Two things, both of which exist once on the CPU and once here, and must agree:
//
//   * the meaning of the frame's `user` vectors — written by
//     `src/engine/render/gpu/uniforms.axle` in exactly this order;
//   * the colour arithmetic of the software renderer: the colour space and tone curve
//     (`shade::gamma`), the light at a face corner (`shade::facelight`,
//     `shade::cornerlight`), the sky's colour along a direction (`sky::atmosphere`), the
//     cloud deck as it is read (`sky::clouddome`) — the same formulas, line for line. A
//     change to one of those is a change here too; a pinned `--snap --gpu` against
//     `--snap --cpu` is how the two are held together.
//
// Where the two still differ, and why: the GPU filters a texture it minifies with the
// hardware's trilinear and anisotropic taps, not the CPU's mip and tap choice; it blooms
// at full resolution with twice the radius, where the CPU blurs at half; it reads the
// fog's sky exactly per pixel, where the CPU interpolates a coarse grid.
//
// Included after smalt's `frame.glsl`.

// ── The frame's vectors ────────────────────────────────────────────────────────

#define U_DIR        fr.user[0]   // the body's direction (unit), its strength
#define U_TINT       fr.user[1]   // the body's tint rgb, the sky's ambient share
#define U_SUN        fr.user[2]   // the SUN's direction (unit), water flow scroll
#define U_LIGHT_A    fr.user[3]   // AMBIENT, SKY_VIEW_MIN, SUN_STRENGTH, SHADOW_KEEP
#define U_LIGHT_B    fr.user[4]   // MIN, FALLOFF, AO_STRENGTH, AO_SKY_MIN
#define U_SHADE      fr.user[5]   // SHADE_TINT rgb, SHEEN_STRENGTH
#define U_SHEEN      fr.user[6]   // SHEEN_EXP, SHEEN_GRAZE, sheen on, TONE_KNEE
#define U_WATER      fr.user[7]   // SPEC_STRENGTH, F0, FRESNEL_STRENGTH, TONE_MAX
#define U_ZENITH     fr.user[8]   // the dome's zenith rgb (display units), halo fade
#define U_HORIZON    fr.user[9]   // the dome's horizon rgb (display units), under water
#define U_HALO       fr.user[10]  // SKY_HALO rgb, SKY_HALO_STRENGTH
#define U_CORE       fr.user[11]  // SKY_CORE_THRESH, SKY_CORE_STRENGTH, SKY_SHOULDER, clouds on
#define U_CAMERA     fr.user[12]  // cos yaw, sin yaw, cos pitch, sin pitch
#define U_LENS       fr.user[13]  // half width / focal, half height / focal
#define U_SUN_DISC   fr.user[14]  // centre x, y (fractions of the target), radius / height, shown
#define U_MOON_DISC  fr.user[15]  // ... the moon's
#define U_DECK_DIR   fr.user[16]  // the deck light's direction
#define U_DECK_BODY  fr.user[17]  // the body's light on the deck
#define U_DECK_SKY   fr.user[18]  // the sky's light on the deck
#define U_DECK_GND   fr.user[19]  // the ground's light thrown up into it
#define U_PHASE      fr.user[20]  // PHASE_G, PHASE_BACK, PHASE_FWD_W, PHASE_MAX
#define U_FOG        fr.user[21]  // FOG_SCALE, DRAW_DIST
#define U_FORWARD    fr.user[22]  // the camera's forward direction (unit)
#define U_DEEP       fr.user[23]  // the deep water's rgb (display units)
#define U_WATER_FOG  fr.user[24]  // the water fog's rgb (display units), FOG_FAR
#define U_WATER_FX   fr.user[25]  // FOG_MAX, CAUSTIC_FREQ, CAUSTIC_AMP, the water's phase
#define U_BUBBLES    fr.user[26]  // BUBBLE_COUNT, BUBBLE_SPEED
#define U_RAYS       fr.user[27]  // the sun on screen (fractions of the target), exposure, samples
#define U_RAYS_B     fr.user[28]  // GOD_RAY_DECAY, GOD_RAY_DENSITY
#define U_BLOOM      fr.user[29]  // BLOOM_THRESHOLD (display units), BLOOM_STRENGTH, radius in pixels

// ── Colour space (shade::gamma) ────────────────────────────────────────────────

float srgbToLinear(float s) {
    return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4);
}

vec3 toLinear(vec3 c) {
    return vec3(srgbToLinear(c.r), srgbToLinear(c.g), srgbToLinear(c.b));
}

float linearToSrgb(float x) {
    if (x <= 0.0) {
        return 0.0;
    }
    if (x >= 1.0) {
        return 1.0;
    }
    return x <= 0.0031308 ? x * 12.92 : 1.055 * pow(x, 1.0 / 2.4) - 0.055;
}

// The highlight shoulder: the identity up to the knee, then a roll-off toward 1.
float toneMap(float x) {
    float knee = U_SHEEN.w;
    if (x <= knee) {
        return x;
    }
    float head = 1.0 - knee;
    float over = x - knee;
    return knee + head * over / (over + head);
}

// Linear light to a display value, through the tone curve — what the CPU's encode
// table holds, clamped at its ends the same way.
vec3 encode(vec3 lin) {
    vec3 x = clamp(lin, 0.0, U_WATER.w);
    return vec3(linearToSrgb(toneMap(x.r)), linearToSrgb(toneMap(x.g)), linearToSrgb(toneMap(x.b)));
}

// ── The sky's colour along a direction (sky::atmosphere) ───────────────────────

// In display units (0 .. 255, and past it near the sun), before the shoulder.
vec3 skyColour(vec3 dir) {
    float t = clamp(dir.y, 0.0, 1.0);
    float ts = sqrt(t);
    vec3 c = U_HORIZON.rgb + (U_ZENITH.rgb - U_HORIZON.rgb) * ts;
    float sd = dot(dir, U_SUN.xyz);
    float fade = U_ZENITH.w;
    if (sd > 0.0 && fade > 0.0) {
        float s2 = sd * sd;
        float halo = s2 * s2 * s2 * U_HALO.w * fade;
        if (sd > U_CORE.x) {
            float cc = (sd - U_CORE.x) / (1.0 - U_CORE.x);
            halo += cc * cc * fade * U_CORE.y;
        }
        c += U_HALO.rgb * halo;
    }
    return c;
}

// The highlight shoulder in display units: the sky as it is painted, and as the fog
// dissolves into it.
float shoulder(float x) {
    float knee = U_CORE.z;
    if (x <= knee) {
        return x;
    }
    float head = 255.0 - knee;
    float over = x - knee;
    return knee + head * over / (over + head);
}

vec3 shoulderRgb(vec3 c) {
    return vec3(shoulder(c.r), shoulder(c.g), shoulder(c.b));
}

// ── The cloud deck as it is read (sky::clouddome) ──────────────────────────────
//
// The deck's three tables live in a two-layer texture of 16-bit values split across
// bytes: layer 0 holds coverage (r high, g low) and the lit share (b high, a low),
// layer 1 the ambient share (r high, g low). `CLOUD_N` cells across.

#define CLOUD_N 448

vec3 cloudCell(sampler2DArray deck, int u, int v) {
    ivec2 p = ivec2(clamp(u, 0, CLOUD_N - 1), clamp(v, 0, CLOUD_N - 1));
    vec4 a = texelFetch(deck, ivec3(p, 0), 0);
    vec4 b = texelFetch(deck, ivec3(p, 1), 0);
    float cov = (floor(a.r * 255.0 + 0.5) * 256.0 + floor(a.g * 255.0 + 0.5)) / 65535.0;
    float lit = (floor(a.b * 255.0 + 0.5) * 256.0 + floor(a.a * 255.0 + 0.5)) / 65535.0;
    float amb = (floor(b.r * 255.0 + 0.5) * 256.0 + floor(b.g * 255.0 + 0.5)) / 65535.0;
    return vec3(cov, lit, amb);
}

vec4 cubicWeights(float t) {
    float t2 = t * t;
    float t3 = t2 * t;
    return vec4(
        -0.5 * t + t2 - 0.5 * t3,
        1.0 - 2.5 * t2 + 1.5 * t3,
        0.5 * t + 2.0 * t2 - 1.5 * t3,
        -0.5 * t2 + 0.5 * t3
    );
}

float phaseHG(float mu, float g) {
    float k = max(1.0 + g * g - 2.0 * g * mu, 0.0001);
    return (1.0 - g * g) / (k * sqrt(k));
}

// What the cloud contributes along a unit direction: its colour (display units,
// premultiplied by coverage) and its coverage.
vec4 cloudSample(sampler2DArray deck, vec3 dir) {
    if (U_CORE.w < 0.5 || dir.y <= 0.0) {
        return vec4(0.0);
    }
    float sc = 1.0 / sqrt(1.0 + dir.y);
    float edge = float(CLOUD_N - 1) * 0.5;
    float fu = (dir.x * sc + 1.0) * edge;
    float fv = (dir.z * sc + 1.0) * edge;
    int iu = int(floor(fu));
    int iv = int(floor(fv));
    if (cloudCell(deck, iu, iv).x <= 0.0 && cloudCell(deck, iu + 1, iv).x <= 0.0
        && cloudCell(deck, iu, iv + 1).x <= 0.0 && cloudCell(deck, iu + 1, iv + 1).x <= 0.0) {
        return vec4(0.0);
    }
    vec4 wu = cubicWeights(fu - float(iu));
    vec4 wv = cubicWeights(fv - float(iv));
    vec3 acc = vec3(0.0);
    for (int j = 0; j < 4; ++j) {
        vec3 row = cloudCell(deck, iu - 1, iv - 1 + j) * wu.x
                 + cloudCell(deck, iu, iv - 1 + j) * wu.y
                 + cloudCell(deck, iu + 1, iv - 1 + j) * wu.z
                 + cloudCell(deck, iu + 2, iv - 1 + j) * wu.w;
        acc += row * wv[j];
    }
    float cov = clamp(acc.x, 0.0, 1.0);
    float lit = clamp(acc.y, 0.0, cov);
    float amb = clamp(acc.z, 0.0, cov);
    if (cov <= 0.0005) {
        return vec4(0.0);
    }
    float mu = dot(dir, U_DECK_DIR.xyz);
    float phase = min(
        U_PHASE.z * phaseHG(mu, U_PHASE.x) + (1.0 - U_PHASE.z) * phaseHG(mu, -U_PHASE.y),
        U_PHASE.w
    );
    float direct = lit * phase;
    float deep = cov - amb;
    vec3 c = (direct * U_DECK_BODY.rgb + amb * U_DECK_SKY.rgb + deep * U_DECK_GND.rgb) * 255.0;
    return vec4(c, cov);
}

// The sky behind a direction with the deck over it, in display units: what distant
// terrain dissolves into.
vec3 skyWithCloud(sampler2DArray deck, vec3 dir) {
    vec3 c = skyColour(dir);
    vec4 cl = cloudSample(deck, dir);
    if (cl.a > 0.002) {
        c = c * (1.0 - cl.a) + cl.rgb;
    }
    return c;
}

// ── A pixel back into the world ────────────────────────────────────────────────

// The world point (render-origin relative) a pixel of the target shows at a depth.
vec3 worldAt(vec2 uv, float depth) {
    vec4 clip = vec4(uv * 2.0 - 1.0, depth, 1.0);
    vec4 w = fr.invViewProj * clip;
    return w.xyz / w.w;
}

// The view direction through a pixel, as the CPU's view rays compute it.
vec3 viewRay(vec2 uv) {
    float ndcx = (uv.x * 2.0 - 1.0) * U_LENS.x;
    float ndcy = (1.0 - uv.y * 2.0) * U_LENS.y;
    float cosy = U_CAMERA.x;
    float siny = U_CAMERA.y;
    float cosp = U_CAMERA.z;
    float sinp = U_CAMERA.w;
    float rz0c = cosp - ndcy * sinp;
    float dyw = ndcy * cosp + sinp;
    vec3 d = vec3(ndcx * cosy - rz0c * siny, dyw, ndcx * siny + rz0c * cosy);
    return d / max(length(d), 0.0001);
}

// The CPU's integer hash (math::noise2 `hashI`), 0 .. 1; a 32-bit int wraps the same.
float hashI(int x, int y, int s) {
    int n = x * 374761393 + y * 668265263 + s * 1442695041;
    n = (n ^ (n >> 13)) * 1274126177;
    n = n ^ (n >> 16);
    return float(n & 0x7FFFFFFF) / 2147483647.0;
}

// A triangular dither of plus or minus one display unit, to break the sky's contours —
// the CPU's, pixel for pixel (`render/cpu/sky/viewrays`, `ditherAt`).
float dither(ivec2 p) {
    return hashI(p.x, p.y, 0) + hashI(p.x, p.y, 4177) - 1.0;
}

// A colour target's texel back in display units, rounded as the CPU's bytes are.
vec3 bytesAt(sampler2D target, vec2 uv) {
    return floor(texture(target, uv).rgb * 255.0 + 0.5);
}
