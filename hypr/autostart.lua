hl.on("hyprland.start", function ()
    -- Export variables to systemd
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")

    -- Restart portals so they catch the environment
    hl.exec_cmd("systemctl --user stop xdg-desktop-portal xdg-desktop-portal-hyprland")
    hl.exec_cmd("systemctl --user start xdg-desktop-portal-hyprland xdg-desktop-portal")

    -- Check if ASCII wallpaper mode is active
    local HOME = os.getenv("HOME")
    local ascii_enabled = false
    local af = io.open(HOME .. "/.cache/glyph-shell/ascii_state.json", "r")
    if af then
        local content = af:read("*all") or ""
        af:close()
        if content:match('"enabled"%s*:%s*true') then
            ascii_enabled = true
        end
    end

    -- Wallpaper daemon (awww) — skip at boot when ASCII mode is active to prevent image flash
    if not ascii_enabled then
        hl.exec_cmd("awww-daemon")
    end

    -- Load cursor
    hl.exec_cmd("hyprctl setcursor Bibata-Modern-Ice 24")

    -- Start polkit daemon
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")

    -- Stop swaync if active & launch glyph-shell (DesktopWidgetsApp) directly
    hl.exec_cmd("bash -c 'systemctl --user stop swaync.service 2>/dev/null || true; killall swaync 2>/dev/null || true'")
    hl.exec_cmd("qs -p ~/.config/quickshell/DesktopWidgetsApp")

    -- Load GTK settings
    hl.exec_cmd("~/.config/hypr/scripts/gtk.sh")

    -- Start hypridle
    hl.exec_cmd("hypridle")

    -- Load cliphist history (for Super + V Clipboard History)
    hl.exec_cmd("wl-paste --watch cliphist store")

    -- Start autostart cleanup
    hl.exec_cmd("~/.config/hypr/scripts/cleanup.sh")
end)
