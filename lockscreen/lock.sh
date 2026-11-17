#!/usr/bin/env bash
set -euo pipefail

SHELL_DIR="/home/azhehe/.config/quickshell/DesktopWidgetsApp"

# Primary: Native Quickshell Lockscreen (WlSessionLock + PamContext)
if command -v qs >/dev/null 2>&1; then
    if qs ipc -p "$SHELL_DIR" call lockscreen lock >/dev/null 2>&1; then
        exit 0
    fi
fi

# Emergency Fallback: hyprlock (only if Quickshell is not running)
if pgrep -u "$(id -u)" -x hyprlock >/dev/null 2>&1; then
    exit 0
fi
exec hyprlock --config "$SHELL_DIR/lockscreen/hyprlock.conf"
