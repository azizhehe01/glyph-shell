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

vec3 rotate3D(vec3 p, float cosA, float sinA, float cosB, float sinB) {
    vec3 rx = vec3(p.x, p.y * cosA - p.z * sinA, p.y * sinA + p.z * cosA);
    return vec3(rx.x * cosB - rx.y * sinB, rx.x * sinB + rx.y * cosB, rx.z);
}

float sdTorus(vec3 p, vec2 t) {
    vec2 q = vec2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
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

    vec3 bgCol = vec3(0.027, 0.031, 0.039);
    vec3 dimCol = vec3(0.804, 0.839, 0.894);
    vec3 brightCol = vec3(1.0, 1.0, 1.0);
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
    } else {
        vec3 wpSample = texture(wallpaperTex, cellCenterUV).rgb;
        float rawLum = dot(wpSample, vec3(0.299, 0.587, 0.114));
        // Auto-contrast stretch so dark wallpapers still show rich * # % @ detail
        float baseLum = smoothstep(0.03, 0.68, rawLum);
        float iDist = length(cellCenterPx - cursorPx);
        float cWave = (iDist < 260.0)
            ? sin(iDist * 0.05 - t * 6.0) * (1.0 - iDist / 260.0) * 0.38
            : 0.0;
        float breath = sin(cellIdx.x * 0.18 + cellIdx.y * 0.14 + t * 1.8) * 0.09;
        float lum = clamp(baseLum + breath + cWave, 0.0, 0.999);
        int idx6 = int(floor(lum * 10.0));
        if (idx6 > 0) {
            glyphIdx = idx6;
            vec3 boostedWp = clamp(wpSample * 1.65 + 0.12, 0.0, 1.0);
            if (iDist < 180.0 && idx6 >= 6) {
                charColor = redCol;
                charAlpha = 0.96;
            } else if (idx6 >= 5 || iDist < 240.0) {
                charColor = mix(brightCol, boostedWp, 0.35);
                charAlpha = 0.92;
            } else {
                charColor = mix(dimCol, boostedWp, 0.45);
                charAlpha = 0.55;
            }
        }
    }

    float mask = sampleGlyph(glyphIdx, cellUV) * charAlpha;
    vec3 finalRgb = mix(bgCol, charColor, mask);
    fragColor = vec4(finalRgb, 1.0) * ubuf.qt_Opacity;
}
