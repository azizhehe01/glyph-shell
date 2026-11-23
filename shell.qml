import Quickshell
import Quickshell.Wayland
import QtQuick
import "widgets"
import "notifications"
import "notch"
import "sidebar"
import "launcher"
import "wallpaper"
import "clipboard"
import "emoji"
import "keybinds"
import "overview"
import "power"
import "lockscreen"

ShellRoot {
    DesktopWidgetsWindow {
        id: desktopWidgets
    }

    AsciiWallpaperWindow {
        id: asciiWallpaper
        rawCursorX: topNotch.cursorX
        rawCursorY: topNotch.cursorY
        hasOpenWindow: topNotch.hasWindow
    }

    NotificationPopupWindow {
        id: notifPopup
        wallpaperUrl: desktopWidgets.wallpaperUrl
    }

    NotchWindow {
        id: topNotch
    }

    SidebarWindow {
        id: musicSidebar
        notifServer: notifPopup
    }

    LauncherWindow {
        id: appLauncher
    }

    WallpaperWindow {
        id: wallpaperSelector
        desktopWidgetsRef: desktopWidgets
        asciiWallpaperRef: asciiWallpaper
    }

    ClipboardWindow {
        id: clipboardHistory
    }

    EmojiWindow {
        id: emojiPicker
    }

    KeybindsWindow {
        id: keybindsViewer
    }

    OverviewWindow {
        id: workspaceOverview
    }

    PowerWindow {
        id: powerMenu
    }

    LockscreenWindow {
        id: lockscreenWindow
        asciiWallpaperRef: asciiWallpaper
    }
}
