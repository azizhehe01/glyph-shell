import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

// =============================================================================
// Nothing OS 3.0 / glyph-shell Native Quickshell Lockscreen
// Powered by WlSessionLock + Quickshell.Services.Pam (zero hyprlock needed).
// Features:
// - Clean center canvas (100% open for SILENT BLADE live GPU shader or frosted WP)
// - Bottom Dock: Analog + Dot-Matrix Clock (Ndot57) & Frosted Music Pill (MPRIS)
// - Opsi A: Auto-Show Passcode Capsule (hidden on idle; appears on keypress/click)
// =============================================================================
Scope {
    id: root

    property var asciiWallpaperRef: null
    property string activeBgColor: root.asciiWallpaperRef ? root.asciiWallpaperRef.currentBgColor : "#07080A"
    property bool asciiEnabled: root.asciiWallpaperRef ? root.asciiWallpaperRef.asciiEnabled : false
    property string blurredWallpaperUrl: ""

    property string passwordBuffer: ""
    property bool passwordVisible: false
    property bool authenticating: false
    property int failedAttempts: 0
    property string errorMessage: ""
    property string wifiText: "WIFI"

    FontLoader { id: fontNdot57; source: Qt.resolvedUrl("../assets/fonts/Ndot57-Regular.otf") }
    FontLoader { id: fontNType;  source: Qt.resolvedUrl("../assets/fonts/NType82-Regular.otf") }
    FontLoader { id: fontNMono;  source: Qt.resolvedUrl("../assets/fonts/LetteraMonoLL-Regular.otf") }

    SystemClock {
        id: lockClock
        precision: SystemClock.Seconds
    }

    // Active MPRIS Player (prioritizes dedicated music apps like Spotify over browser tabs)
    readonly property var activePlayer: {
        var list = Mpris.players.values;
        if (!list || list.length === 0) return null;

        function isMusicApp(p) {
            if (!p) return false;
            var id = ((p.identity || "") + " " + (p.dbusName || "")).toLowerCase();
            return id.indexOf("spotify") !== -1 || id.indexOf("ncspot") !== -1
                || id.indexOf("rhythmbox") !== -1 || id.indexOf("elisa") !== -1
                || id.indexOf("amberol") !== -1 || id.indexOf("lollypop") !== -1
                || id.indexOf("vlc") !== -1 || id.indexOf("mpv") !== -1;
        }

        // 1. Always prefer Spotify while Spotify is open (playing or paused)
        for (var s = 0; s < list.length; s++) {
            if (list[s] && (((list[s].identity || "") + " " + (list[s].dbusName || "")).toLowerCase().indexOf("spotify") !== -1) && list[s].trackTitle !== "") {
                return list[s];
            }
        }
        // 2. Playing dedicated music player
        for (var a = 0; a < list.length; a++) {
            if (isMusicApp(list[a]) && list[a].playbackState === MprisPlaybackState.Playing && list[a].trackTitle !== "") {
                return list[a];
            }
        }
        // 2. Playing browser/other media
        for (var b = 0; b < list.length; b++) {
            if (list[b] && list[b].playbackState === MprisPlaybackState.Playing && list[b].trackTitle !== "") {
                return list[b];
            }
        }
        // 3. Paused dedicated music player (Spotify, etc.)
        for (var c = 0; c < list.length; c++) {
            if (isMusicApp(list[c]) && list[c].trackTitle !== "") {
                return list[c];
            }
        }
        // 4. Any paused media
        for (var d = 0; d < list.length; d++) {
            if (list[d] && list[d].trackTitle !== "") {
                return list[d];
            }
        }
        return null;
    }
    readonly property bool hasMusic: root.activePlayer !== null && root.activePlayer.trackTitle !== ""

    // Track position ticker for smooth progress bar when playing
    property real trackPos: 0
    Timer {
        interval: 1000
        running: sessionLock.locked && root.hasMusic && root.activePlayer.playbackState === MprisPlaybackState.Playing
        repeat: true
        onTriggered: {
            if (root.activePlayer) {
                root.trackPos = root.activePlayer.position || 0;
            }
        }
    }

    Connections {
        target: root.activePlayer
        function onPositionChanged() {
            if (root.activePlayer) root.trackPos = root.activePlayer.position || 0;
        }
        function onTrackTitleChanged() {
            if (root.activePlayer) root.trackPos = root.activePlayer.position || 0;
        }
    }

    // Refresh current blurred image wallpaper & wifi label on lock
    Process {
        id: lockInfoProc
        command: ["python3", "-c", "
import glob, json, os, subprocess
wp = ''
frosted = sorted(glob.glob('/tmp/glyph_widget_frost_*.jpg'), key=os.path.getmtime, reverse=True)
if frosted:
    wp = frosted[0]
elif os.path.exists('/tmp/nothing_lock_wallpaper'):
    wp = os.path.realpath('/tmp/nothing_lock_wallpaper')
wifi = 'OFFLINE'
try:
    out = subprocess.check_output(['nmcli', '-t', '-f', 'ACTIVE,SSID', 'dev', 'wifi'], text=True, timeout=1)
    for line in out.splitlines():
        if line.startswith('yes:'):
            wifi = line.split(':', 1)[1].strip() or 'WIFI'
            break
except Exception:
    pass
print(json.dumps({'wp': wp, 'wifi': wifi}))
"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text.trim());
                    if (d.wp) root.blurredWallpaperUrl = "file://" + d.wp;
                    if (d.wifi) root.wifiText = d.wifi.toUpperCase();
                } catch (e) {}
            }
        }
    }

    // Auto-hide empty password capsule after 8 seconds of inactivity (Opsi A)
    Timer {
        id: idleHideTimer
        interval: 8000
        repeat: false
        onTriggered: {
            if (root.passwordBuffer === "" && !root.authenticating) {
                root.passwordVisible = false;
                root.errorMessage = "";
            }
        }
    }

    function revealPasswordBar(): void {
        root.passwordVisible = true;
        idleHideTimer.restart();
    }

    function submitPassword(): void {
        if (root.authenticating || root.passwordBuffer.length === 0) return;
        root.authenticating = true;
        root.errorMessage = "";
        idleHideTimer.stop();
        pamAuth.start();
    }

    function lock(): void {
        if (sessionLock.locked) return;
        root.passwordBuffer = "";
        root.passwordVisible = false;
        root.authenticating = false;
        root.failedAttempts = 0;
        root.errorMessage = "";
        if (root.activePlayer) {
            root.trackPos = root.activePlayer.position || 0;
        }
        lockInfoProc.running = false;
        lockInfoProc.running = true;
        sessionLock.locked = true;
    }

    signal wakeRequested()

    IpcHandler {
        target: "lockscreen"
        function lock(): void {
            root.lock();
        }
        function wake(): void {
            if (sessionLock.locked) {
                root.wakeRequested();
            }
        }
    }

    // Native Linux PAM Authenticator
    PamContext {
        id: pamAuth
        config: "hyprlock"
        onPamMessage: {
            if (this.responseRequired) {
                this.respond(root.passwordBuffer);
            }
        }
        onCompleted: result => {
            root.authenticating = false;
            if (result === PamResult.Success) {
                root.passwordBuffer = "";
                root.passwordVisible = false;
                root.failedAttempts = 0;
                root.errorMessage = "";
                sessionLock.locked = false;
            } else {
                root.passwordBuffer = "";
                root.failedAttempts += 1;
                root.errorMessage = "ACCESS DENIED · [" + root.failedAttempts + "]";
                root.passwordVisible = true;
                idleHideTimer.restart();
            }
        }
    }

    function formatTime(secs: real): string {
        var s = Math.max(0, Math.floor(secs));
        var m = Math.floor(s / 60);
        var rem = s % 60;
        return m + ":" + (rem < 10 ? "0" + rem : rem);
    }

    // Wayland ext-session-lock-v1 Surface Host
    WlSessionLock {
        id: sessionLock
        locked: false

        surface: Component {
            WlSessionLockSurface {
                id: lockSurface
                color: root.asciiEnabled ? root.activeBgColor : "#07080A"

                // Smooth GPU Shader Time Driver for live SILENT BLADE on Lockscreen
                property real lockShaderTime: 0.0
                NumberAnimation on lockShaderTime {
                    from: 0.0
                    to: 62831.853
                    duration: 62831853
                    loops: Animation.Infinite
                    running: sessionLock.locked && root.asciiEnabled
                }

                // 1A. Live GPU SILENT BLADE Background (when ASCII mode is active)
                ShaderEffect {
                    anchors.fill: parent
                    visible: root.asciiEnabled && root.asciiWallpaperRef && root.asciiWallpaperRef.shaderReady

                    property real timeSec: lockSurface.lockShaderTime
                    property real widthPx: width
                    property real heightPx: height
                    property real cursorX: width * 0.54
                    property real cursorY: height * 0.48
                    property real cursorEnergy: 0.25
                    property int presetId: root.asciiWallpaperRef ? root.asciiWallpaperRef.currentPresetId : 6
                    property color bgColor: root.activeBgColor
                    property variant fontAtlas: lockAtlasFallback
                    property variant wallpaperTex: lockAtlasFallback

                    fragmentShader: Qt.resolvedUrl("../wallpaper/ascii_wallpaper_v6.frag.qsb")
                }

                Image {
                    id: lockAtlasFallback
                    source: root.asciiWallpaperRef ? root.asciiWallpaperRef.atlasSource : ""
                    visible: false
                }

                // 1B. Blurred Desktop Image Background (when Image mode is active)
                Image {
                    anchors.fill: parent
                    visible: !root.asciiEnabled && root.blurredWallpaperUrl !== ""
                    source: root.blurredWallpaperUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                Rectangle {
                    anchors.fill: parent
                    visible: !root.asciiEnabled
                    color: Qt.rgba(0.03, 0.04, 0.05, 0.42)
                }

                // Click anywhere on background to reveal Password Pill (Opsi A)
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.revealPasswordBar();
                        keyInputScope.forceActiveFocus();
                    }
                }

                // Global Keyboard Handler for Lockscreen
                Item {
                    id: keyInputScope
                    anchors.fill: parent
                    focus: true
                    Component.onCompleted: forceActiveFocus()

                    Timer {
                        id: wakeFocusTimer
                        interval: 200
                        repeat: false
                        onTriggered: keyInputScope.forceActiveFocus()
                    }

                    Connections {
                        target: root
                        function onWakeRequested() {
                            keyInputScope.forceActiveFocus();
                            wakeFocusTimer.restart();
                        }
                    }

                    Connections {
                        target: lockSurface
                        function onActiveChanged() {
                            if (lockSurface.active) {
                                keyInputScope.forceActiveFocus();
                                wakeFocusTimer.restart();
                            }
                        }
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            root.passwordBuffer = "";
                            root.errorMessage = "";
                            root.passwordVisible = false;
                            idleHideTimer.stop();
                            event.accepted = true;
                            return;
                        }
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (!root.passwordVisible) {
                                root.revealPasswordBar();
                            } else if (root.passwordBuffer.length > 0) {
                                root.submitPassword();
                            }
                            event.accepted = true;
                            return;
                        }
                        if (event.key === Qt.Key_Backspace) {
                            if (root.passwordBuffer.length > 0) {
                                root.passwordBuffer = root.passwordBuffer.slice(0, -1);
                                root.revealPasswordBar();
                            }
                            event.accepted = true;
                            return;
                        }
                        if (event.text && event.text.length > 0 && !(event.modifiers & Qt.ControlModifier) && !(event.modifiers & Qt.AltModifier) && !(event.modifiers & Qt.MetaModifier)) {
                            if (!root.authenticating) {
                                root.passwordBuffer += event.text;
                                root.errorMessage = "";
                                root.revealPasswordBar();
                            }
                            event.accepted = true;
                        }
                    }
                }

                // Subtle Top Status Strip (very minimal, non-intrusive)
                RowLayout {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.topMargin: 24
                    anchors.leftMargin: 36
                    anchors.rightMargin: 36

                    Text {
                        text: "[:::] " + root.wifiText
                        font.family: fontNMono.name
                        font.pixelSize: 10
                        font.letterSpacing: 1.0
                        color: Qt.rgba(1, 1, 1, 0.48)
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: {
                            var dev = UPower.displayDevice;
                            var pct = dev ? Math.round(dev.percentage * 100) : 100;
                            var chg = (dev && dev.state === UPowerDeviceState.Charging) ? "⚡ " : "";
                            return chg + "BAT " + pct + "%";
                        }
                        font.family: fontNMono.name
                        font.pixelSize: 10
                        font.letterSpacing: 1.0
                        color: Qt.rgba(1, 1, 1, 0.48)
                    }
                }

                // =============================================================
                // OPSI A: Clean Borderless Auto-Show Passcode Dots (Zero Capsule)
                // =============================================================
                Item {
                    id: passcodePill
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: bottomDock.top
                    anchors.bottomMargin: 18
                    width: 280
                    height: 28

                    visible: opacity > 0.01
                    opacity: root.passwordVisible ? 1.0 : 0.0
                    transform: Translate {
                        y: root.passwordVisible ? 0 : 8
                        Behavior on y { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    }
                    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }

                    // Fixed-model Repeater so existing dots NEVER recreate or blink when typing!
                    Row {
                        id: dotsRow
                        visible: !root.authenticating && root.errorMessage === "" && root.passwordBuffer.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        spacing: 9

                        Repeater {
                            model: 18

                            Rectangle {
                                readonly property bool activeDot: index < root.passwordBuffer.length
                                width: 8
                                height: 8
                                radius: 4
                                color: "#FFFFFF"
                                opacity: activeDot ? 1.0 : 0.0
                                scale: activeDot ? 1.0 : 0.35

                                Behavior on opacity { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                            }
                        }
                    }

                    // Placeholder / Status / Error Label
                    Text {
                        visible: root.authenticating || root.errorMessage !== "" || root.passwordBuffer.length === 0
                        anchors.centerIn: parent
                        text: {
                            if (root.authenticating) return "VERIFYING...";
                            if (root.errorMessage !== "") return root.errorMessage;
                            return "ENTER PASSCODE";
                        }
                        font.family: fontNMono.name
                        font.pixelSize: 10
                        font.letterSpacing: 1.6
                        color: root.errorMessage !== ""
                            ? "#FF454E"
                            : Qt.rgba(1, 1, 1, 0.52)
                    }
                }

                // =============================================================
                // BOTTOM WIDGET DOCK (Clock Widget + Optional Music Pill)
                // Keeps the center 100% clean for SILENT BLADE!
                // =============================================================
                RowLayout {
                    id: bottomDock
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 32
                    spacing: 16

                    // 1. CLOCK WIDGET (Matches Image 2: Analog Dial + Orange/White Dot-Matrix Time)
                    Rectangle {
                        id: clockCard
                        Layout.preferredWidth: 336
                        Layout.preferredHeight: 118
                        Layout.minimumHeight: 118
                        Layout.maximumHeight: 118
                        Layout.alignment: Qt.AlignVCenter
                        radius: 26
                        color: "#000000"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.12)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 18
                            anchors.rightMargin: 22
                            spacing: 18

                            // Left: Live Real-Time Rotating Analog Clock
                            Rectangle {
                                id: analogDial
                                width: 82
                                height: 82
                                radius: 41
                                color: "#E6E6E6"

                                readonly property real hoursVal: lockClock.date ? (lockClock.date.getHours() % 12) : 0
                                readonly property real minsVal: lockClock.date ? lockClock.date.getMinutes() : 0
                                readonly property real secsVal: lockClock.date ? lockClock.date.getSeconds() : 0

                                // 4 Cardinal Dots (12, 3, 6, 9)
                                Rectangle { width: 4; height: 4; radius: 2; color: "#7A7A7A"; anchors.top: parent.top; anchors.topMargin: 7; anchors.horizontalCenter: parent.horizontalCenter }
                                Rectangle { width: 4; height: 4; radius: 2; color: "#7A7A7A"; anchors.bottom: parent.bottom; anchors.bottomMargin: 7; anchors.horizontalCenter: parent.horizontalCenter }
                                Rectangle { width: 4; height: 4; radius: 2; color: "#7A7A7A"; anchors.left: parent.left; anchors.leftMargin: 7; anchors.verticalCenter: parent.verticalCenter }
                                Rectangle { width: 4; height: 4; radius: 2; color: "#7A7A7A"; anchors.right: parent.right; anchors.rightMargin: 7; anchors.verticalCenter: parent.verticalCenter }

                                // Hour Hand (Dark Charcoal)
                                Item {
                                    anchors.centerIn: parent
                                    width: 4
                                    height: 4
                                    rotation: (analogDial.hoursVal * 30.0) + (analogDial.minsVal * 0.5)
                                    Behavior on rotation { RotationAnimation { duration: 300; direction: RotationAnimation.Shortest } }

                                    Rectangle {
                                        width: 4
                                        height: 22
                                        radius: 2
                                        color: "#222428"
                                        anchors.bottom: parent.verticalCenter
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                }

                                // Minute Hand (Vibrant Nothing Orange-Red)
                                Item {
                                    anchors.centerIn: parent
                                    width: 3
                                    height: 3
                                    rotation: (analogDial.minsVal * 6.0) + (analogDial.secsVal * 0.1)
                                    Behavior on rotation { RotationAnimation { duration: 250; direction: RotationAnimation.Shortest } }

                                    Rectangle {
                                        width: 3
                                        height: 30
                                        radius: 1.5
                                        color: "#FF4D2A"
                                        anchors.bottom: parent.verticalCenter
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                }

                                // Second Hand (Thin Crisp Sweeping Needle)
                                Item {
                                    anchors.centerIn: parent
                                    width: 1.5
                                    height: 1.5
                                    rotation: analogDial.secsVal * 6.0

                                    Rectangle {
                                        width: 1.5
                                        height: 33
                                        radius: 0.75
                                        color: "#D71921"
                                        anchors.bottom: parent.verticalCenter
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                }

                                // Center Pivot Dot
                                Rectangle {
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: "#181818"
                                    anchors.centerIn: parent
                                }
                            }

                            // Right: Two-Tone Dot-Matrix Digital Time + Date
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                RowLayout {
                                    spacing: 0
                                    Text {
                                        text: lockClock.date ? Qt.formatDateTime(lockClock.date, "HH:") : "00:"
                                        font.family: fontNdot57.name
                                        font.pixelSize: 42
                                        color: "#FF4D2A"
                                    }
                                    Text {
                                        text: lockClock.date ? Qt.formatDateTime(lockClock.date, "mm") : "00"
                                        font.family: fontNdot57.name
                                        font.pixelSize: 42
                                        color: "#FFFFFF"
                                    }
                                }

                                Text {
                                    text: lockClock.date
                                        ? (Qt.formatDateTime(lockClock.date, "dd MMM yyyy").toUpperCase() + "   |   " + Qt.formatDateTime(lockClock.date, "ddd").toUpperCase())
                                        : "01 JAN 2026   |   MON"
                                    font.family: fontNMono.name
                                    font.pixelSize: 10
                                    font.letterSpacing: 1.0
                                    color: Qt.rgba(1, 1, 1, 0.58)
                                }
                            }
                        }
                    }

                    // 2. MUSIC PLAYER CARD (Exact same height/radius/color as Clock Card)
                    Rectangle {
                        id: musicPill
                        visible: root.hasMusic
                        Layout.preferredWidth: 404
                        Layout.preferredHeight: 118
                        Layout.minimumHeight: 118
                        Layout.maximumHeight: 118
                        Layout.alignment: Qt.AlignVCenter
                        radius: 26
                        color: "#000000"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.12)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 18
                            anchors.rightMargin: 20
                            spacing: 16

                            // Rounded Album Art (true rounded mask matching card curvature)
                            Item {
                                width: 82
                                height: 82

                                Image {
                                    id: lockAlbumArt
                                    anchors.fill: parent
                                    source: (root.activePlayer && root.activePlayer.trackArtUrl)
                                        ? root.activePlayer.trackArtUrl
                                        : Qt.resolvedUrl("../assets/album.jpg")
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    visible: false
                                }

                                Rectangle {
                                    id: lockAlbumMask
                                    anchors.fill: parent
                                    radius: 14
                                    visible: false
                                }

                                OpacityMask {
                                    anchors.fill: parent
                                    source: lockAlbumArt
                                    maskSource: lockAlbumMask
                                }
                            }

                            // Center: Title + Artist + Progress Bar
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                Text {
                                    Layout.fillWidth: true
                                    text: root.activePlayer ? (root.activePlayer.trackTitle || "Unknown Track") : ""
                                    font.family: fontNType.name
                                    font.pixelSize: 14
                                    font.bold: true
                                    color: "#FFFFFF"
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.activePlayer ? (root.activePlayer.trackArtist || "Unknown Artist") : ""
                                    font.family: fontNType.name
                                    font.pixelSize: 11
                                    color: Qt.rgba(1, 1, 1, 0.65)
                                    elide: Text.ElideRight
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 4
                                    spacing: 6

                                    Text {
                                        text: root.formatTime(root.trackPos)
                                        font.family: fontNMono.name
                                        font.pixelSize: 9
                                        color: Qt.rgba(1, 1, 1, 0.55)
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 3
                                        radius: 1.5
                                        color: Qt.rgba(1, 1, 1, 0.22)

                                        Rectangle {
                                            height: parent.height
                                            radius: 1.5
                                            color: "#FFFFFF"
                                            width: {
                                                var len = (root.activePlayer && root.activePlayer.length > 0) ? root.activePlayer.length : 1;
                                                return Math.max(0, Math.min(parent.width, (root.trackPos / len) * parent.width));
                                            }
                                        }
                                    }

                                    Text {
                                        text: root.formatTime(root.activePlayer ? (root.activePlayer.length || 0) : 0)
                                        font.family: fontNMono.name
                                        font.pixelSize: 9
                                        color: Qt.rgba(1, 1, 1, 0.55)
                                    }
                                }
                            }

                            // Right: 3 Circular Controls (<  ▶  >)
                            RowLayout {
                                spacing: 6

                                Rectangle {
                                    width: 28; height: 28; radius: 14
                                    color: prevMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.16)
                                    Text { anchors.centerIn: parent; text: "‹"; font.pixelSize: 15; color: "#FFFFFF" }
                                    MouseArea {
                                        id: prevMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (root.activePlayer) root.activePlayer.previous()
                                    }
                                }

                                Rectangle {
                                    width: 30; height: 30; radius: 15
                                    color: playMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.34) : Qt.rgba(1, 1, 1, 0.22)
                                    Text {
                                        anchors.centerIn: parent
                                        text: (root.activePlayer && root.activePlayer.playbackState === MprisPlaybackState.Playing) ? "⏸" : "▶"
                                        font.pixelSize: 11
                                        color: "#FFFFFF"
                                    }
                                    MouseArea {
                                        id: playMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (root.activePlayer) root.activePlayer.togglePlaying()
                                    }
                                }

                                Rectangle {
                                    width: 28; height: 28; radius: 14
                                    color: nextMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.16)
                                    Text { anchors.centerIn: parent; text: "›"; font.pixelSize: 15; color: "#FFFFFF" }
                                    MouseArea {
                                        id: nextMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (root.activePlayer) root.activePlayer.next()
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
