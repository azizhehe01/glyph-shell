import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// =============================================================================
// Nothing OS 3.0 / glyph-shell Interactive Live ASCII Wallpaper Engine
// GPU FBO Canvas + 3-Pass Color Batching (only 3 fillStyle changes/frame)
// + Smart Window Auto-Pause (0% CPU/GPU when any window is open on workspace).
// =============================================================================
PanelWindow {
    id: root

    WlrLayershell.namespace: "quickshell:ascii-wallpaper"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: WlrLayershell.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // State controlled by WallpaperWindow or persisted config
    property bool asciiEnabled: false
    property bool previewActive: false
    property bool hasOpenWindow: false
    property string activePreset: "topo-wave"
    property string previewPreset: ""

    readonly property bool isShowing: root.asciiEnabled || root.previewActive
    readonly property string currentPreset: (root.previewActive && root.previewPreset !== "")
        ? root.previewPreset
        : root.activePreset

    // Auto-Pause when any window is open on the current workspace (unless previewing in Ctrl+Super+W)
    readonly property bool shouldAnimate: root.isShowing && (root.previewActive || !root.hasOpenWindow)

    onShouldAnimateChanged: {
        if (root.shouldAnimate) {
            asciiCanvas.requestPaint();
        }
    }

    visible: root.isShowing
    color: "#07080A"

    // Live cursor coordinates injected from NotchWindow (zero extra daemon overhead)
    property real rawCursorX: 960
    property real rawCursorY: 540
    property real smoothCursorX: 960
    property real smoothCursorY: 540
    property real cursorEnergy: 0.0

    // Time accumulator for procedural animations
    property real timeSec: 0.0

    // Sampled image cells for "wallpaper-ascii" preset
    property int sampleCols: 76
    property int sampleRows: 42
    property var sampleCells: []

    FontLoader {
        id: fontNMono
        source: Qt.resolvedUrl("../assets/fonts/LetteraMonoLL-Regular.otf")
    }

    // Load persisted ASCII state on startup
    Process {
        id: initAsciiStateProc
        command: ["python3", Quickshell.shellDir + "/wallpaper/wallpaper.py", "ascii-state"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text.trim());
                    root.asciiEnabled = !!d.enabled;
                    if (d.preset) root.activePreset = d.preset;
                    if (root.isShowing) {
                        if (root.currentPreset === "wallpaper-ascii") {
                            root.reloadWallpaperSample();
                        }
                        asciiCanvas.requestPaint();
                    }
                } catch (e) {}
            }
        }
    }

    // Load sampled image grid for "wallpaper-ascii" preset
    Process {
        id: sampleAsciiProc
        command: ["python3", Quickshell.shellDir + "/wallpaper/wallpaper.py", "sample-ascii"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text.trim());
                    if (d.cells && d.cells.length > 0) {
                        root.sampleCols = d.cols || 76;
                        root.sampleRows = d.rows || 42;
                        root.sampleCells = d.cells;
                        asciiCanvas.requestPaint();
                    }
                } catch (e) {}
            }
        }
    }

    function reloadWallpaperSample(): void {
        if (!sampleAsciiProc.running) {
            sampleAsciiProc.running = true;
        }
    }

    onCurrentPresetChanged: {
        if (root.currentPreset === "wallpaper-ascii" && root.sampleCells.length === 0) {
            root.reloadWallpaperSample();
        }
        asciiCanvas.requestPaint();
    }

    onIsShowingChanged: {
        if (root.isShowing) {
            if (root.currentPreset === "wallpaper-ascii") {
                root.reloadWallpaperSample();
            }
            asciiCanvas.requestPaint();
        }
    }

    // Smooth 22 FPS loop — only runs when on empty desktop or previewing!
    Timer {
        id: frameTimer
        interval: 45
        running: root.shouldAnimate
        repeat: true
        onTriggered: {
            root.timeSec += 0.045;

            var dx = root.rawCursorX - root.smoothCursorX;
            var dy = root.rawCursorY - root.smoothCursorY;
            var dist = Math.sqrt(dx * dx + dy * dy);
            root.smoothCursorX += dx * 0.28;
            root.smoothCursorY += dy * 0.28;
            root.cursorEnergy = Math.min(1.0, root.cursorEnergy * 0.86 + (dist / 80.0) * 0.40);

            asciiCanvas.requestPaint();
        }
    }

    Canvas {
        id: asciiCanvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject
        renderStrategy: Canvas.Cooperative

        property var rainDrops: []

        function ensureRainDrops(cols, rows) {
            if (rainDrops.length === cols) return;
            var arr = [];
            for (var c = 0; c < cols; c++) {
                arr.push({
                    y: Math.random() * rows,
                    speed: 0.35 + Math.random() * 0.55,
                    len: 6 + Math.floor(Math.random() * 10),
                    seed: Math.floor(Math.random() * 1000),
                    isRed: (c % 7 === 0)
                });
            }
            rainDrops = arr;
        }

        // Batch renderer: sets ctx.fillStyle at most 3 times per frame across the whole screen
        function flushBatches(ctx, dimCh, dimX, dimY, brCh, brX, brY, redCh, redX, redY) {
            var i, n;
            n = dimCh.length;
            if (n > 0) {
                ctx.fillStyle = "rgba(205, 214, 228, 0.36)";
                for (i = 0; i < n; i++) {
                    ctx.fillText(dimCh[i], dimX[i], dimY[i]);
                }
            }
            n = brCh.length;
            if (n > 0) {
                ctx.fillStyle = "rgba(255, 255, 255, 0.90)";
                for (i = 0; i < n; i++) {
                    ctx.fillText(brCh[i], brX[i], brY[i]);
                }
            }
            n = redCh.length;
            if (n > 0) {
                ctx.fillStyle = "#D71921";
                for (i = 0; i < n; i++) {
                    ctx.fillText(redCh[i], redX[i], redY[i]);
                }
            }
        }

        onPaint: {
            var ctx = getContext("2d");
            var w = width;
            var h = height;
            if (w <= 0 || h <= 0) return;

            ctx.fillStyle = "#07080A";
            ctx.fillRect(0, 0, w, h);

            var preset = root.currentPreset;
            var t = root.timeSec;
            var cx = root.smoothCursorX;
            var cy = root.smoothCursorY;
            var energy = root.cursorEnergy;

            // Balanced 56x32 full-screen grid (1,792 cells, ~50% empty skipped)
            var cols = 56;
            var rows = 32;
            var cellW = w / cols;
            var cellH = h / rows;

            var fontSize = Math.max(12, Math.floor(cellH * 0.66));
            ctx.font = "bold " + fontSize + "px '" + (fontNMono.name || "monospace") + "'";
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";

            var dimCh = [], dimX = [], dimY = [];
            var brCh = [], brX = [], brY = [];
            var redCh = [], redX = [], redY = [];

            // =================================================================
            // PRESET 1: TOPOGRAPHIC WAVE (Devault Contour Field + Cursor Ripple)
            // =================================================================
            if (preset === "topo-wave") {
                var ramp = "  .:-=+*#%@";
                var rampLen = ramp.length;

                for (var r = 0; r < rows; r++) {
                    var py = (r + 0.5) * cellH;
                    var ny = r / rows;

                    for (var c = 0; c < cols; c++) {
                        var px = (c + 0.5) * cellW;
                        var nx = c / cols;

                        var v1 = Math.sin(nx * 6.2 + t * 1.1 + Math.cos(ny * 4.0 - t * 0.7));
                        var v2 = Math.cos(ny * 5.5 - t * 0.8 + Math.sin(nx * 4.8 + t * 0.6));
                        var val = (v1 + v2) * 0.5;

                        var dx = px - cx;
                        var dy = py - cy;
                        var dist = Math.sqrt(dx * dx + dy * dy);
                        var cursorInfluence = Math.max(0.0, 1.0 - dist / 320.0);
                        var ripple = Math.sin(dist * 0.045 - t * 6.5) * cursorInfluence * (0.50 + energy * 0.50);

                        var combined = Math.max(0.0, Math.min(0.999, (val + ripple + 1.0) * 0.5));
                        var idx = Math.floor(combined * rampLen);
                        if (idx <= 1) continue;

                        var ch = ramp.charAt(idx);
                        if (cursorInfluence > 0.35 && Math.abs(Math.sin(dist * 0.045 - t * 6.5)) > 0.70) {
                            redCh.push(ch); redX.push(px); redY.push(py);
                        } else if (cursorInfluence > 0.16 || idx >= rampLen - 2) {
                            brCh.push(ch); brX.push(px); brY.push(py);
                        } else {
                            dimCh.push(ch); dimX.push(px); dimY.push(py);
                        }
                    }
                }
                flushBatches(ctx, dimCh, dimX, dimY, brCh, brX, brY, redCh, redX, redY);
            }

            // =================================================================
            // PRESET 2: NOTHING GLYPH VORTEX (Orbital Dot-Matrix + Cursor Pull)
            // =================================================================
            else if (preset === "glyph-vortex") {
                var gRamp = "  .:oO0*#@";
                var gLen = gRamp.length;
                var vx = w * 0.56 + (cx - w * 0.56) * 0.28;
                var vy = h * 0.50 + (cy - h * 0.50) * 0.28;

                for (var r2 = 0; r2 < rows; r2++) {
                    var py2 = (r2 + 0.5) * cellH;
                    for (var c2 = 0; c2 < cols; c2++) {
                        var px2 = (c2 + 0.5) * cellW;
                        var dx2 = px2 - vx;
                        var dy2 = py2 - vy;
                        var radius = Math.sqrt(dx2 * dx2 + dy2 * dy2);
                        var angle = Math.atan2(dy2, dx2);

                        var spiral = Math.sin(angle * 4.0 - radius * 0.018 + t * 2.0);
                        var rings = Math.cos(radius * 0.032 - t * 2.6);
                        var field = (spiral * 0.55 + rings * 0.45 + 1.0) * 0.5;

                        var cDist = Math.hypot(px2 - cx, py2 - cy);
                        var cGlow = Math.max(0.0, 1.0 - cDist / 250.0);

                        var norm = Math.max(0.0, Math.min(0.999, field * 0.85 + cGlow * 0.35));
                        var gIdx = Math.floor(norm * gLen);
                        if (gIdx <= 1) continue;

                        var gCh = gRamp.charAt(gIdx);
                        if (Math.abs(radius - 210 - Math.sin(t * 1.6) * 28) < 20 || (cGlow > 0.50 && gIdx >= 6)) {
                            redCh.push(gCh); redX.push(px2); redY.push(py2);
                        } else if (cGlow > 0.18 || gIdx >= gLen - 2) {
                            brCh.push(gCh); brX.push(px2); brY.push(py2);
                        } else {
                            dimCh.push(gCh); dimX.push(px2); dimY.push(py2);
                        }
                    }
                }
                flushBatches(ctx, dimCh, dimX, dimY, brCh, brX, brY, redCh, redX, redY);
            }

            // =================================================================
            // PRESET 3: TERMINAL GLYPH RAIN (Cyber Matrix + Cursor Magnetic Glow)
            // =================================================================
            else if (preset === "cyber-rain") {
                ensureRainDrops(cols, rows);
                var rainChars = "0123456789ABCDEF:+*#<>=";
                var rCharLen = rainChars.length;

                for (var c3 = 0; c3 < cols; c3++) {
                    var drop = rainDrops[c3];
                    var px3 = (c3 + 0.5) * cellW;
                    drop.y += drop.speed;
                    if (drop.y - drop.len > rows) {
                        drop.y = -Math.random() * 6;
                        drop.speed = 0.35 + Math.random() * 0.55;
                        drop.len = 6 + Math.floor(Math.random() * 10);
                    }

                    var headRow = Math.floor(drop.y);
                    for (var k = 0; k < drop.len; k++) {
                        var r3 = headRow - k;
                        if (r3 < 0 || r3 >= rows) continue;
                        var py3 = (r3 + 0.5) * cellH;

                        var dist3 = Math.hypot(px3 - cx, py3 - cy);
                        var nearCursor = dist3 < 190;

                        var charHash = (c3 * 31 + r3 * 17 + Math.floor(t * 6.0) + drop.seed) % rCharLen;
                        var ch3 = rainChars.charAt(Math.abs(charHash));

                        if (nearCursor || (k === 0 && drop.isRed)) {
                            redCh.push(ch3); redX.push(px3); redY.push(py3);
                        } else if (k <= 1) {
                            brCh.push(ch3); brX.push(px3); brY.push(py3);
                        } else {
                            dimCh.push(ch3); dimX.push(px3); dimY.push(py3);
                        }
                    }
                }
                flushBatches(ctx, dimCh, dimX, dimY, brCh, brX, brY, redCh, redX, redY);
            }

            // =================================================================
            // PRESET 4: 3D ASCII TORUS (Interactive 3D Donut Tilted by Cursor)
            // =================================================================
            else if (preset === "ascii-torus") {
                var shadeRamp = ".,-~:;=!*#$@";
                var centerCol = Math.floor(cols * 0.56);
                var centerRow = Math.floor(rows * 0.50);

                var A = t * 1.35 + ((cy / h) - 0.5) * 2.4;
                var B = t * 0.85 + ((cx / w) - 0.5) * 2.4;
                var cosA = Math.cos(A), sinA = Math.sin(A);
                var cosB = Math.cos(B), sinB = Math.sin(B);

                var zbuf = new Array(cols * rows).fill(0);
                var outCh = new Array(cols * rows).fill("");
                var outLum = new Array(cols * rows).fill(0);

                for (var theta = 0; theta < 6.283; theta += 0.11) {
                    var cost = Math.cos(theta), sint = Math.sin(theta);
                    for (var phi = 0; phi < 6.283; phi += 0.045) {
                        var cosp = Math.cos(phi), sinp = Math.sin(phi);
                        var circleX = 2.0 + 1.05 * cost;
                        var circleY = 1.05 * sint;

                        var x3 = circleX * (cosB * cosp + sinA * sinB * sinp) - circleY * cosA * sinB;
                        var y3 = circleX * (sinB * cosp - sinA * cosB * sinp) + circleY * cosA * cosB;
                        var z3 = 4.8 + cosA * circleX * sinp + circleY * sinA;
                        var ooz = 1.0 / z3;

                        var xp = Math.floor(centerCol + 26.0 * ooz * x3);
                        var yp = Math.floor(centerRow - 14.5 * ooz * y3);
                        if (xp < 0 || xp >= cols || yp < 0 || yp >= rows) continue;

                        var L = cosp * cost * sinB - cosA * cost * sinp - sinA * sint + cosB * (cosA * sint - cost * sinA * sinp);
                        var bIdx = xp + yp * cols;
                        if (ooz > zbuf[bIdx]) {
                            zbuf[bIdx] = ooz;
                            var lumIdx = Math.max(0, Math.min(11, Math.floor((L + 1.4) * 4.5)));
                            outCh[bIdx] = shadeRamp.charAt(lumIdx);
                            outLum[bIdx] = lumIdx;
                        }
                    }
                }

                for (var tr = 0; tr < rows; tr++) {
                    var tpy = (tr + 0.5) * cellH;
                    for (var tc = 0; tc < cols; tc++) {
                        var tpx = (tc + 0.5) * cellW;
                        var mIdx = tc + tr * cols;
                        var ch4 = outCh[mIdx];
                        if (ch4 === "") {
                            // Subtle animated background dot-wave so empty space also breathes
                            if (tr % 2 === 0 && tc % 2 === 0) {
                                var bgWave = Math.sin(tc * 0.25 + tr * 0.20 - t * 1.8);
                                if (bgWave > 0.15) {
                                    dimCh.push(bgWave > 0.75 ? "+" : ".");
                                    dimX.push(tpx);
                                    dimY.push(tpy);
                                }
                            }
                            continue;
                        }
                        var lv = outLum[mIdx];
                        if (lv >= 10) {
                            redCh.push(ch4); redX.push(tpx); redY.push(tpy);
                        } else if (lv >= 5) {
                            brCh.push(ch4); brX.push(tpx); brY.push(tpy);
                        } else {
                            dimCh.push(ch4); dimX.push(tpx); dimY.push(tpy);
                        }
                    }
                }
                flushBatches(ctx, dimCh, dimX, dimY, brCh, brX, brY, redCh, redX, redY);
            }

            // =================================================================
            // PRESET 5: HALFTONE DOTS & MOIRÉ (Devault Halftone Interference)
            // =================================================================
            else if (preset === "halftone-pulse") {
                var hRamp = "  .:oO0@#";
                var hLen = hRamp.length;
                var s1x = w * 0.5 + Math.cos(t * 0.9) * (w * 0.22);
                var s1y = h * 0.5 + Math.sin(t * 0.7) * (h * 0.20);

                for (var r5 = 0; r5 < rows; r5++) {
                    var py5 = (r5 + 0.5) * cellH;
                    for (var c5 = 0; c5 < cols; c5++) {
                        var px5 = (c5 + 0.5) * cellW;
                        var d1 = Math.hypot(px5 - s1x, py5 - s1y);
                        var d2 = Math.hypot(px5 - cx, py5 - cy);

                        var w1 = Math.sin(d1 * 0.035 - t * 2.6);
                        var w2 = Math.sin(d2 * 0.042 - t * 3.2);
                        var moire = (w1 + w2 + 2.0) * 0.25;

                        var hIdx = Math.max(0, Math.min(hLen - 1, Math.floor(moire * hLen)));
                        if (hIdx <= 1) continue;

                        var ch5 = hRamp.charAt(hIdx);
                        if (d2 < 220 && hIdx >= hLen - 2) {
                            redCh.push(ch5); redX.push(px5); redY.push(py5);
                        } else if (hIdx >= hLen - 3) {
                            brCh.push(ch5); brX.push(px5); brY.push(py5);
                        } else {
                            dimCh.push(ch5); dimX.push(px5); dimY.push(py5);
                        }
                    }
                }
                flushBatches(ctx, dimCh, dimX, dimY, brCh, brX, brY, redCh, redX, redY);
            }

            // =================================================================
            // PRESET 6: CHAMELEON IMAGE-TO-ASCII LIVE (Wallpaper Photo -> ASCII)
            // =================================================================
            else if (preset === "wallpaper-ascii") {
                var imgRamp = "  .:-=+*#%@";
                var imgLen = imgRamp.length;
                var cells = root.sampleCells;
                var sCols = root.sampleCols;
                var sRows = root.sampleRows;

                if (!cells || cells.length < sCols * sRows) {
                    ctx.fillStyle = "rgba(255, 255, 255, 0.5)";
                    ctx.fillText("SAMPLING WALLPAPER TO ASCII MATRIX...", w * 0.5, h * 0.5);
                    return;
                }

                for (var ir = 0; ir < rows; ir++) {
                    var ipy = (ir + 0.5) * cellH;
                    var sr = Math.min(sRows - 1, Math.floor(ir * sRows / rows));

                    for (var ic = 0; ic < cols; ic++) {
                        var ipx = (ic + 0.5) * cellW;
                        var sc = Math.min(sCols - 1, Math.floor(ic * sCols / cols));
                        var cell = cells[sr * sCols + sc];
                        var baseLum = cell[0];

                        var iDist = Math.hypot(ipx - cx, ipy - cy);
                        var cWave = (iDist < 240)
                            ? Math.sin(iDist * 0.05 - t * 6.0) * (1.0 - iDist / 240.0) * 0.32
                            : 0.0;

                        var breath = Math.sin(ic * 0.18 + ir * 0.14 + t * 1.8) * 0.07;
                        var lum = Math.max(0.0, Math.min(0.999, baseLum + breath + cWave));
                        var charI = Math.floor(lum * imgLen);
                        if (charI <= 1) continue;

                        var sym = imgRamp.charAt(charI);
                        if (iDist < 170 && charI >= imgLen - 3) {
                            redCh.push(sym); redX.push(ipx); redY.push(ipy);
                        } else if (charI >= imgLen - 4 || iDist < 220) {
                            brCh.push(sym); brX.push(ipx); brY.push(ipy);
                        } else {
                            dimCh.push(sym); dimX.push(ipx); dimY.push(ipy);
                        }
                    }
                }
                flushBatches(ctx, dimCh, dimX, dimY, brCh, brX, brY, redCh, redX, redY);
            }
        }
    }
}
