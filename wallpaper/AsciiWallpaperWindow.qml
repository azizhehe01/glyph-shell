import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

// =============================================================================
// Nothing OS 3.0 / glyph-shell 100% Pure GPU Live ASCII Wallpaper Engine
// Powered by compiled Qt6 RHI ShaderEffect (ascii_wallpaper.frag.qsb) +
// LetteraMonoLL GPU Font Atlas. Zero JS per-frame loops (0% CPU usage) +
// Smart Window Auto-Pause + Live GPU Snapshot Sync for hyprlock Lockscreen.
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

    property bool shaderReady: false
    property string atlasSource: ""
    property string wallpaperSource: ""

    readonly property bool isShowing: root.asciiEnabled || root.previewActive
    readonly property string currentPreset: (root.previewActive && root.previewPreset !== "")
        ? root.previewPreset
        : root.activePreset

    readonly property int currentPresetId: {
        var p = root.currentPreset;
        if (p === "topo-wave") return 0;
        if (p === "glyph-vortex") return 1;
        if (p === "cyber-rain") return 2;
        if (p === "ascii-torus") return 3;
        if (p === "halftone-pulse") return 4;
        if (p === "wallpaper-ascii") return 5;
        return 0;
    }

    // Auto-Pause when any window is open on the current workspace (unless previewing in Ctrl+Super+W)
    readonly property bool shouldAnimate: root.isShowing && (root.previewActive || !root.hasOpenWindow)

    visible: root.isShowing
    color: "#07080A"

    // Live cursor coordinates injected from NotchWindow — smoothed in native C++ scenegraph
    property real rawCursorX: 960
    property real rawCursorY: 540
    property real smoothCursorX: root.rawCursorX
    property real smoothCursorY: root.rawCursorY
    property real cursorEnergy: 0.45

    Behavior on smoothCursorX {
        enabled: root.shouldAnimate
        SmoothedAnimation { velocity: 1500; duration: 80 }
    }
    Behavior on smoothCursorY {
        enabled: root.shouldAnimate
        SmoothedAnimation { velocity: 1500; duration: 80 }
    }

    // Pure C++/GPU scenegraph time driver (0% JS per-frame execution)
    property real shaderTime: 0.0
    NumberAnimation on shaderTime {
        from: 0.0
        to: 62831.853
        duration: 62831853
        loops: Animation.Infinite
        running: root.isShowing
        paused: !root.shouldAnimate
    }

    // Load persisted ASCII state and ensure GPU shader + font atlas exist
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
                    if (d.atlas) root.atlasSource = "file://" + d.atlas;
                    if (d.wallpaper) root.wallpaperSource = "file://" + d.wallpaper;
                    if (d.qsb) {
                        root.shaderReady = false;
                        root.shaderReady = true;
                    }
                    if (root.asciiEnabled) {
                        lockSnapshotTimer.restart();
                    }
                } catch (e) {}
            }
        }
    }

    function reloadWallpaperSample(): void {
        if (!initAsciiStateProc.running) {
            initAsciiStateProc.running = true;
        }
    }

    function snapshotToLockscreen(): void {
        if (shaderLoader.item && root.isShowing) {
            shaderLoader.item.grabToImage(function(result) {
                if (result) {
                    result.saveToFile("/tmp/nothing_lock_ascii.png");
                }
            });
        }
    }

    // Delayed one-shot GPU frame capture so lockscreen matches the exact GPU shader output
    Timer {
        id: lockSnapshotTimer
        interval: 450
        repeat: false
        onTriggered: {
            if (root.asciiEnabled) {
                root.snapshotToLockscreen();
            }
        }
    }

    onActivePresetChanged: {
        if (root.asciiEnabled) {
            lockSnapshotTimer.restart();
        }
    }

    onAsciiEnabledChanged: {
        if (root.asciiEnabled) {
            lockSnapshotTimer.restart();
        }
    }

    IpcHandler {
        target: "asciiwallpaper"
        function snapshot(): void {
            root.snapshotToLockscreen();
        }
    }

    // GPU Texture 1: 16-slot Nothing Monospace (LetteraMonoLL) Glyph Atlas
    Image {
        id: fontAtlasImage
        source: root.atlasSource
        visible: false
        smooth: true
        cache: true
    }

    // GPU Texture 2: Active Desktop Wallpaper for Chameleon Image-to-ASCII Shader
    Image {
        id: currentWallpaperImage
        source: root.wallpaperSource
        visible: false
        smooth: true
        cache: false
    }

    // 100% Pure GPU Fragment Shader Renderer (SPIR-V / GLSL via Qt6 RHI)
    Loader {
        id: shaderLoader
        anchors.fill: parent
        active: root.shaderReady && root.isShowing

        sourceComponent: ShaderEffect {
            id: asciiShader
            anchors.fill: parent

            property real timeSec: root.shaderTime
            property real widthPx: width
            property real heightPx: height
            property real cursorX: root.smoothCursorX
            property real cursorY: root.smoothCursorY
            property real cursorEnergy: root.cursorEnergy
            property int presetId: root.currentPresetId
            property variant fontAtlas: fontAtlasImage
            property variant wallpaperTex: currentWallpaperImage

            fragmentShader: Qt.resolvedUrl("ascii_wallpaper_v2.frag.qsb")
        }
    }
}
