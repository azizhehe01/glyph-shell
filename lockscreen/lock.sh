#!/usr/bin/env bash
set -euo pipefail

LOCK_DIR="/home/azhehe/.config/quickshell/DesktopWidgetsApp/lockscreen"
SHELL_DIR="/home/azhehe/.config/quickshell/DesktopWidgetsApp"
CONF="$LOCK_DIR/hyprlock.conf"
WP_LINK="/tmp/nothing_lock_wallpaper"
ASCII_STATE="$HOME/.cache/glyph-shell/ascii_state.json"
ASCII_LOCK_IMG="/tmp/nothing_lock_ascii.png"
ASCII_CONF="/tmp/nothing_hyprlock_ascii.conf"

# Prevent duplicate hyprlock instances
if pgrep -u "$(id -u)" -x hyprlock >/dev/null 2>&1; then
    exit 0
fi

# Check if ASCII Live Wallpaper mode is active
if [[ -f "$ASCII_STATE" ]] && grep -q '"enabled":[[:space:]]*true' "$ASCII_STATE"; then
    # Request a fresh GPU frame snapshot from the running Quickshell ShaderEffect
    if command -v qs >/dev/null 2>&1; then
        qs ipc -p "$SHELL_DIR" call asciiwallpaper snapshot >/dev/null 2>&1 || true
        sleep 0.12
    fi

    # Fallback: render crisp ASCII lockscreen PNG via wallpaper.py if snapshot is missing
    if [[ ! -s "$ASCII_LOCK_IMG" ]]; then
        python3 "$SHELL_DIR/wallpaper/wallpaper.py" render-ascii-lock >/dev/null 2>&1 || true
    fi

    if [[ -f "$ASCII_LOCK_IMG" ]]; then
        ln -sf "$ASCII_LOCK_IMG" "$WP_LINK"
    fi

    # Generate ASCII-tuned hyprlock config (blur_passes = 0 so ASCII glyphs stay razor-sharp)
    sed -e 's/blur_passes = 4/blur_passes = 0/' \
        -e 's/brightness = 0.62/brightness = 0.90/' \
        "$CONF" > "$ASCII_CONF"

    exec hyprlock --config "$ASCII_CONF"
fi

# Otherwise: Resolve active photo wallpaper dynamically for Frosted Glass blur
WP_PATH=""
if [[ -f "$HOME/.cache/glyph-shell/current_wallpaper" ]]; then
    WP_PATH="$(tr -d '\r\n' < "$HOME/.cache/glyph-shell/current_wallpaper")"
elif [[ -f "$HOME/.cache/ml4w/hyprland-dotfiles/current_wallpaper" ]]; then
    WP_PATH="$(tr -d '\r\n' < "$HOME/.cache/ml4w/hyprland-dotfiles/current_wallpaper")"
fi

if [[ -z "$WP_PATH" || ! -f "$WP_PATH" ]]; then
    WP_PATH="$HOME/.config/quickshell/DesktopWidgetsApp/wallpapers/default.jpg"
fi
if [[ ! -f "$WP_PATH" ]]; then
    WP_PATH="$HOME/.config/ml4w/wallpapers/clay-banks-CtmO3PZaxmU-unsplash.jpg"
fi

if [[ -f "$WP_PATH" ]]; then
    ln -sf "$WP_PATH" "$WP_LINK"
fi

exec hyprlock --config "$CONF"
