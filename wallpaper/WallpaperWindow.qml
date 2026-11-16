import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects

// =============================================================================
// Nothing OS 3.0 / glyph-shell Native Wallpaper Carousel
// Shortcut: Ctrl + Super + W (Toggle Selector) | Super + Shift + W (Random)
// Bottom-edge Horizontal Filmstrip with 60fps Live Instant Desktop Preview
// =============================================================================
PanelWindow {
    id: root

    // Reference to DesktopWidgetsWindow to refresh frosted glass blur on apply
    property var desktopWidgetsRef: null
    property var asciiWallpaperRef: null

    WlrLayershell.namespace: "quickshell:wallpaper"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.showWindow ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: WlrLayershell.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"

    property bool isOpen: false
    property bool showWindow: false
    visible: showWindow

    readonly property int screenW: root.screen ? root.screen.width : 1920
    readonly property int screenH: root.screen ? root.screen.height : 1080
    readonly property int dockW: Math.min(root.screenW - 72, 1240)
    readonly property int dockH: 226

    property var wallpapers: []
    property string folderPath: "~/.config/quickshell/DesktopWidgetsApp/wallpapers"
    property string originalWallpaper: ""
    property string previewedWallpaper: ""
    property int selectedIndex: 0

    // Dual-Mode: "image" vs "ascii"
    property string activeMode: "image"
    property bool originalAsciiEnabled: false
    property string originalAsciiPreset: "silent-blade"
    property string originalAsciiBgColor: "#07080A"
    property string selectedAsciiBgColor: "#07080A"
    property bool colorPickerOpen: false
    property real hsvH: 0.61
    property real hsvS: 0.30
    property real hsvV: 0.04
    property int selectedAsciiIndex: 0

    readonly property var asciiPresets: [
        {
            id: "silent-blade",
            title: "SILENT BLADE",
            res: "480×270 · SHADE BLOCKS",
            tag: "MINIMALIST",
            art: [
                "                ▓▓                ",
                "               ▒██▓               ",
                "               ▒██▓               ",
                "           ░░░░♦♦♦♦░░░░           ",
                "                ▒▒                "
            ]
        }
    ]

    readonly property var currentSelectedObj: {
        if (root.activeMode === "ascii") {
            return (root.selectedAsciiIndex >= 0 && root.selectedAsciiIndex < root.asciiPresets.length)
                ? root.asciiPresets[root.selectedAsciiIndex]
                : null;
        }
        return (root.wallpapers && root.wallpapers.length > 0 && root.selectedIndex >= 0 && root.selectedIndex < root.wallpapers.length)
            ? root.wallpapers[root.selectedIndex]
            : null;
    }

    readonly property bool isPreviewingNew: {
        if (root.activeMode === "ascii") {
            return !root.originalAsciiEnabled
                || (root.currentSelectedObj && root.currentSelectedObj.id !== root.originalAsciiPreset)
                || (root.selectedAsciiBgColor.toUpperCase() !== root.originalAsciiBgColor.toUpperCase());
        }
        return root.originalAsciiEnabled || (root.currentSelectedObj && root.originalWallpaper !== "" && root.currentSelectedObj.path !== root.originalWallpaper);
    }

    function hsvToHex(h: real, s: real, v: real): string {
        var i = Math.floor(h * 6);
        var f = h * 6 - i;
        var p = v * (1 - s);
        var q = v * (1 - f * s);
        var t = v * (1 - (1 - f) * s);
        var r = 0, g = 0, b = 0;
        switch (i % 6) {
            case 0: r = v; g = t; b = p; break;
            case 1: r = q; g = v; b = p; break;
            case 2: r = p; g = v; b = t; break;
            case 3: r = p; g = q; b = v; break;
            case 4: r = t; g = p; b = v; break;
            case 5: r = v; g = p; b = q; break;
        }
        function toH(c) {
            var val = Math.max(0, Math.min(255, Math.round(c * 255)));
            var s2 = val.toString(16).toUpperCase();
            return s2.length < 2 ? "0" + s2 : s2;
        }
        return "#" + toH(r) + toH(g) + toH(b);
    }

    function syncHsvFromHex(hexStr: string): void {
        if (!/^#[0-9A-Fa-f]{6}$/.test(hexStr)) return;
        var r = parseInt(hexStr.substr(1, 2), 16) / 255.0;
        var g = parseInt(hexStr.substr(3, 2), 16) / 255.0;
        var b = parseInt(hexStr.substr(5, 2), 16) / 255.0;
        var max = Math.max(r, g, b);
        var min = Math.min(r, g, b);
        var d = max - min;
        var h = root.hsvH;
        var s = (max === 0) ? 0 : d / max;
        var v = max;
        if (d !== 0) {
            if (max === r) h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
            else if (max === g) h = ((b - r) / d + 2) / 6;
            else h = ((r - g) / d + 4) / 6;
        }
        root.hsvH = Math.max(0, Math.min(1, h));
        root.hsvS = Math.max(0, Math.min(1, s));
        root.hsvV = Math.max(0, Math.min(1, v));
    }

    function applyHsvPreview(): void {
        var hex = hsvToHex(root.hsvH, root.hsvS, root.hsvV);
        root.selectedAsciiBgColor = hex;
        if (root.asciiWallpaperRef) {
            root.asciiWallpaperRef.previewBgColor = hex;
            root.asciiWallpaperRef.previewActive = true;
        }
    }

    function applyHexPreview(hexStr: string): void {
        var clean = hexStr.trim().toUpperCase();
        if (!/^#[0-9A-F]{6}$/.test(clean)) return;
        root.selectedAsciiBgColor = clean;
        syncHsvFromHex(clean);
        if (root.asciiWallpaperRef) {
            root.asciiWallpaperRef.previewBgColor = clean;
            root.asciiWallpaperRef.previewActive = true;
        }
    }

    // Official Nothing OS Typography
    FontLoader { id: fontNdot55; source: Qt.resolvedUrl("../assets/fonts/Ndot55-Regular.otf") }
    FontLoader { id: fontNdot57; source: Qt.resolvedUrl("../assets/fonts/Ndot57-Regular.otf") }
    FontLoader { id: fontNType;  source: Qt.resolvedUrl("../assets/fonts/NType82-Regular.otf") }
    FontLoader { id: fontNMono;  source: Qt.resolvedUrl("../assets/fonts/LetteraMonoLL-Regular.otf") }

    // Theme Tokens — Chameleon Frosted Glass (High Transparency, Aligned with App Launcher)
    readonly property color glassBg: Qt.rgba(0.05, 0.06, 0.08, 0.30)
    readonly property color glassBorder: Qt.rgba(1.0, 1.0, 1.0, 0.16)
    readonly property color nothingRed: "#D71921"
    readonly property color textPrimary: "#FFFFFF"
    readonly property color textSecondary: Qt.rgba(1.0, 1.0, 1.0, 0.72)
    readonly property color textMuted: Qt.rgba(1.0, 1.0, 1.0, 0.42)

    HyprlandFocusGrab {
        id: focusGrab
        windows: [root]
        active: false
        onCleared: {
            if (root.isOpen) {
                root.cancelAndClose();
            }
        }
    }

    Timer {
        id: grabDelayTimer
        interval: 40
        repeat: false
        onTriggered: {
            focusGrab.active = root.isOpen;
            if (root.isOpen) {
                keyCatcher.forceActiveFocus();
            }
        }
    }

    // Debounce timer for buttery-smooth Live Instant Preview when scrubbing with arrow keys
    Timer {
        id: previewDebounceTimer
        interval: 75
        repeat: false
        onTriggered: {
            if (!root.isOpen || !root.currentSelectedObj) return;
            var targetPath = root.currentSelectedObj.path;
            if (targetPath && targetPath !== root.previewedWallpaper) {
                root.previewedWallpaper = targetPath;
                Quickshell.execDetached([
                    "python3",
                    Quickshell.shellDir + "/wallpaper/wallpaper.py",
                    "preview",
                    targetPath
                ]);
            }
        }
    }

    // Delayed refresh of desktop widgets after applying new wallpaper
    Timer {
        id: refreshWidgetsTimer
        interval: 600
        repeat: false
        onTriggered: {
            if (root.desktopWidgetsRef) {
                root.desktopWidgetsRef.refreshStats();
            }
        }
    }

    // Load wallpapers list from wallpaper/wallpaper.py
    Process {
        id: loadWallpapersProc
        command: ["python3", Quickshell.shellDir + "/wallpaper/wallpaper.py", "list"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var raw = this.text.trim();
                    if (!raw) return;
                    var data = JSON.parse(raw);
                    var list = data.wallpapers || [];
                    root.wallpapers = list;
                    if (data.folder) root.folderPath = data.folder;
                    if (data.current) {
                        root.originalWallpaper = data.current;
                        if (!root.previewedWallpaper) {
                            root.previewedWallpaper = data.current;
                        }
                    }

                    // Position selection on active wallpaper
                    var activeIdx = 0;
                    for (var i = 0; i < list.length; i++) {
                        if (list[i].active || list[i].path === root.originalWallpaper) {
                            activeIdx = i;
                            root.originalWallpaper = list[i].path;
                            root.previewedWallpaper = list[i].path;
                            break;
                        }
                    }
                    root.selectedIndex = activeIdx;
                    if (data.ascii) {
                        root.originalAsciiEnabled = !!data.ascii.enabled;
                        if (data.ascii.bg_color) {
                            root.originalAsciiBgColor = data.ascii.bg_color;
                            root.selectedAsciiBgColor = data.ascii.bg_color;
                            root.syncHsvFromHex(data.ascii.bg_color);
                        }
                        if (data.ascii.preset) {
                            root.originalAsciiPreset = data.ascii.preset;
                            for (var j = 0; j < root.asciiPresets.length; j++) {
                                if (root.asciiPresets[j].id === data.ascii.preset) {
                                    root.selectedAsciiIndex = j;
                                    break;
                                }
                            }
                        }
                    }
                    centerTimer.restart();
                } catch (e) {}
            }
        }
    }

    Timer {
        id: centerTimer
        interval: 30
        repeat: false
        onTriggered: {
            if (root.activeMode === "ascii") {
                if (asciiFilmstripList.count > 0) {
                    asciiFilmstripList.positionViewAtIndex(root.selectedAsciiIndex, ListView.Center);
                }
            } else if (filmstripList.count > 0) {
                filmstripList.positionViewAtIndex(root.selectedIndex, ListView.Center);
            }
        }
    }

    // Process to commit ASCII preset state
    Process {
        id: applyAsciiProc
        property string targetPreset: "silent-blade"
        property string targetBgColor: "#07080A"
        command: ["python3", Quickshell.shellDir + "/wallpaper/wallpaper.py", "apply-ascii", targetPreset, targetBgColor]
        running: false
    }

    // Process to commit wallpaper & update frosted glass blur
    Process {
        id: applyWallpaperProc
        property string targetPath: ""
        property bool alreadyPreviewed: false
        command: {
            var args = ["python3", Quickshell.shellDir + "/wallpaper/wallpaper.py", "apply", targetPath];
            if (alreadyPreviewed) args.push("--already-previewed");
            return args;
        }
        running: false
        onExited: (exitCode, exitStatus) => {
            if (root.desktopWidgetsRef) {
                root.desktopWidgetsRef.refreshStats();
            }
        }
    }

    // Process for random wallpaper shortcut (Super + Shift + W)
    Process {
        id: randomWallpaperProc
        command: ["python3", Quickshell.shellDir + "/wallpaper/wallpaper.py", "random"]
        running: false
        onExited: (exitCode, exitStatus) => {
            if (root.desktopWidgetsRef) {
                root.desktopWidgetsRef.refreshStats();
            }
            if (!loadWallpapersProc.running) {
                loadWallpapersProc.running = true;
            }
        }
    }

    function switchMode(newMode: string): void {
        if (newMode !== "image" && newMode !== "ascii") return;
        root.activeMode = newMode;
        if (newMode === "ascii") {
            previewDebounceTimer.stop();
            var presetObj = root.asciiPresets[root.selectedAsciiIndex];
            if (root.asciiWallpaperRef && presetObj) {
                root.asciiWallpaperRef.previewPreset = presetObj.id;
                root.asciiWallpaperRef.previewBgColor = root.selectedAsciiBgColor;
                root.asciiWallpaperRef.previewActive = true;
            }
            centerTimer.restart();
        } else {
            root.colorPickerOpen = false;
            if (root.asciiWallpaperRef) {
                root.asciiWallpaperRef.previewActive = false;
                root.asciiWallpaperRef.previewBgColor = "";
                root.asciiWallpaperRef.asciiEnabled = false;
            }
            previewDebounceTimer.restart();
            centerTimer.restart();
        }
    }

    function toggleMode(): void {
        switchMode(root.activeMode === "image" ? "ascii" : "image");
    }

    function selectAsciiIndex(idx: int, triggerPreview: bool): void {
        var count = root.asciiPresets.length;
        if (count <= 0) return;
        var clamped = idx;
        if (clamped < 0) clamped = count - 1;
        if (clamped >= count) clamped = 0;

        root.selectedAsciiIndex = clamped;
        asciiFilmstripList.positionViewAtIndex(clamped, ListView.Center);
        if (triggerPreview && root.asciiWallpaperRef) {
            root.asciiWallpaperRef.previewPreset = root.asciiPresets[clamped].id;
            root.asciiWallpaperRef.previewActive = true;
        }
    }

    function selectIndex(idx: int, triggerPreview: bool): void {
        if (root.activeMode === "ascii") {
            selectAsciiIndex(idx, triggerPreview);
            return;
        }
        var count = root.wallpapers ? root.wallpapers.length : 0;
        if (count <= 0) return;
        var clamped = idx;
        // Wrap around smoothly at ends
        if (clamped < 0) clamped = count - 1;
        if (clamped >= count) clamped = 0;

        root.selectedIndex = clamped;
        filmstripList.positionViewAtIndex(clamped, ListView.Center);
        if (triggerPreview) {
            if (root.asciiWallpaperRef) {
                root.asciiWallpaperRef.previewActive = false;
                root.asciiWallpaperRef.asciiEnabled = false;
            }
            previewDebounceTimer.restart();
        }
    }

    function moveSelection(delta: int): void {
        if (root.activeMode === "ascii") {
            selectAsciiIndex(root.selectedAsciiIndex + delta, true);
        } else {
            selectIndex(root.selectedIndex + delta, true);
        }
    }

    function pickRandomPreview(): void {
        if (root.activeMode === "ascii") {
            var acount = root.asciiPresets.length;
            if (acount <= 1) return;
            var anext = (root.selectedAsciiIndex + 1 + Math.floor(Math.random() * (acount - 1))) % acount;
            selectAsciiIndex(anext, true);
            return;
        }
        var count = root.wallpapers ? root.wallpapers.length : 0;
        if (count <= 1) return;
        var next = root.selectedIndex;
        for (var tries = 0; tries < 10; tries++) {
            var cand = Math.floor(Math.random() * count);
            if (cand !== root.selectedIndex) {
                next = cand;
                break;
            }
        }
        selectIndex(next, true);
    }

    function openWallpaperFolder(): void {
        Quickshell.execDetached([
            "python3",
            Quickshell.shellDir + "/wallpaper/wallpaper.py",
            "open-folder"
        ]);
    }

    function confirmSelection(): void {
        previewDebounceTimer.stop();
        if (!root.currentSelectedObj) {
            root.closeInternal();
            return;
        }

        if (root.activeMode === "ascii") {
            var chosenPreset = root.currentSelectedObj.id;
            var chosenBg = root.selectedAsciiBgColor;
            root.colorPickerOpen = false;
            root.originalAsciiEnabled = true;
            root.originalAsciiPreset = chosenPreset;
            root.originalAsciiBgColor = chosenBg;
            if (root.asciiWallpaperRef) {
                root.asciiWallpaperRef.activePreset = chosenPreset;
                root.asciiWallpaperRef.activeBgColor = chosenBg;
                root.asciiWallpaperRef.previewBgColor = "";
                root.asciiWallpaperRef.asciiEnabled = true;
                root.asciiWallpaperRef.previewActive = false;
            }
            applyAsciiProc.targetPreset = chosenPreset;
            applyAsciiProc.targetBgColor = chosenBg;
            applyAsciiProc.running = false;
            applyAsciiProc.running = true;
            root.closeInternal();
            return;
        }

        var chosenPath = root.currentSelectedObj.path;
        var wasPreviewed = (root.previewedWallpaper === chosenPath);
        root.originalWallpaper = chosenPath;
        root.previewedWallpaper = chosenPath;
        root.originalAsciiEnabled = false;

        if (root.asciiWallpaperRef) {
            root.asciiWallpaperRef.asciiEnabled = false;
            root.asciiWallpaperRef.previewActive = false;
            root.asciiWallpaperRef.reloadWallpaperSample();
        }

        applyWallpaperProc.targetPath = chosenPath;
        applyWallpaperProc.alreadyPreviewed = wasPreviewed;
        applyWallpaperProc.running = false;
        applyWallpaperProc.running = true;

        refreshWidgetsTimer.restart();
        root.closeInternal();
    }

    function cancelAndClose(): void {
        previewDebounceTimer.stop();
        root.colorPickerOpen = false;
        root.selectedAsciiBgColor = root.originalAsciiBgColor;
        root.syncHsvFromHex(root.originalAsciiBgColor);
        // Restore ASCII state if changed during preview
        if (root.asciiWallpaperRef) {
            root.asciiWallpaperRef.previewActive = false;
            root.asciiWallpaperRef.previewBgColor = "";
            root.asciiWallpaperRef.activePreset = root.originalAsciiPreset;
            root.asciiWallpaperRef.activeBgColor = root.originalAsciiBgColor;
            root.asciiWallpaperRef.asciiEnabled = root.originalAsciiEnabled;
        }
        // Revert to original wallpaper if Live Preview changed it
        if (root.originalWallpaper !== "" && root.previewedWallpaper !== "" && root.previewedWallpaper !== root.originalWallpaper) {
            root.previewedWallpaper = root.originalWallpaper;
            Quickshell.execDetached([
                "python3",
                Quickshell.shellDir + "/wallpaper/wallpaper.py",
                "preview",
                root.originalWallpaper
            ]);
        }
        root.closeInternal();
    }

    function open(): void {
        if (!loadWallpapersProc.running) {
            loadWallpapersProc.running = true;
        }
        if (root.asciiWallpaperRef) {
            root.originalAsciiEnabled = root.asciiWallpaperRef.asciiEnabled;
            root.originalAsciiPreset = root.asciiWallpaperRef.activePreset;
            root.activeMode = root.originalAsciiEnabled ? "ascii" : "image";
            for (var i = 0; i < root.asciiPresets.length; i++) {
                if (root.asciiPresets[i].id === root.originalAsciiPreset) {
                    root.selectedAsciiIndex = i;
                    break;
                }
            }
        }
        root.showWindow = true;
        root.isOpen = true;
        grabDelayTimer.restart();
        centerTimer.restart();
    }

    function closeInternal(): void {
        focusGrab.active = false;
        root.isOpen = false;
        if (!dockAnim.running) {
            root.showWindow = false;
        }
    }

    function toggle(): void {
        if (root.isOpen) root.cancelAndClose();
        else root.open();
    }

    function triggerRandomDirect(): void {
        if (root.isOpen) {
            root.pickRandomPreview();
        } else {
            randomWallpaperProc.running = false;
            randomWallpaperProc.running = true;
        }
    }

    IpcHandler {
        target: "wallpaper"
        function toggle(): void { root.toggle(); }
        function open(): void { root.open(); }
        function close(): void { root.cancelAndClose(); }
        function random(): void { root.triggerRandomDirect(); }
    }

    // Fullscreen invisible click-outside catcher (keeps desktop 100% clear for Live Preview)
    MouseArea {
        anchors.fill: parent
        hoverEnabled: false
        onClicked: root.cancelAndClose()
    }

    // Keyboard navigation handler
    Item {
        id: keyCatcher
        focus: true
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                root.moveSelection(-1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                root.moveSelection(1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Tab) {
                root.toggleMode();
                event.accepted = true;
            } else if (event.key === Qt.Key_Home) {
                root.selectIndex(0, true);
                event.accepted = true;
            } else if (event.key === Qt.Key_End) {
                var maxLen = (root.activeMode === "ascii") ? root.asciiPresets.length : root.wallpapers.length;
                root.selectIndex(Math.max(0, maxLen - 1), true);
                event.accepted = true;
            } else if (event.key === Qt.Key_R) {
                root.pickRandomPreview();
                event.accepted = true;
            } else if (event.key === Qt.Key_O) {
                root.openWallpaperFolder();
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                root.confirmSelection();
                event.accepted = true;
            } else if (event.key === Qt.Key_Escape) {
                root.cancelAndClose();
                event.accepted = true;
            }
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.isOpen
        onActivated: root.cancelAndClose()
    }

    Shortcut {
        sequence: "Ctrl+Meta+W"
        enabled: root.isOpen
        onActivated: root.cancelAndClose()
    }

    // =========================================================================
    // HSV Background Color Picker Popover (ASCII Mode)
    // =========================================================================
    Rectangle {
        id: hsvPopover
        visible: root.isOpen && root.activeMode === "ascii" && root.colorPickerOpen
        width: 264
        height: 268
        radius: 16
        anchors.bottom: dockWrapper.top
        anchors.bottomMargin: 12
        anchors.right: dockWrapper.right
        color: Qt.rgba(0.06, 0.07, 0.09, 0.92)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.18)
        z: 50

        // Absorb clicks inside popover so backdrop doesn't close the drawer
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // 1. 2D Saturation x Value Gradient Box
            Item {
                id: svBox
                Layout.fillWidth: true
                Layout.preferredHeight: 156

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: Qt.hsva(root.hsvH, 1.0, 1.0, 1.0)
                    clip: true

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "#FFFFFFFF" }
                            GradientStop { position: 1.0; color: "#00FFFFFF" }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop { position: 0.0; color: "#00000000" }
                            GradientStop { position: 1.0; color: "#FF000000" }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.16)
                    }

                    // Draggable circle indicator
                    Rectangle {
                        width: 14
                        height: 14
                        radius: 7
                        x: Math.max(0, Math.min(svBox.width - width, root.hsvS * svBox.width - width / 2))
                        y: Math.max(0, Math.min(svBox.height - height, (1.0 - root.hsvV) * svBox.height - height / 2))
                        color: "transparent"
                        border.width: 2
                        border.color: "#FFFFFF"

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -1
                            radius: 8
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.rgba(0, 0, 0, 0.55)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.CrossCursor
                        function updateSV(mx, my) {
                            root.hsvS = Math.max(0.0, Math.min(1.0, mx / svBox.width));
                            root.hsvV = Math.max(0.0, Math.min(1.0, 1.0 - (my / svBox.height)));
                            root.applyHsvPreview();
                        }
                        onPressed: (mouse) => updateSV(mouse.x, mouse.y)
                        onPositionChanged: (mouse) => { if (pressed) updateSV(mouse.x, mouse.y); }
                    }
                }
            }

            // 2. Preview Swatch + Rainbow Hue Slider
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    width: 28
                    height: 28
                    radius: 8
                    color: root.selectedAsciiBgColor
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.25)
                }

                Item {
                    id: hueTrack
                    Layout.fillWidth: true
                    height: 16

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 12
                        radius: 6
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.00; color: "#FF0000" }
                            GradientStop { position: 0.17; color: "#FFFF00" }
                            GradientStop { position: 0.33; color: "#00FF00" }
                            GradientStop { position: 0.50; color: "#00FFFF" }
                            GradientStop { position: 0.67; color: "#0000FF" }
                            GradientStop { position: 0.83; color: "#FF00FF" }
                            GradientStop { position: 1.00; color: "#FF0000" }
                        }
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.18)
                    }

                    Rectangle {
                        width: 16
                        height: 16
                        radius: 8
                        anchors.verticalCenter: parent.verticalCenter
                        x: Math.max(0, Math.min(hueTrack.width - width, root.hsvH * hueTrack.width - width / 2))
                        color: Qt.hsva(root.hsvH, 1.0, 1.0, 1.0)
                        border.width: 2
                        border.color: "#FFFFFF"
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        function updateHue(mx) {
                            root.hsvH = Math.max(0.0, Math.min(1.0, mx / hueTrack.width));
                            root.applyHsvPreview();
                        }
                        onPressed: (mouse) => updateHue(mouse.x)
                        onPositionChanged: (mouse) => { if (pressed) updateHue(mouse.x); }
                    }
                }
            }

            // 3. Editable #HEX Input + Reset Obsidian Button
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    height: 28
                    radius: 8
                    color: Qt.rgba(1, 1, 1, 0.07)
                    border.width: 1
                    border.color: hexInput.activeFocus ? root.nothingRed : Qt.rgba(1, 1, 1, 0.14)

                    TextInput {
                        id: hexInput
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: fontNMono.name
                        font.pixelSize: 11
                        color: root.textPrimary
                        text: root.selectedAsciiBgColor
                        maximumLength: 7
                        selectByMouse: true
                        onTextEdited: {
                            if (/^#[0-9A-Fa-f]{6}$/.test(text)) {
                                root.applyHexPreview(text);
                            }
                        }
                        Keys.onReturnPressed: {
                            root.applyHexPreview(text);
                            keyCatcher.forceActiveFocus();
                        }
                        Keys.onEscapePressed: {
                            keyCatcher.forceActiveFocus();
                            root.colorPickerOpen = false;
                        }
                    }
                }

                Rectangle {
                    height: 28
                    width: resetColLbl.implicitWidth + 18
                    radius: 8
                    color: resetColMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.07)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.14)

                    Text {
                        id: resetColLbl
                        anchors.centerIn: parent
                        text: "RESET"
                        font.family: fontNMono.name
                        font.pixelSize: 10
                        font.bold: true
                        color: root.textSecondary
                    }

                    MouseArea {
                        id: resetColMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.applyHexPreview("#07080A")
                    }
                }
            }
        }
    }

    // =========================================================================
    // Bottom-Edge Horizontal Filmstrip Drawer
    // =========================================================================
    Item {
        id: dockWrapper
        width: root.dockW
        height: root.dockH
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24

        opacity: root.isOpen ? 1.0 : 0.0
        transform: Translate {
            y: root.isOpen ? 0 : 260
            Behavior on y {
                NumberAnimation {
                    id: dockAnim
                    duration: 240
                    easing.type: Easing.OutCubic
                    onRunningChanged: {
                        if (!dockAnim.running && !root.isOpen) {
                            root.showWindow = false;
                        }
                    }
                }
            }
        }
        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
        }

        // Prevent clicks inside the dock from triggering the outside backdrop
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: (mouse) => { mouse.accepted = true; }
            onWheel: (wheel) => {
                if (wheel.angleDelta.y > 0 || wheel.angleDelta.x > 0) {
                    root.moveSelection(-1);
                } else if (wheel.angleDelta.y < 0 || wheel.angleDelta.x < 0) {
                    root.moveSelection(1);
                }
                wheel.accepted = true;
            }
        }

        // Main Frosted Obsidian Container (Aligned with Launcher & Sidebar)
        Rectangle {
            id: dockCard
            anchors.fill: parent
            radius: 26
            color: root.glassBg
            border.width: 1
            border.color: root.glassBorder
            clip: true

            // Top Specular Highlight Line
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 26
                anchors.rightMargin: 26
                height: 1
                color: Qt.rgba(1.0, 1.0, 1.0, 0.24)
            }

            // Subtle Nothing OS Dot-Matrix Background Accent along header
            Canvas {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 52
                opacity: 0.08
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    ctx.fillStyle = "#FFFFFF";
                    var step = 10;
                    for (var x = 14; x < width - 14; x += step) {
                        for (var y = 10; y < height; y += step) {
                            ctx.beginPath();
                            ctx.arc(x, y, 1.0, 0, Math.PI * 2);
                            ctx.fill();
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 14
                anchors.bottomMargin: 14
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                spacing: 10

                // =============================================================
                // Top Header Bar: Status, Title, Active Filename, Quick Actions
                // =============================================================
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    spacing: 12

                    // Left: Recording-style LED dot + Dot-Matrix Title + Count
                    RowLayout {
                        spacing: 9

                        Rectangle {
                            width: 9
                            height: 9
                            radius: 4.5
                            color: root.isPreviewingNew ? root.nothingRed : "#FFFFFF"

                            SequentialAnimation on opacity {
                                running: root.isOpen && root.isPreviewingNew
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.35; duration: 550; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0;  duration: 550; easing.type: Easing.InOutSine }
                            }
                        }

                        Text {
                            text: "WALLPAPER"
                            font.family: fontNdot57.name
                            font.pixelSize: 16
                            font.letterSpacing: 1.8
                            color: root.textPrimary
                        }

                        // Dual-Mode Switcher Pill: [ IMAGE ] | [ ASCII LIVE ] (Tab to toggle)
                        Rectangle {
                            height: 24
                            width: modeSwitchRow.implicitWidth + 8
                            radius: 12
                            color: Qt.rgba(0, 0, 0, 0.38)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.14)

                            RowLayout {
                                id: modeSwitchRow
                                anchors.centerIn: parent
                                spacing: 2

                                Rectangle {
                                    height: 18
                                    width: imgModeLbl.implicitWidth + 14
                                    radius: 9
                                    color: root.activeMode === "image" ? "#FFFFFF" : "transparent"

                                    Text {
                                        id: imgModeLbl
                                        anchors.centerIn: parent
                                        text: "IMAGE"
                                        font.family: fontNMono.name
                                        font.pixelSize: 9
                                        font.bold: true
                                        color: root.activeMode === "image" ? "#000000" : root.textSecondary
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.switchMode("image")
                                    }
                                }

                                Rectangle {
                                    height: 18
                                    width: asciiModeLbl.implicitWidth + 14
                                    radius: 9
                                    color: root.activeMode === "ascii" ? root.nothingRed : "transparent"

                                    Text {
                                        id: asciiModeLbl
                                        anchors.centerIn: parent
                                        text: "⠿ ASCII LIVE"
                                        font.family: fontNMono.name
                                        font.pixelSize: 9
                                        font.bold: true
                                        color: root.activeMode === "ascii" ? "#FFFFFF" : root.textSecondary
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.switchMode("ascii")
                                    }
                                }
                            }
                        }

                        // Counter Pill [ 03 / 17 ]
                        Rectangle {
                            height: 22
                            width: countLabel.implicitWidth + 16
                            radius: 11
                            color: Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.12)

                            Text {
                                id: countLabel
                                anchors.centerIn: parent
                                text: {
                                    var total = (root.activeMode === "ascii")
                                        ? root.asciiPresets.length
                                        : (root.wallpapers ? root.wallpapers.length : 0);
                                    var cur = total > 0
                                        ? ((root.activeMode === "ascii" ? root.selectedAsciiIndex : root.selectedIndex) + 1)
                                        : 0;
                                    var curStr = cur < 10 ? ("0" + cur) : ("" + cur);
                                    var totStr = total < 10 ? ("0" + total) : ("" + total);
                                    return curStr + " / " + totStr;
                                }
                                font.family: fontNMono.name
                                font.pixelSize: 11
                                color: root.textSecondary
                            }
                        }

                        // Live Preview Indicator Badge
                        Rectangle {
                            visible: root.isPreviewingNew
                            height: 22
                            width: liveLabel.implicitWidth + 16
                            radius: 11
                            color: Qt.rgba(0.84, 0.10, 0.13, 0.22)
                            border.width: 1
                            border.color: root.nothingRed

                            Text {
                                id: liveLabel
                                anchors.centerIn: parent
                                text: "LIVE PREVIEW"
                                font.family: fontNMono.name
                                font.pixelSize: 10
                                font.letterSpacing: 0.8
                                color: "#FF5A60"
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Center: Currently Selected Wallpaper Title & Resolution
                    RowLayout {
                        spacing: 8
                        visible: root.currentSelectedObj !== null

                        Text {
                            text: root.currentSelectedObj ? root.currentSelectedObj.title.toUpperCase() : ""
                            font.family: fontNType.name
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.6
                            color: root.textPrimary
                            elide: Text.ElideMiddle
                            Layout.maximumWidth: 280
                        }

                        Rectangle {
                            visible: root.currentSelectedObj && root.currentSelectedObj.res !== ""
                            height: 20
                            width: resText.implicitWidth + 12
                            radius: 6
                            color: Qt.rgba(1, 1, 1, 0.07)

                            Text {
                                id: resText
                                anchors.centerIn: parent
                                text: root.currentSelectedObj ? root.currentSelectedObj.res : ""
                                font.family: fontNMono.name
                                font.pixelSize: 10
                                color: root.textMuted
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Right: Interactive Action Pills & Key Hints
                    RowLayout {
                        spacing: 6

                        // BG COLOR Picker Toggle (ASCII Mode)
                        Rectangle {
                            visible: root.activeMode === "ascii"
                            height: 26
                            width: bgColRow.implicitWidth + 16
                            radius: 13
                            color: root.colorPickerOpen
                                ? Qt.rgba(0.84, 0.10, 0.13, 0.25)
                                : (bgColMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08))
                            border.width: 1
                            border.color: root.colorPickerOpen ? root.nothingRed : Qt.rgba(1, 1, 1, 0.16)

                            RowLayout {
                                id: bgColRow
                                anchors.centerIn: parent
                                spacing: 6

                                Rectangle {
                                    width: 12
                                    height: 12
                                    radius: 4
                                    color: root.selectedAsciiBgColor
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.45)
                                }
                                Text {
                                    text: "BG " + root.selectedAsciiBgColor
                                    font.family: fontNMono.name
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: root.textPrimary
                                }
                            }

                            MouseArea {
                                id: bgColMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.colorPickerOpen = !root.colorPickerOpen
                            }
                        }

                        // [R] RANDOM Button
                        Rectangle {
                            height: 26
                            width: randRow.implicitWidth + 16
                            radius: 13
                            color: randMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.07)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.12)

                            RowLayout {
                                id: randRow
                                anchors.centerIn: parent
                                spacing: 5
                                Text {
                                    text: "[R]"
                                    font.family: fontNMono.name
                                    font.pixelSize: 10
                                    color: root.nothingRed
                                }
                                Text {
                                    text: "RANDOM"
                                    font.family: fontNMono.name
                                    font.pixelSize: 10
                                    color: root.textSecondary
                                }
                            }

                            MouseArea {
                                id: randMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.pickRandomPreview()
                            }
                        }

                        // [O] FOLDER Button
                        Rectangle {
                            height: 26
                            width: folderRow.implicitWidth + 16
                            radius: 13
                            color: folderMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.07)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.12)

                            RowLayout {
                                id: folderRow
                                anchors.centerIn: parent
                                spacing: 5
                                Text {
                                    text: "[O]"
                                    font.family: fontNMono.name
                                    font.pixelSize: 10
                                    color: root.textMuted
                                }
                                Text {
                                    text: "FOLDER"
                                    font.family: fontNMono.name
                                    font.pixelSize: 10
                                    color: root.textSecondary
                                }
                            }

                            MouseArea {
                                id: folderMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openWallpaperFolder()
                            }
                        }

                        // [↵] APPLY Primary Button (Nothing Red)
                        Rectangle {
                            height: 26
                            width: applyRow.implicitWidth + 18
                            radius: 13
                            color: applyMouse.containsMouse ? "#EA222A" : root.nothingRed

                            RowLayout {
                                id: applyRow
                                anchors.centerIn: parent
                                spacing: 5
                                Text {
                                    text: "[↵]"
                                    font.family: fontNMono.name
                                    font.pixelSize: 10
                                    color: "#FFFFFF"
                                }
                                Text {
                                    text: "APPLY"
                                    font.family: fontNMono.name
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: "#FFFFFF"
                                }
                            }

                            MouseArea {
                                id: applyMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.confirmSelection()
                            }
                        }

                        // [ESC] Close/Cancel Button
                        Rectangle {
                            height: 26
                            width: escRow.implicitWidth + 14
                            radius: 13
                            color: escMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.06)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.10)

                            RowLayout {
                                id: escRow
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    text: "ESC"
                                    font.family: fontNMono.name
                                    font.pixelSize: 10
                                    color: root.textMuted
                                }
                            }

                            MouseArea {
                                id: escMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.cancelAndClose()
                            }
                        }
                    }
                }

                // Hairline Separator
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                // =============================================================
                // Horizontal Wallpaper Filmstrip (ListView)
                // =============================================================
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // Empty State if no wallpapers found
                    Item {
                        visible: root.activeMode === "image" && (!root.wallpapers || root.wallpapers.length === 0)
                        anchors.fill: parent

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 16

                            Text {
                                text: "[!] NO WALLPAPERS FOUND IN FOLDER"
                                font.family: fontNMono.name
                                font.pixelSize: 12
                                font.letterSpacing: 1.0
                                color: root.textMuted
                            }

                            Rectangle {
                                height: 28
                                width: emptyBtnRow.implicitWidth + 20
                                radius: 14
                                color: emptyBtnMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.10)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.20)

                                RowLayout {
                                    id: emptyBtnRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text {
                                        text: "[O]"
                                        font.family: fontNMono.name
                                        font.pixelSize: 11
                                        color: root.nothingRed
                                    }
                                    Text {
                                        text: "OPEN WALLPAPERS FOLDER"
                                        font.family: fontNMono.name
                                        font.pixelSize: 11
                                        color: "#FFFFFF"
                                    }
                                }

                                MouseArea {
                                    id: emptyBtnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.openWallpaperFolder()
                                }
                            }
                        }
                    }

                    // Horizontal ASCII Presets Filmstrip
                    ListView {
                        id: asciiFilmstripList
                        visible: root.activeMode === "ascii"
                        anchors.fill: parent
                        orientation: ListView.Horizontal
                        spacing: 14
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        highlightMoveDuration: 220
                        model: root.asciiPresets

                        Behavior on contentX {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }

                        delegate: Item {
                            id: asciiSlot
                            width: 212
                            height: asciiFilmstripList.height

                            readonly property bool isSelected: (index === root.selectedAsciiIndex)
                            readonly property bool isOriginalActive: (root.originalAsciiEnabled && modelData.id === root.originalAsciiPreset)

                            Item {
                                width: 198
                                height: 112
                                anchors.centerIn: parent

                                scale: asciiSlot.isSelected ? 1.07 : (asciiCardMouse.containsMouse ? 1.02 : 0.95)
                                opacity: asciiSlot.isSelected ? 1.0 : (asciiCardMouse.containsMouse ? 0.88 : 0.62)

                                Behavior on scale { NumberAnimation { duration: 190; easing.type: Easing.OutBack } }
                                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                                RectangularGlow {
                                    visible: asciiSlot.isSelected
                                    anchors.fill: asciiCardBg
                                    glowRadius: 14
                                    spread: 0.2
                                    color: Qt.rgba(0.843, 0.098, 0.129, 0.55)
                                    cornerRadius: 18
                                }

                                Rectangle {
                                    id: asciiCardBg
                                    anchors.fill: parent
                                    radius: 15
                                    color: "#090A0D"
                                    border.width: asciiSlot.isSelected ? 2.5 : 1
                                    border.color: asciiSlot.isSelected
                                        ? root.nothingRed
                                        : (asciiCardMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.42) : Qt.rgba(1, 1, 1, 0.16))
                                    clip: true

                                    // Mini ASCII Art Pattern Preview inside Card
                                    Column {
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: -6
                                        spacing: 2

                                        Repeater {
                                            model: modelData.art
                                            delegate: Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: modelData
                                                font.family: fontNMono.name
                                                font.pixelSize: 8
                                                color: index === 2
                                                    ? (asciiSlot.isSelected ? root.nothingRed : "#FFFFFF")
                                                    : Qt.rgba(1, 1, 1, 0.48)
                                            }
                                        }
                                    }

                                    // Bottom Dark Gradient Scrim
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 40
                                        radius: 15
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: "transparent" }
                                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.90) }
                                        }
                                    }

                                    // Top-left Badge: [ ACTIVE ] or Tag
                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.topMargin: 8
                                        anchors.leftMargin: 8
                                        height: 18
                                        width: asciiTagText.implicitWidth + 12
                                        radius: 9
                                        color: asciiSlot.isOriginalActive ? root.nothingRed : Qt.rgba(1, 1, 1, 0.10)
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.22)

                                        Text {
                                            id: asciiTagText
                                            anchors.centerIn: parent
                                            text: asciiSlot.isOriginalActive ? "ACTIVE" : modelData.tag
                                            font.family: fontNdot57.name
                                            font.pixelSize: 8
                                            font.letterSpacing: 0.8
                                            color: "#FFFFFF"
                                        }
                                    }

                                    // Top-right Index Number (#01)
                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.topMargin: 8
                                        anchors.rightMargin: 8
                                        height: 18
                                        width: asciiIdxText.implicitWidth + 10
                                        radius: 9
                                        color: asciiSlot.isSelected ? root.nothingRed : Qt.rgba(0, 0, 0, 0.62)

                                        Text {
                                            id: asciiIdxText
                                            anchors.centerIn: parent
                                            text: "0" + (index + 1)
                                            font.family: fontNMono.name
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            color: "#FFFFFF"
                                        }
                                    }

                                    // Bottom Title Caption
                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        anchors.bottomMargin: 7
                                        text: modelData.title
                                        font.family: fontNMono.name
                                        font.pixelSize: 10
                                        color: asciiSlot.isSelected ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.82)
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: asciiCardMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (asciiSlot.isSelected) {
                                            root.confirmSelection();
                                        } else {
                                            root.selectAsciiIndex(index, true);
                                        }
                                    }
                                    onDoubleClicked: {
                                        root.selectAsciiIndex(index, false);
                                        root.confirmSelection();
                                    }
                                }
                            }
                        }
                    }

                    ListView {
                        id: filmstripList
                        visible: root.activeMode === "image" && root.wallpapers && root.wallpapers.length > 0
                        anchors.fill: parent
                        orientation: ListView.Horizontal
                        spacing: 14
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        highlightMoveDuration: 220

                        model: root.wallpapers

                        Behavior on contentX {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }

                        delegate: Item {
                            id: cardSlot
                            width: 212
                            height: filmstripList.height

                            readonly property bool isSelected: (index === root.selectedIndex)
                            readonly property bool isOriginalActive: (modelData.path === root.originalWallpaper)

                            Item {
                                id: cardVisual
                                width: 198
                                height: 112
                                anchors.centerIn: parent

                                scale: cardSlot.isSelected ? 1.07 : (cardMouse.containsMouse ? 1.02 : 0.95)
                                opacity: cardSlot.isSelected ? 1.0 : (cardMouse.containsMouse ? 0.88 : 0.54)

                                Behavior on scale {
                                    NumberAnimation { duration: 190; easing.type: Easing.OutBack }
                                }
                                Behavior on opacity {
                                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                                }

                                // Nothing Red Glow behind active selected card
                                RectangularGlow {
                                    visible: cardSlot.isSelected
                                    anchors.fill: thumbMaskContainer
                                    glowRadius: 14
                                    spread: 0.2
                                    color: Qt.rgba(0.843, 0.098, 0.129, 0.55)
                                    cornerRadius: 18
                                }

                                // Thumbnail Image Mask Container
                                Item {
                                    id: thumbMaskContainer
                                    anchors.fill: parent

                                    Rectangle {
                                        id: thumbMask
                                        anchors.fill: parent
                                        radius: 15
                                        visible: false
                                    }

                                    Image {
                                        id: thumbImg
                                        anchors.fill: parent
                                        source: modelData.thumb ? ("file://" + modelData.thumb) : ""
                                        sourceSize: Qt.size(384, 216)
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                        smooth: true
                                        visible: false
                                    }

                                    OpacityMask {
                                        anchors.fill: parent
                                        source: thumbImg
                                        maskSource: thumbMask
                                    }

                                    // Bottom Dark Gradient Scrim for Title Readability
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 44
                                        radius: 15
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: "transparent" }
                                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.82) }
                                        }
                                    }

                                    // Top-left Badge: [ ACTIVE ] for current desktop wallpaper
                                    Rectangle {
                                        visible: cardSlot.isOriginalActive
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.topMargin: 8
                                        anchors.leftMargin: 8
                                        height: 18
                                        width: activeBadgeText.implicitWidth + 12
                                        radius: 9
                                        color: Qt.rgba(0, 0, 0, 0.72)
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.35)

                                        Text {
                                            id: activeBadgeText
                                            anchors.centerIn: parent
                                            text: "ACTIVE"
                                            font.family: fontNdot57.name
                                            font.pixelSize: 9
                                            font.letterSpacing: 1.0
                                            color: "#FFFFFF"
                                        }
                                    }

                                    // Top-right Index Number (#01)
                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.topMargin: 8
                                        anchors.rightMargin: 8
                                        height: 18
                                        width: idxBadgeText.implicitWidth + 10
                                        radius: 9
                                        color: cardSlot.isSelected ? root.nothingRed : Qt.rgba(0, 0, 0, 0.62)

                                        Text {
                                            id: idxBadgeText
                                            anchors.centerIn: parent
                                            text: (index + 1) < 10 ? ("0" + (index + 1)) : ("" + (index + 1))
                                            font.family: fontNMono.name
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            color: "#FFFFFF"
                                        }
                                    }

                                    // Bottom Filename Caption
                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        anchors.bottomMargin: 7
                                        text: modelData.title
                                        font.family: fontNMono.name
                                        font.pixelSize: 10
                                        color: cardSlot.isSelected ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.80)
                                        elide: Text.ElideRight
                                    }

                                    // Selection Border Frame
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 15
                                        color: "transparent"
                                        border.width: cardSlot.isSelected ? 2.5 : 1
                                        border.color: cardSlot.isSelected
                                            ? root.nothingRed
                                            : (cardMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.42) : Qt.rgba(1, 1, 1, 0.14))
                                    }
                                }

                                MouseArea {
                                    id: cardMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (cardSlot.isSelected) {
                                            // Second click on already-previewed card applies & closes
                                            root.confirmSelection();
                                        } else {
                                            root.selectIndex(index, true);
                                        }
                                    }
                                    onDoubleClicked: {
                                        root.selectIndex(index, false);
                                        root.confirmSelection();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

