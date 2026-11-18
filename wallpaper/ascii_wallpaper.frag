#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float timeSec;
    float widthPx;
    float heightPx;
    float cursorX;
    float cursorY;
    float cursorEnergy;
    int presetId;
    vec4 bgColor;
} ubuf;

layout(binding = 1) uniform sampler2D fontAtlas;
layout(binding = 2) uniform sampler2D wallpaperTex;

int mapVortexGlyph(int stepIdx) {
    if (stepIdx == 1) return 1;
    if (stepIdx == 2) return 2;
    if (stepIdx == 3) return 12;
    if (stepIdx == 4) return 13;
    if (stepIdx == 5) return 10;
    if (stepIdx == 6) return 6;
    if (stepIdx == 7) return 7;
    if (stepIdx >= 8) return 9;
    return 0;
}

int mapHalftoneGlyph(int stepIdx) {
    if (stepIdx == 1) return 1;
    if (stepIdx == 2) return 2;
    if (stepIdx == 3) return 12;
    if (stepIdx == 4) return 13;
    if (stepIdx == 5) return 10;
    if (stepIdx == 6) return 9;
    if (stepIdx >= 7) return 7;
    return 0;
}

float sampleGlyph(int idx, vec2 cellUV) {
    if (idx <= 0) return 0.0;
    int cIdx = clamp(idx, 0, 15);
    vec2 padded = (cellUV - 0.5) * 0.96 + 0.5;
    if (padded.x < 0.02 || padded.x > 0.98 || padded.y < 0.02 || padded.y > 0.98) {
        return 0.0;
    }
    float u = (float(cIdx) + padded.x) / 16.0;
    return texture(fontAtlas, vec2(u, padded.y)).r;
}

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbmFlame(vec2 p) {
    float v = 0.0;
    float a = 0.55;
    for (int i = 0; i < 3; i++) {
        v += a * vnoise(p);
        p = p * 2.08 + vec2(1.7, -3.1);
        a *= 0.5;
    }
    return v;
}

vec3 rotate3D(vec3 p, float cosA, float sinA, float cosB, float sinB) {
    vec3 rx = vec3(p.x, p.y * cosA - p.z * sinA, p.y * sinA + p.z * cosA);
    return vec3(rx.x * cosB - rx.y * sinB, rx.x * sinB + rx.y * cosB, rx.z);
}

float sdTorus(vec3 p, vec2 t) {
    vec2 q = vec2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

float sdBox(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float sdCapsule(vec3 p, vec3 a, vec3 b, float r) {
    vec3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// Returns vec2(distance, materialId: 1=blade, 2=guard/pommel, 3=red gem/core)
vec2 sdSword(vec3 p) {
    // 1. Heroic Tapered Diamond-Profile Blade (y from -0.34 to +1.28)
    float by = clamp((p.y + 0.34) / 1.62, 0.0, 1.0);
    float halfW = mix(0.22, 0.012, pow(by, 1.45));
    float halfT = mix(0.085, 0.010, by);
    float bladeDiamond = (abs(p.x) / halfW + abs(p.z) / halfT - 1.0) * min(halfW, halfT) * 0.72;
    float bladeCapY = max(p.y - 1.28, -0.34 - p.y);
    float dBlade = max(bladeDiamond, bladeCapY);

    // 2. Sculpted Crossguard (tapered & slightly swept)
    vec3 gp = p - vec3(0.0, -0.37, 0.0);
    float guardSweep = abs(gp.x) * 0.14;
    float dGuard = sdBox(vec3(gp.x, gp.y - guardSweep, gp.z), vec3(0.54, 0.058, 0.095)) - 0.015;

    // 3. Hilt / Grip
    float dGrip = sdCapsule(p, vec3(0.0, -0.40, 0.0), vec3(0.0, -0.94, 0.0), 0.068);

    // 4. Faceted Pommel
    float dPommel = length(p - vec3(0.0, -1.03, 0.0)) - 0.125;

    // 5. Nothing Red Core Gem at Crossguard Center
    float dGem = length((p - vec3(0.0, -0.37, 0.0)) * vec3(1.0, 1.0, 0.72)) - 0.095;

    vec2 res = vec2(dBlade, 1.0);
    float dMetal = min(dGuard, dPommel);
    if (dMetal < res.x) res = vec2(dMetal, 2.0);
    if (dGrip < res.x) res = vec2(dGrip, 2.0);
    if (dGem < res.x) res = vec2(dGem, 3.0);
    return res;
}

// Crisp Edge-to-Edge GPU Shade Block mask: 1='░', 2='▒', 3='▓', 4='█'
float sampleShadeBlock(int level, vec2 cellUV) {
    if (level <= 0) return 0.0;
    if (level >= 4) return 1.0; // █ Full Block
    vec2 sub = floor(cellUV * 2.0);
    float checker = mod(sub.x + sub.y, 2.0);
    if (level == 2) return (checker < 0.5) ? 1.0 : 0.0; // ▒ Medium Shade (50%)
    if (level == 1) return (sub.x < 0.5 && sub.y < 0.5) ? 1.0 : 0.0; // ░ Light Shade (25%)
    return (sub.x > 0.5 && sub.y > 0.5) ? 0.0 : 1.0; // ▓ Dark Shade (75%)
}

vec3 transformSword(vec3 p, float cosY, float sinY, float cosP, float sinP, float hoverY) {
    p.y -= hoverY;
    vec3 px = vec3(p.x, p.y * cosP - p.z * sinP, p.y * sinP + p.z * cosP);
    return vec3(px.x * cosY + px.z * sinY, px.y, -px.x * sinY + px.z * cosY);
}

vec3 calcSwordNormal(vec3 p) {
    const float e = 0.004;
    return normalize(vec3(
        sdSword(p + vec3(e, 0.0, 0.0)).x - sdSword(p - vec3(e, 0.0, 0.0)).x,
        sdSword(p + vec3(0.0, e, 0.0)).x - sdSword(p - vec3(0.0, e, 0.0)).x,
        sdSword(p + vec3(0.0, 0.0, e)).x - sdSword(p - vec3(0.0, 0.0, e)).x
    ));
}

// =========================================================================
// 3D SOLITAIRE PRISM DIAMOND RING SDF (matId: 1=metal band/prongs, 2=diamond)
// =========================================================================
vec2 sdDiamondRing(vec3 p) {
    // 1. Sleek Circular Metal Band (upright in XY plane, centered at y = -0.22)
    vec3 bp = p - vec3(0.0, -0.22, 0.0);
    float bandR = 0.62;
    float qx = length(bp.xy) - bandR;
    // Slightly thicker toward the top shoulders of the ring
    float topBoost = smoothstep(0.15, 0.62, bp.y) * 0.018;
    float bandTube = 0.068 + topBoost;
    float dBand = length(vec2(qx, bp.z * 0.78)) - bandTube;

    // 2. Crown Setting Base Collar & 4 Sleek Prongs gripping the diamond
    float dCollar = length(vec2(length(p.xz) - 0.14, p.y - 0.43)) - 0.036;
    vec3 pp = vec3(abs(p.x), p.y, abs(p.z));
    float dProng = sdCapsule(pp, vec3(0.10, 0.42, 0.10), vec3(0.21, 0.68, 0.21), 0.024);
    float dMetal = min(dBand, min(dCollar, dProng));

    // 3. 8-Fold Brilliant-Cut Faceted Diamond (centered at y = 0.66)
    vec3 dp = p - vec3(0.0, 0.66, 0.0);
    vec2 xz = abs(dp.xz);
    if (xz.y > xz.x) xz = xz.yx;
    // Regular octagon distance (8 crisp flat sides)
    float r8 = max(xz.x, dot(xz, vec2(0.70710678, 0.70710678)));
    // Secondary star facets at 22.5 deg for richer brilliant-cut sparkle
    float r16 = dot(xz, vec2(0.92387953, 0.38268343));
    float rFacet = max(r8, r16 * 0.96);

    float dPavilion = (rFacet * 0.74 - dp.y * 0.67) - 0.245;
    float dCrown    = (rFacet * 0.64 + dp.y * 0.77) - 0.248;
    float dTable    = dp.y - 0.155;
    float dDiamond  = max(max(dPavilion, dCrown), dTable);

    if (dDiamond < dMetal) {
        return vec2(dDiamond, 2.0);
    }
    return vec2(dMetal, 1.0);
}

vec3 transformRing(vec3 p, float cosY, float sinY, float cosP, float sinP, float hoverY) {
    p.y -= hoverY;
    vec3 px = vec3(p.x, p.y * cosP - p.z * sinP, p.y * sinP + p.z * cosP);
    return vec3(px.x * cosY + px.z * sinY, px.y, -px.x * sinY + px.z * cosY);
}

vec3 calcRingNormal(vec3 p) {
    const float e = 0.003;
    return normalize(vec3(
        sdDiamondRing(p + vec3(e, 0.0, 0.0)).x - sdDiamondRing(p - vec3(e, 0.0, 0.0)).x,
        sdDiamondRing(p + vec3(0.0, e, 0.0)).x - sdDiamondRing(p - vec3(0.0, e, 0.0)).x,
        sdDiamondRing(p + vec3(0.0, 0.0, e)).x - sdDiamondRing(p - vec3(0.0, 0.0, e)).x
    ));
}

void main() {
    vec2 res = vec2(max(1.0, ubuf.widthPx), max(1.0, ubuf.heightPx));
    float aspect = res.x / res.y;

    vec2 gridDims = vec2(64.0, 36.0);
    vec2 gridPos = qt_TexCoord0 * gridDims;
    vec2 cellIdx = floor(gridPos);
    vec2 cellUV = fract(gridPos);
    vec2 cellCenterUV = (cellIdx + 0.5) / gridDims;
    vec2 cellCenterPx = cellCenterUV * res;

    float t = ubuf.timeSec;
    vec2 cursorPx = vec2(ubuf.cursorX, ubuf.cursorY);
    float energy = ubuf.cursorEnergy;

    vec3 bgCol = ubuf.bgColor.rgb;
    float bgLum = dot(bgCol, vec3(0.299, 0.587, 0.114));
    bool isLightBg = bgLum > 0.55;
    vec3 dimCol = isLightBg ? vec3(0.22, 0.25, 0.30) : vec3(0.804, 0.839, 0.894);
    vec3 brightCol = isLightBg ? vec3(0.05, 0.06, 0.08) : vec3(1.0, 1.0, 1.0);
    vec3 redCol = vec3(0.843, 0.098, 0.129);

    int glyphIdx = 0;
    vec3 charColor = dimCol;
    float charAlpha = 0.0;

    if (ubuf.presetId == 0) {
        float nx = cellCenterUV.x;
        float ny = cellCenterUV.y;
        float v1 = sin(nx * 6.2 + t * 1.1 + cos(ny * 4.0 - t * 0.7));
        float v2 = cos(ny * 5.5 - t * 0.8 + sin(nx * 4.8 + t * 0.6));
        float val = (v1 + v2) * 0.5;
        float dist = length(cellCenterPx - cursorPx);
        float cursorInf = max(0.0, 1.0 - dist / 320.0);
        float rippleWave = sin(dist * 0.045 - t * 6.5);
        float ripple = rippleWave * cursorInf * (0.50 + energy * 0.50);
        float combined = clamp((val + ripple + 1.0) * 0.5, 0.0, 0.999);
        int idx = int(floor(combined * 10.0));
        if (idx > 0) {
            glyphIdx = idx;
            if (cursorInf > 0.32 && abs(rippleWave) > 0.68) {
                charColor = redCol;
                charAlpha = 0.96;
            } else if (cursorInf > 0.15 || idx >= 8) {
                charColor = brightCol;
                charAlpha = 0.90;
            } else {
                charColor = dimCol;
                charAlpha = 0.42;
            }
        }
    } else if (ubuf.presetId == 1) {
        vec2 vortexCenter = vec2(res.x * 0.56, res.y * 0.50);
        vortexCenter += (cursorPx - vortexCenter) * 0.28;
        vec2 dVec = cellCenterPx - vortexCenter;
        float radius = length(dVec);
        float angle = atan(dVec.y, dVec.x);
        float spiral = sin(angle * 4.0 - radius * 0.018 + t * 2.0);
        float rings = cos(radius * 0.032 - t * 2.6);
        float field = (spiral * 0.55 + rings * 0.45 + 1.0) * 0.5;
        float cDist = length(cellCenterPx - cursorPx);
        float cGlow = max(0.0, 1.0 - cDist / 250.0);
        float norm = clamp(field * 0.85 + cGlow * 0.35, 0.0, 0.999);
        int gStep = int(floor(norm * 9.0));
        if (gStep > 0) {
            glyphIdx = mapVortexGlyph(gStep);
            if (abs(radius - 210.0 - sin(t * 1.6) * 28.0) < 20.0 || (cGlow > 0.48 && gStep >= 5)) {
                charColor = redCol;
                charAlpha = 0.96;
            } else if (cGlow > 0.18 || gStep >= 7) {
                charColor = brightCol;
                charAlpha = 0.90;
            } else {
                charColor = dimCol;
                charAlpha = 0.42;
            }
        }
    } else if (ubuf.presetId == 2) {
        float col = cellIdx.x;
        float row = cellIdx.y;
        float h1 = hash21(vec2(col, 13.7));
        float speed = 5.5 + h1 * 8.5;
        float trailLen = 7.0 + fract(h1 * 19.3) * 11.0;
        float totalSpan = gridDims.y + trailLen + 4.0;
        float headY = mod(t * speed + h1 * 50.0, totalSpan) - 2.0;
        float k = headY - row;
        if (k >= 0.0 && k < trailLen) {
            float charHash = hash21(vec2(col * 3.1 + row * 1.7, floor(t * 6.5 + h1 * 10.0)));
            glyphIdx = 1 + int(floor(charHash * 14.99));
            float cDist = length(cellCenterPx - cursorPx);
            bool nearCursor = cDist < 190.0;
            bool isRedCol = mod(col, 7.0) < 0.5;
            if (nearCursor || (k < 1.2 && isRedCol)) {
                charColor = redCol;
                charAlpha = 0.96;
            } else if (k < 2.0) {
                charColor = brightCol;
                charAlpha = 0.92;
            } else {
                charColor = dimCol;
                charAlpha = clamp((1.0 - k / trailLen) * 0.62, 0.16, 0.58);
            }
        }
    } else if (ubuf.presetId == 3) {
        vec2 p2d = vec2((cellCenterUV.x - 0.56) * aspect, cellCenterUV.y - 0.50) * 2.15;
        vec3 ro = vec3(0.0, 0.0, -3.7);
        vec3 rd = normalize(vec3(p2d, 1.35));
        float A = t * 1.25 + ((cursorPx.y / res.y) - 0.5) * 2.3;
        float B = t * 0.80 + ((cursorPx.x / res.x) - 0.5) * 2.3;
        float cosA = cos(A), sinA = sin(A);
        float cosB = cos(B), sinB = sin(B);
        float distT = 0.0;
        bool hit = false;
        vec3 pos = vec3(0.0);
        for (int i = 0; i < 24; i++) {
            pos = rotate3D(ro + rd * distT, cosA, sinA, cosB, sinB);
            float d = sdTorus(pos, vec2(1.05, 0.45));
            if (d < 0.012) {
                hit = true;
                break;
            }
            distT += d;
            if (distT > 6.5) break;
        }
        if (hit) {
            vec2 ringDir = normalize(pos.xz);
            vec3 ringCenter = vec3(ringDir.x * 1.05, 0.0, ringDir.y * 1.05);
            vec3 localNorm = normalize(pos - ringCenter);
            vec3 lightWorld = normalize(vec3(0.55, -0.70, -0.85));
            vec3 lightLocal = rotate3D(lightWorld, cosA, sinA, cosB, sinB);
            float diff = dot(localNorm, lightLocal);
            float lum = clamp((diff + 0.72) / 1.72, 0.08, 0.999);
            glyphIdx = 1 + int(floor(lum * 8.99));
            if (lum > 0.83) {
                charColor = redCol;
                charAlpha = 0.96;
            } else if (lum > 0.44) {
                charColor = brightCol;
                charAlpha = 0.92;
            } else {
                charColor = dimCol;
                charAlpha = 0.48;
            }
        } else {
            if (mod(cellIdx.x, 2.0) < 0.5 && mod(cellIdx.y, 2.0) < 0.5) {
                float bgWave = sin(cellIdx.x * 0.24 + cellIdx.y * 0.20 - t * 1.8);
                if (bgWave > 0.10) {
                    glyphIdx = (bgWave > 0.75) ? 5 : 1;
                    charColor = dimCol;
                    charAlpha = 0.32;
                }
            }
        }
    } else if (ubuf.presetId == 4) {
        vec2 s1 = vec2(res.x * 0.5 + cos(t * 0.9) * (res.x * 0.22),
                       res.y * 0.5 + sin(t * 0.7) * (res.y * 0.20));
        float d1 = length(cellCenterPx - s1);
        float d2 = length(cellCenterPx - cursorPx);
        float w1 = sin(d1 * 0.035 - t * 2.6);
        float w2 = sin(d2 * 0.042 - t * 3.2);
        float moire = clamp((w1 + w2 + 2.0) * 0.25, 0.0, 0.999);
        int hStep = int(floor(moire * 8.0));
        if (hStep > 0) {
            glyphIdx = mapHalftoneGlyph(hStep);
            if (d2 < 220.0 && hStep >= 6) {
                charColor = redCol;
                charAlpha = 0.96;
            } else if (hStep >= 5) {
                charColor = brightCol;
                charAlpha = 0.90;
            } else {
                charColor = dimCol;
                charAlpha = 0.42;
            }
        }
    } else if (ubuf.presetId == 6) {
        // PRESET 6: SILENT BLADE (Ultra-Dense 480x270 Edge-to-Edge Shade-Block 3D Sword)
        vec2 swordGrid = vec2(480.0, 270.0);
        vec2 sGridPos = qt_TexCoord0 * swordGrid;
        vec2 sCellIdx = floor(sGridPos);
        vec2 sCellUV = fract(sGridPos);
        vec2 sCenterUV = (sCellIdx + 0.5) / swordGrid;

        vec2 p2d = vec2((sCenterUV.x - 0.56) * aspect, -(sCenterUV.y - 0.50)) * 2.05;
        vec3 ro = vec3(0.0, 0.08, -3.30);
        vec3 rd = normalize(vec3(p2d, 1.55));

        float hoverY = sin(t * 1.15) * 0.050;
        float yaw = t * 0.65 + ((cursorPx.x / res.x) - 0.5) * 1.8;
        float pitch = -0.16 + ((cursorPx.y / res.y) - 0.5) * 0.65;
        float cosY = cos(yaw), sinY = sin(yaw);
        float cosP = cos(pitch), sinP = sin(pitch);

        float distS = 0.0;
        bool hitS = false;
        vec3 hitPos = vec3(0.0);
        float hitMat = 1.0;

        for (int i = 0; i < 40; i++) {
            vec3 sp = transformSword(ro + rd * distS, cosY, sinY, cosP, sinP, hoverY);
            vec2 resS = sdSword(sp);
            if (resS.x < 0.004) {
                hitS = true;
                hitPos = sp;
                hitMat = resS.y;
                break;
            }
            distS += resS.x * 0.75;
            if (distS > 6.5) break;
        }

        if (hitS) {
            vec3 nrm = calcSwordNormal(hitPos);
            vec3 lightWorld = normalize(vec3(0.70, 0.55, -0.75));
            vec3 lightLocal = transformSword(lightWorld, cosY, sinY, cosP, sinP, 0.0);
            vec3 viewLocal = transformSword(normalize(vec3(0.0, 0.0, -1.0)), cosY, sinY, cosP, sinP, 0.0);
            vec3 halfVec = normalize(lightLocal + viewLocal);

            float diff = max(0.0, dot(nrm, lightLocal));
            float spec = pow(max(0.0, dot(nrm, halfVec)), 12.0);
            float rim = pow(1.0 - max(0.0, dot(nrm, viewLocal)), 2.2) * 0.35;
            // High-contrast 3D metallic curve: lit bevel hits solid █ while shaded bevel grades ▓ -> ▒ -> ░
            float lum = clamp(0.12 + pow(diff, 0.85) * 0.78 + spec * 0.85 + rim * 0.28, 0.08, 0.999);

            int shadeLvl = 1 + int(floor(lum * 3.99));
            if (hitMat > 2.5 || (hitMat < 1.5 && rim > 0.24 && spec > 0.14)) {
                charColor = redCol;
                charAlpha = 0.96;
            } else if (hitMat < 1.5 && (lum > 0.72 || spec > 0.25)) {
                charColor = brightCol;
                charAlpha = 0.98;
            } else if (hitMat < 1.5) {
                charColor = mix(dimCol, brightCol, lum * 0.72);
                charAlpha = 0.88;
            } else {
                charColor = dimCol;
                charAlpha = 0.72;
            }

            float blockMask = sampleShadeBlock(shadeLvl, sCellUV) * charAlpha;
            vec3 swordRgb = mix(bgCol, charColor, blockMask);
            fragColor = vec4(swordRgb, 1.0) * ubuf.qt_Opacity;
            return;
        }
        fragColor = vec4(bgCol, 1.0) * ubuf.qt_Opacity;
        return;
    } else if (ubuf.presetId == 7) {
        // PRESET 7: INFERNO PRISM (White Crystal 3D Diamond Engulfed in Organic Blue Fire)
        vec2 ringGrid = vec2(480.0, 270.0);
        vec2 rGridPos = qt_TexCoord0 * ringGrid;
        vec2 rCellIdx = floor(rGridPos);
        vec2 rCellUV = fract(rGridPos);
        vec2 rCenterUV = (rCellIdx + 0.5) / ringGrid;

        vec2 p2d = vec2((rCenterUV.x - 0.56) * aspect, -(rCenterUV.y - 0.50)) * 2.15;
        vec3 ro = vec3(0.0, 0.14, -3.28);
        vec3 rd = normalize(vec3(p2d, 1.58));

        float hoverY = sin(t * 1.10) * 0.045;
        float yaw = t * 0.62 + ((cursorPx.x / res.x) - 0.5) * 1.9;
        float pitch = 0.22 + ((cursorPx.y / res.y) - 0.5) * 0.60;
        float cosY = cos(yaw), sinY = sin(yaw);
        float cosP = cos(pitch), sinP = sin(pitch);

        // Projected screen position of the diamond center
        float crownY3 = 0.66 * cosP;
        float crownZ3 = 0.66 * sinP;
        float diamondScreenY = (crownY3 + hoverY - ro.y) * 1.58 / (3.28 + crownZ3);

        // Cursor Wind Draft (sways the blue flame tongues smoothly)
        vec2 cursorP2d = vec2(((cursorPx.x / res.x) - 0.56) * aspect, -((cursorPx.y / res.y) - 0.50)) * 2.15;
        float cursorDist = length(cursorP2d - vec2(0.0, diamondScreenY + 0.12));
        float windStrength = smoothstep(1.30, 0.05, cursorDist);
        float windDir = clamp((0.0 - cursorP2d.x) * 0.55, -0.38, 0.38) * windStrength;

        // Multi-tongue Organic Blue Fire wrapping cleanly around the diamond (zero stray noise!)
        float flameBaseY = diamondScreenY - 0.14;
        // Curve the flame base slightly upward along the sides so it hugs the diamond's V-shape
        float fy = p2d.y - (flameBaseY + abs(p2d.x) * 0.42);
        float flameIntensity = 0.0;
        float frontFlameMask = 0.0;

        if (fy > -0.02 && fy < 0.88 && abs(p2d.x) < 0.52) {
            float normY = clamp(fy / 0.84, 0.0, 1.0);
            float windBend = windDir * normY * normY * 0.72;

            // Domain-warped turbulence for organic flickering flame tongues
            float warpA = (fbmFlame(vec2(p2d.x * 4.5, fy * 3.8 - t * 3.4)) - 0.5) * 0.22 * (0.35 + normY);
            float fx = p2d.x - windBend + warpA;

            // 3 distinct organic flame tongues: Left side wrap + Main center + Right side wrap
            float lSway = sin(fy * 7.2 - t * 5.2 + 1.1) * 0.032 * normY;
            float cSway = sin(fy * 5.8 - t * 4.5) * 0.028 * normY;
            float rSway = sin(fy * 6.8 - t * 4.9 + 3.4) * 0.032 * normY;

            // Left tongue hugging left girdle & rising independently
            float lNormY = clamp(fy / 0.62, 0.0, 1.0);
            float lX = (fx + 0.145 * (1.0 - lNormY * 0.45) - lSway) / mix(0.135, 0.024, pow(lNormY, 0.9));
            float lLobe = max(0.0, 1.0 - lX * lX) * (1.0 - pow(lNormY, 1.25));

            // Right tongue hugging right girdle & rising independently
            float rNormY = clamp(fy / 0.66, 0.0, 1.0);
            float rX = (fx - 0.145 * (1.0 - rNormY * 0.45) - rSway) / mix(0.135, 0.024, pow(rNormY, 0.9));
            float rLobe = max(0.0, 1.0 - rX * rX) * (1.0 - pow(rNormY, 1.25));

            // Main central fire core hugging the whole diamond body
            float cX = (fx - cSway) / mix(0.235, 0.034, pow(normY, 1.05));
            float cLobe = max(0.0, 1.0 - cX * cX) * (1.0 - pow(normY, 1.30));

            float combinedShape = max(cLobe, max(lLobe * 0.92, rLobe * 0.92));

            // Fine upward-licking plasma wisps — strictly bounded by combinedShape so ZERO stray spots appear!
            float turb = fbmFlame(vec2(fx * 6.8, fy * 5.2 - t * 4.4));
            float fineWisp = fbmFlame(vec2(fx * 12.5 - t * 0.8, fy * 9.0 - t * 6.2));

            float rawFlame = combinedShape * (0.65 + turb * 1.15 + fineWisp * 0.42) - normY * 0.14;
            flameIntensity = clamp(rawFlame, 0.0, 1.0) * smoothstep(-0.02, 0.11, fy) * smoothstep(0.0, 0.10, combinedShape);

            // Foreground fire tongues that visibly lick across the FRONT & rim of the white diamond
            float frontNoise = fbmFlame(vec2(fx * 8.5 + 2.3, fy * 6.8 - t * 5.2));
            float edgeFocus = smoothstep(0.03, 0.17, abs(p2d.x)) + smoothstep(0.26, 0.02, fy) * 0.65;
            frontFlameMask = clamp((frontNoise - 0.36) * 2.4 * edgeFocus * smoothstep(0.42, 0.02, fy), 0.0, 1.0);
        }

        // Raymarch 3D Solitaire Ring + Diamond
        float distR = 0.0;
        bool hitR = false;
        vec3 hitPos = vec3(0.0);
        float hitMat = 1.0;

        for (int i = 0; i < 44; i++) {
            vec3 rp = transformRing(ro + rd * distR, cosY, sinY, cosP, sinP, hoverY);
            vec2 resR = sdDiamondRing(rp);
            if (resR.x < 0.0035) {
                hitR = true;
                hitPos = rp;
                hitMat = resR.y;
                break;
            }
            distR += resR.x * 0.78;
            if (distR > 6.5) break;
        }

        // Blue Fire Palette
        vec3 iceWhite  = vec3(0.92, 0.99, 1.00); // #EBFCFF (Hottest flame core)
        vec3 elecCyan  = vec3(0.14, 0.84, 1.00); // #24D6FF (Bright electric blue flame)
        vec3 cobaltBlu = vec3(0.06, 0.42, 1.00); // #0F6BFF (Mid cobalt flame)
        vec3 deepIndig = vec3(0.05, 0.16, 0.74); // #0D29BD (Outer wispy blue flame)

        if (hitR) {
            vec3 nrm = calcRingNormal(hitPos);
            vec3 light1 = transformRing(normalize(vec3(0.68, 0.78, -0.70)), cosY, sinY, cosP, sinP, 0.0);
            vec3 light2 = transformRing(normalize(vec3(-0.72, 0.40, -0.55)), cosY, sinY, cosP, sinP, 0.0);
            vec3 viewLocal = transformRing(normalize(vec3(0.0, 0.0, -1.0)), cosY, sinY, cosP, sinP, 0.0);
            vec3 half1 = normalize(light1 + viewLocal);
            vec3 half2 = normalize(light2 + viewLocal);

            float diff1 = max(0.0, dot(nrm, light1));
            float diff2 = max(0.0, dot(nrm, light2));
            float spec1 = pow(max(0.0, dot(nrm, half1)), hitMat > 1.5 ? 24.0 : 14.0);
            float spec2 = pow(max(0.0, dot(nrm, half2)), 18.0);
            float fresnel = pow(1.0 - max(0.0, dot(nrm, viewLocal)), 2.0);

            float lum;
            if (hitMat > 1.5) {
                // PURE WHITE CRYSTAL DIAMOND (#FFFFFF) with sharp facets + foreground blue flame licks!
                lum = clamp(0.24 + diff1 * 0.56 + diff2 * 0.24 + spec1 * 1.15 + spec2 * 0.70 + fresnel * 0.22, 0.16, 0.999);
                vec3 crystalCol = (lum > 0.66 || spec1 > 0.26)
                    ? vec3(1.0, 1.0, 1.0)
                    : mix(vec3(0.70, 0.75, 0.82), vec3(1.0, 1.0, 1.0), lum * 0.85);

                // Foreground blue flame licking across the front & rim of the white diamond
                float rimBurn = clamp(fresnel * 0.72 * flameIntensity + frontFlameMask * 1.15, 0.0, 1.0);
                if (rimBurn > 0.34) {
                    vec3 lickCol = mix(cobaltBlu, elecCyan, clamp((rimBurn - 0.34) * 1.8, 0.0, 1.0));
                    charColor = mix(crystalCol, lickCol, clamp((rimBurn - 0.28) * 1.6, 0.0, 0.94));
                    lum = max(lum, 0.55 + rimBurn * 0.40);
                    charAlpha = 0.98;
                } else {
                    // Subtle cool cyan edge reflection on white facets
                    charColor = mix(crystalCol, elecCyan, fresnel * 0.18);
                    charAlpha = 0.98;
                }
            } else {
                // Cool metallic silver/slate ring band + blue fire licking around upper prongs
                float prongGlow = smoothstep(0.18, 0.62, hitPos.y);
                lum = clamp(0.12 + diff1 * 0.62 + diff2 * 0.20 + spec1 * 0.68 + fresnel * 0.24, 0.08, 0.999);
                vec3 metalCol = (lum > 0.74 || spec1 > 0.34)
                    ? brightCol
                    : mix(dimCol, brightCol, lum * 0.55);
                float prongLick = clamp(prongGlow * (0.35 + frontFlameMask * 0.85), 0.0, 0.85);
                charColor = mix(metalCol, elecCyan, prongLick);
                charAlpha = 0.88;
            }

            int shadeLvl = 1 + int(floor(lum * 3.99));
            float blockMask = sampleShadeBlock(shadeLvl, rCellUV) * charAlpha;
            vec3 ringRgb = mix(bgCol, charColor, blockMask);
            fragColor = vec4(ringRgb, 1.0) * ubuf.qt_Opacity;
            return;
        }

        // Render Blue Flame engulfing the sides & rising above the diamond (480x270 Shade Blocks)
        if (flameIntensity > 0.11) {
            int fLvl;
            vec3 fCol;
            float fAlpha;
            if (flameIntensity > 0.72) {
                fLvl = 4; // █ Hottest cyan-white base
                fCol = mix(elecCyan, iceWhite, (flameIntensity - 0.72) * 3.2);
                fAlpha = 0.98;
            } else if (flameIntensity > 0.45) {
                fLvl = 3; // ▓ Bright electric blue
                fCol = mix(cobaltBlu, elecCyan, (flameIntensity - 0.45) / 0.27);
                fAlpha = 0.94;
            } else if (flameIntensity > 0.25) {
                fLvl = 2; // ▒ Cobalt mid-flame
                fCol = mix(deepIndig, cobaltBlu, (flameIntensity - 0.25) / 0.20);
                fAlpha = 0.86;
            } else {
                fLvl = 1; // ░ Wispy indigo tips
                fCol = deepIndig;
                fAlpha = 0.76;
            }
            float fMask = sampleShadeBlock(fLvl, rCellUV) * fAlpha;
            vec3 flameRgb = mix(bgCol, fCol, fMask);
            fragColor = vec4(flameRgb, 1.0) * ubuf.qt_Opacity;
            return;
        }

        fragColor = vec4(bgCol, 1.0) * ubuf.qt_Opacity;
        return;
    } else {
        vec3 wpSample = texture(wallpaperTex, cellCenterUV).rgb;
        float rawLum = dot(wpSample, vec3(0.299, 0.587, 0.114));
        float baseLum = smoothstep(0.02, 0.65, rawLum);
        vec3 satWp = mix(vec3(rawLum), wpSample, 1.65);
        vec3 vividWp = clamp(satWp * (1.35 + baseLum * 0.65), 0.0, 1.0);

        float iDist = length(cellCenterPx - cursorPx);
        float cWave = (iDist < 260.0)
            ? sin(iDist * 0.05 - t * 6.0) * (1.0 - iDist / 260.0) * 0.38
            : 0.0;
        float breath = sin(cellIdx.x * 0.18 + cellIdx.y * 0.14 + t * 1.8) * 0.09;
        float lum = clamp(baseLum + breath + cWave, 0.0, 0.999);
        int idx6 = int(floor(lum * 10.0));
        if (idx6 > 0) {
            glyphIdx = idx6;
            if (iDist < 170.0 && idx6 >= 6) {
                charColor = redCol;
                charAlpha = 0.96;
            } else if (idx6 >= 5 || iDist < 220.0) {
                charColor = mix(brightCol, vividWp, 0.85);
                charAlpha = 0.95;
            } else {
                charColor = mix(dimCol, vividWp, 0.88);
                charAlpha = 0.72;
            }
        }
    }

    float mask = sampleGlyph(glyphIdx, cellUV) * charAlpha;
    vec3 finalRgb = mix(bgCol, charColor, mask);
    fragColor = vec4(finalRgb, 1.0) * ubuf.qt_Opacity;
}
