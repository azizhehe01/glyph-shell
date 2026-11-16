#!/usr/bin/env python3
"""
glyph-shell Native Wallpaper Engine & Manager
Replaces ml4w-wallpaper-app and ml4w-wallpaper with a standalone, fast,
Nothing OS 3.0 / glyph-shell native implementation.

Features:
- Dedicated wallpaper directory: ~/.config/quickshell/DesktopWidgetsApp/wallpapers
- Automatic one-time migration from ~/.config/ml4w/wallpapers if needed
- Fast 16:9 thumbnail caching in ~/.cache/glyph-shell/thumbs/
- Instant 60fps Live Preview via awww / swww / hyprpaper
- Full ecosystem sync on apply (glyph-shell frosted glass, hyprlock, matugen)
"""

import glob
import hashlib
import json
import os
import random
import re
import shutil
import subprocess
import sys
from PIL import Image

SHELL_DIR = os.path.expanduser("~/.config/quickshell/DesktopWidgetsApp")
PRIMARY_WP_DIR = os.path.join(SHELL_DIR, "wallpapers")
USER_PICTURES_WP_DIR = os.path.expanduser("~/Pictures/Wallpapers")
LEGACY_ML4W_WP_DIR = os.path.expanduser("~/.config/ml4w/wallpapers")

GLYPH_CACHE_DIR = os.path.expanduser("~/.cache/glyph-shell")
THUMBS_DIR = os.path.join(GLYPH_CACHE_DIR, "thumbs")
GLYPH_CURRENT_WP = os.path.join(GLYPH_CACHE_DIR, "current_wallpaper")
ASCII_STATE_FILE = os.path.join(GLYPH_CACHE_DIR, "ascii_state.json")

# Legacy compatibility paths so other tools/configs never break
ML4W_CACHE_DIR = os.path.expanduser("~/.cache/ml4w/hyprland-dotfiles")
ML4W_CURRENT_WP = os.path.join(ML4W_CACHE_DIR, "current_wallpaper")
ML4W_BLURRED_WP = os.path.join(ML4W_CACHE_DIR, "blurred_wallpaper.png")
LOCK_SYMLINK = "/tmp/nothing_lock_wallpaper"

VALID_EXTS = {".jpg", ".jpeg", ".png", ".webp"}


def ensure_dirs_and_migrate():
    os.makedirs(PRIMARY_WP_DIR, exist_ok=True)
    os.makedirs(THUMBS_DIR, exist_ok=True)
    os.makedirs(ML4W_CACHE_DIR, exist_ok=True)

    # Auto-migrate wallpapers from ~/.config/ml4w/wallpapers if PRIMARY_WP_DIR is empty
    existing = [
        f for f in os.listdir(PRIMARY_WP_DIR)
        if os.path.splitext(f)[1].lower() in VALID_EXTS
    ]
    if not existing and os.path.isdir(LEGACY_ML4W_WP_DIR):
        try:
            for fname in os.listdir(LEGACY_ML4W_WP_DIR):
                ext = os.path.splitext(fname)[1].lower()
                if ext in VALID_EXTS:
                    src = os.path.join(LEGACY_ML4W_WP_DIR, fname)
                    dst = os.path.join(PRIMARY_WP_DIR, fname)
                    if os.path.isfile(src) and not os.path.exists(dst):
                        shutil.copy2(src, dst)
        except Exception:
            pass


def get_current_wallpaper():
    for cache_f in (GLYPH_CURRENT_WP, ML4W_CURRENT_WP):
        if os.path.exists(cache_f):
            try:
                with open(cache_f, "r") as f:
                    p = f.read().strip()
                if p and os.path.exists(p):
                    # If it points to legacy folder and exists in primary folder, prefer primary
                    bname = os.path.basename(p)
                    primary_cand = os.path.join(PRIMARY_WP_DIR, bname)
                    if os.path.exists(primary_cand):
                        return primary_cand
                    return p
            except Exception:
                pass

    for daemon_cmd in ("awww", "swww"):
        if shutil.which(daemon_cmd):
            try:
                out = subprocess.check_output(
                    [daemon_cmd, "query"], stderr=subprocess.DEVNULL, timeout=1
                ).decode("utf-8", errors="ignore")
                m = re.search(r"image:\s*(.+)$", out, flags=re.MULTILINE)
                if m:
                    p = m.group(1).strip()
                    if p and os.path.exists(p):
                        return p
            except Exception:
                pass
    return ""


def get_thumb_and_meta(img_path):
    try:
        st = os.stat(img_path)
        sig = f"{img_path}:{int(st.st_mtime)}:{st.st_size}:v1"
        h = hashlib.md5(sig.encode("utf-8")).hexdigest()[:12]
        thumb_path = os.path.join(THUMBS_DIR, f"{h}.jpg")
        meta_path = os.path.join(THUMBS_DIR, f"{h}.json")

        if os.path.exists(thumb_path) and os.path.exists(meta_path):
            try:
                with open(meta_path, "r") as mf:
                    meta = json.load(mf)
                return thumb_path, meta.get("res", "")
            except Exception:
                pass

        with Image.open(img_path) as im:
            w, h_px = im.size
            res_str = f"{w}×{h_px}"
            im_rgb = im.convert("RGB")
            # Center crop to 16:9 (384x216) for crisp, ultra-lightweight carousel cards
            target_w, target_h = 384, 216
            src_ratio = w / max(1, h_px)
            target_ratio = target_w / target_h
            if src_ratio > target_ratio:
                new_w = int(h_px * target_ratio)
                left = (w - new_w) // 2
                im_crop = im_rgb.crop((left, 0, left + new_w, h_px))
            else:
                new_h = int(w / target_ratio)
                top = (h_px - new_h) // 2
                im_crop = im_rgb.crop((0, top, w, top + new_h))

            im_thumb = im_crop.resize((target_w, target_h), Image.Resampling.LANCZOS)
            im_thumb.save(thumb_path, "JPEG", quality=86, optimize=True)

            with open(meta_path, "w") as mf:
                json.dump({"res": res_str}, mf)

            return thumb_path, res_str
    except Exception:
        return img_path, ""


def collect_wallpapers():
    ensure_dirs_and_migrate()
    current_wp = get_current_wallpaper()
    current_base = os.path.basename(current_wp) if current_wp else ""

    dirs_to_scan = [PRIMARY_WP_DIR]
    if os.path.isdir(USER_PICTURES_WP_DIR) and os.path.abspath(USER_PICTURES_WP_DIR) != os.path.abspath(PRIMARY_WP_DIR):
        dirs_to_scan.append(USER_PICTURES_WP_DIR)

    seen_names = set()
    items = []

    for d in dirs_to_scan:
        if not os.path.isdir(d):
            continue
        for fname in sorted(os.listdir(d), key=lambda s: s.lower()):
            ext = os.path.splitext(fname)[1].lower()
            if ext not in VALID_EXTS:
                continue
            if fname.lower() in seen_names:
                continue
            full_path = os.path.join(d, fname)
            if not os.path.isfile(full_path):
                continue

            seen_names.add(fname.lower())
            thumb_path, res_str = get_thumb_and_meta(full_path)
            raw_title = os.path.splitext(fname)[0]
            clean_title = re.sub(r"[-_]+", " ", raw_title).strip()

            is_active = (
                os.path.abspath(full_path) == os.path.abspath(current_wp)
                if current_wp
                else False
            ) or (fname == current_base and current_base != "")

            items.append({
                "name": fname,
                "title": clean_title,
                "path": full_path,
                "thumb": thumb_path,
                "res": res_str,
                "active": is_active,
            })

    return {
        "current": current_wp,
        "folder": PRIMARY_WP_DIR,
        "count": len(items),
        "wallpapers": items,
        "ascii": get_ascii_state(),
    }


def get_ascii_state():
    ensure_dirs_and_migrate()
    gpu_info = ensure_gpu_assets()
    default_state = {
        "enabled": False,
        "preset": "topo-wave",
        "wallpaper": gpu_info.get("wallpaper", ""),
        "atlas": gpu_info.get("atlas", ""),
        "qsb": gpu_info.get("qsb", ""),
    }
    if os.path.exists(ASCII_STATE_FILE):
        try:
            with open(ASCII_STATE_FILE, "r") as f:
                data = json.load(f)
            return {
                "enabled": bool(data.get("enabled", False)),
                "preset": str(data.get("preset", "topo-wave")),
                "wallpaper": gpu_info.get("wallpaper", ""),
                "atlas": gpu_info.get("atlas", ""),
                "qsb": gpu_info.get("qsb", ""),
            }
        except Exception:
            pass
    return default_state


def set_ascii_state(enabled: bool, preset: str = "topo-wave"):
    ensure_dirs_and_migrate()
    state = {"enabled": bool(enabled), "preset": str(preset or "topo-wave")}
    try:
        with open(ASCII_STATE_FILE, "w") as f:
            json.dump(state, f)
    except Exception:
        pass
    if enabled:
        render_ascii_lock_wallpaper(state["preset"])
    return state


def ensure_gpu_assets():
    """Generates ascii_font_atlas.png and compiles ascii_wallpaper.frag.qsb if needed."""
    wp_dir = os.path.join(SHELL_DIR, "wallpaper")
    atlas_path = os.path.join(wp_dir, "ascii_font_atlas.png")
    frag_path = os.path.join(wp_dir, "ascii_wallpaper.frag")
    qsb_path = os.path.join(wp_dir, "ascii_wallpaper_v2.frag.qsb")
    font_path = os.path.join(SHELL_DIR, "assets", "fonts", "LetteraMonoLL-Regular.otf")

    # Ensure lock.sh is always executable
    lock_sh = os.path.join(SHELL_DIR, "lockscreen", "lock.sh")
    if os.path.isfile(lock_sh):
        try:
            os.chmod(lock_sh, 0o755)
        except Exception:
            pass

    # 1. Generate 16-slot 1024x64 glyph atlas PNG from LetteraMonoLL-Regular.otf
    if not os.path.exists(atlas_path):
        try:
            from PIL import ImageDraw, ImageFont
            chars = [" ", ".", ":", "-", "=", "+", "*", "#", "%", "@", "0", "1", "o", "O", "~", "$"]
            cell_size = 64
            img = Image.new("RGBA", (cell_size * len(chars), cell_size), (0, 0, 0, 255))
            draw = ImageDraw.Draw(img)
            try:
                fnt = ImageFont.truetype(font_path, 46)
            except Exception:
                fnt = ImageFont.load_default()
            for i, ch in enumerate(chars):
                if ch == " ":
                    continue
                cx = i * cell_size + cell_size * 0.5
                cy = cell_size * 0.5
                draw.text((cx, cy), ch, fill=(255, 255, 255, 255), font=fnt, anchor="mm", stroke_width=1, stroke_fill=(255, 255, 255, 255))
            img.save(atlas_path, "PNG")
        except Exception:
            pass

    # 2. Compile GLSL 440 fragment shader to Qt6 .qsb if needed
    if os.path.exists(frag_path):
        need_compile = not os.path.exists(qsb_path)
        if not need_compile:
            try:
                need_compile = os.path.getmtime(frag_path) > os.path.getmtime(qsb_path)
            except Exception:
                pass
        if need_compile:
            qsb_bin = shutil.which("qsb") or "/usr/lib64/qt6/bin/qsb"
            if not os.path.isfile(qsb_bin):
                qsb_bin = "/usr/lib/qt6/bin/qsb"
            if os.path.isfile(qsb_bin):
                try:
                    subprocess.run(
                        [qsb_bin, "--qt6", "-o", qsb_path, frag_path],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        timeout=8,
                    )
                except Exception:
                    pass

    wp = get_current_wallpaper()
    if not wp or not os.path.isfile(wp):
        info = collect_wallpapers()
        wps = info.get("wallpapers", [])
        if wps:
            wp = wps[0]["path"]
    return {"atlas": atlas_path, "qsb": qsb_path, "wallpaper": wp or ""}


def render_ascii_lock_wallpaper(preset: str = None):
    """Renders a crisp 1920x1080 ASCII wallpaper PNG to /tmp/nothing_lock_ascii.png for hyprlock."""
    import math
    from PIL import ImageDraw, ImageFont

    if not preset:
        preset = get_ascii_state().get("preset", "topo-wave")

    out_path = "/tmp/nothing_lock_ascii.png"
    font_path = os.path.join(SHELL_DIR, "assets", "fonts", "LetteraMonoLL-Regular.otf")
    w, h = 1920, 1080
    cols, rows = 64, 36
    cell_w = w / cols
    cell_h = h / rows

    try:
        img = Image.new("RGB", (w, h), (7, 8, 10))
        draw = ImageDraw.Draw(img)
        try:
            fnt = ImageFont.truetype(font_path, int(cell_h * 0.66))
        except Exception:
            fnt = ImageFont.load_default()

        dim_col = (95, 102, 114)
        bright_col = (232, 236, 242)
        red_col = (215, 25, 33)
        t = 2.4

        if preset == "ascii-torus":
            ramp = ".,-~:;=!*#$@"
            cx_col, cy_row = int(cols * 0.56), int(rows * 0.50)
            A, B = 1.15, 0.75
            cosA, sinA = math.cos(A), math.sin(A)
            cosB, sinB = math.cos(B), math.sin(B)
            zbuf = [0.0] * (cols * rows)
            out_ch = [""] * (cols * rows)
            out_lum = [0] * (cols * rows)

            theta = 0.0
            while theta < 6.283:
                cost, sint = math.cos(theta), math.sin(theta)
                phi = 0.0
                while phi < 6.283:
                    cosp, sinp = math.cos(phi), math.sin(phi)
                    circle_x = 2.0 + 1.05 * cost
                    circle_y = 1.05 * sint
                    x3 = circle_x * (cosB * cosp + sinA * sinB * sinp) - circle_y * cosA * sinB
                    y3 = circle_x * (sinB * cosp - sinA * cosB * sinp) + circle_y * cosA * cosB
                    z3 = 4.8 + cosA * circle_x * sinp + circle_y * sinA
                    ooz = 1.0 / z3
                    xp = int(cx_col + 26.0 * ooz * x3)
                    yp = int(cy_row - 14.5 * ooz * y3)
                    if 0 <= xp < cols and 0 <= yp < rows:
                        L = cosp * cost * sinB - cosA * cost * sinp - sinA * sint + cosB * (cosA * sint - cost * sinA * sinp)
                        b_idx = xp + yp * cols
                        if ooz > zbuf[b_idx]:
                            zbuf[b_idx] = ooz
                            lum_idx = max(0, min(11, int((L + 1.4) * 4.5)))
                            out_ch[b_idx] = ramp[lum_idx]
                            out_lum[b_idx] = lum_idx
                    phi += 0.045
                theta += 0.11

            for r in range(rows):
                py = (r + 0.5) * cell_h
                for c in range(cols):
                    px = (c + 0.5) * cell_w
                    m_idx = c + r * cols
                    ch = out_ch[m_idx]
                    if not ch:
                        if r % 2 == 0 and c % 2 == 0:
                            draw.text((px, py), ".", fill=(58, 64, 72), font=fnt, anchor="mm")
                        continue
                    lv = out_lum[m_idx]
                    col = red_col if lv >= 10 else (bright_col if lv >= 5 else dim_col)
                    draw.text((px, py), ch, fill=col, font=fnt, anchor="mm")

        elif preset == "glyph-vortex":
            ramp = "  .:oO0*#@"
            vx, vy = w * 0.56, h * 0.50
            for r in range(rows):
                py = (r + 0.5) * cell_h
                for c in range(cols):
                    px = (c + 0.5) * cell_w
                    dx, dy = px - vx, py - vy
                    rad = math.hypot(dx, dy)
                    ang = math.atan2(dy, dx)
                    spiral = math.sin(ang * 4.0 - rad * 0.018 + t * 2.0)
                    rings = math.cos(rad * 0.032 - t * 2.6)
                    val = max(0.0, min(0.999, (spiral * 0.55 + rings * 0.45 + 1.0) * 0.5))
                    idx = int(val * len(ramp))
                    if idx <= 1:
                        continue
                    col = red_col if abs(rad - 210.0) < 20.0 else (bright_col if idx >= len(ramp) - 2 else dim_col)
                    draw.text((px, py), ramp[idx], fill=col, font=fnt, anchor="mm")

        elif preset == "cyber-rain":
            chars = "0123456789ABCDEF:+*#<>="
            for c in range(cols):
                px = (c + 0.5) * cell_w
                head = (c * 7 + 11) % rows
                length = 8 + (c * 3) % 9
                is_red = (c % 7 == 0)
                for k in range(length):
                    r = (head - k) % rows
                    py = (r + 0.5) * cell_h
                    ch = chars[(c * 31 + r * 17) % len(chars)]
                    col = red_col if (k == 0 and is_red) else (bright_col if k <= 1 else dim_col)
                    draw.text((px, py), ch, fill=col, font=fnt, anchor="mm")

        elif preset == "halftone-pulse":
            ramp = "  .:oO0@#"
            s1x, s1y = w * 0.62, h * 0.46
            s2x, s2y = w * 0.42, h * 0.56
            for r in range(rows):
                py = (r + 0.5) * cell_h
                for c in range(cols):
                    px = (c + 0.5) * cell_w
                    d1 = math.hypot(px - s1x, py - s1y)
                    d2 = math.hypot(px - s2x, py - s2y)
                    moire = (math.sin(d1 * 0.035) + math.sin(d2 * 0.042) + 2.0) * 0.25
                    idx = max(0, min(len(ramp) - 1, int(moire * len(ramp))))
                    if idx <= 1:
                        continue
                    col = red_col if (d2 < 210 and idx >= len(ramp) - 2) else (bright_col if idx >= len(ramp) - 3 else dim_col)
                    draw.text((px, py), ramp[idx], fill=col, font=fnt, anchor="mm")

        elif preset == "wallpaper-ascii":
            ramp = "  .:-=+*#%@"
            sample = sample_wallpaper_ascii(cols, rows)
            cells = sample.get("cells", [])
            if len(cells) >= cols * rows:
                for r in range(rows):
                    py = (r + 0.5) * cell_h
                    for c in range(cols):
                        px = (c + 0.5) * cell_w
                        lum, hex_c = cells[r * cols + c]
                        idx = max(0, min(len(ramp) - 1, int(lum * len(ramp))))
                        if idx <= 1:
                            continue
                        draw.text((px, py), ramp[idx], fill=hex_c, font=fnt, anchor="mm")

        else:  # topo-wave
            ramp = "  .:-=+*#%@"
            for r in range(rows):
                py = (r + 0.5) * cell_h
                ny = r / rows
                for c in range(cols):
                    px = (c + 0.5) * cell_w
                    nx = c / cols
                    v1 = math.sin(nx * 6.2 + t * 1.1 + math.cos(ny * 4.0 - t * 0.7))
                    v2 = math.cos(ny * 5.5 - t * 0.8 + math.sin(nx * 4.8 + t * 0.6))
                    val = max(0.0, min(0.999, ((v1 + v2) * 0.5 + 1.0) * 0.5))
                    idx = int(val * len(ramp))
                    if idx <= 1:
                        continue
                    col = red_col if idx == len(ramp) - 1 else (bright_col if idx >= len(ramp) - 2 else dim_col)
                    draw.text((px, py), ramp[idx], fill=col, font=fnt, anchor="mm")

        img.save(out_path, "PNG")
        if os.path.lexists(LOCK_SYMLINK):
            os.remove(LOCK_SYMLINK)
        os.symlink(out_path, LOCK_SYMLINK)
    except Exception:
        pass
    return out_path


def sample_wallpaper_ascii(cols=76, rows=42):
    """Samples the current wallpaper image into a color + luminance grid for Chameleon Image-to-ASCII."""
    wp = get_current_wallpaper()
    if not wp or not os.path.isfile(wp):
        info = collect_wallpapers()
        wps = info.get("wallpapers", [])
        if wps:
            wp = wps[0]["path"]
    if not wp or not os.path.isfile(wp):
        return {"cols": cols, "rows": rows, "cells": []}

    try:
        with Image.open(wp) as im:
            im_rgb = im.convert("RGB")
            w, h = im_rgb.size
            target_ratio = cols / max(1, rows)
            src_ratio = w / max(1, h)
            if src_ratio > target_ratio:
                new_w = int(h * target_ratio)
                left = (w - new_w) // 2
                im_crop = im_rgb.crop((left, 0, left + new_w, h))
            else:
                new_h = int(w / target_ratio)
                top = (h - new_h) // 2
                im_crop = im_rgb.crop((0, top, w, top + new_h))

            small = im_crop.resize((cols, rows), Image.Resampling.BILINEAR)
            pixels = list(small.getdata())
            cells = []
            for r, g, b in pixels:
                lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
                # Boost saturation/brightness slightly for dark glass desktop contrast
                mr = min(255, int(r * 1.15 + 18))
                mg = min(255, int(g * 1.15 + 18))
                mb = min(255, int(b * 1.15 + 18))
                cells.append([round(lum, 3), f"#{mr:02x}{mg:02x}{mb:02x}"])
            return {"cols": cols, "rows": rows, "path": wp, "cells": cells}
    except Exception as e:
        return {"cols": cols, "rows": rows, "cells": [], "error": str(e)}


def ensure_awww_daemon():
    if not shutil.which("awww"):
        return False
    try:
        res = subprocess.run(
            ["awww", "query"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=1,
        )
        if res.returncode == 0:
            return True
        if shutil.which("awww-daemon"):
            subprocess.Popen(
                ["awww-daemon"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            import time
            for _ in range(15):
                time.sleep(0.08)
                if subprocess.run(
                    ["awww", "query"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                ).returncode == 0:
                    return True
    except Exception:
        pass
    return False


def set_display_wallpaper(img_path, transition="fade", duration="0.45", angle="30"):
    if not os.path.isfile(img_path):
        return False

    if ensure_awww_daemon():
        cmd = [
            "awww", "img", img_path,
            "--resize", "crop",
            "--crop-gravity", "center",
            "--transition-type", transition,
            "--transition-duration", str(duration),
            "--transition-fps", "60",
        ]
        if transition in ("wipe", "wave", "any", "outer"):
            cmd.extend(["--transition-angle", str(angle)])
        try:
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3)
            return True
        except Exception:
            pass

    if shutil.which("swww"):
        try:
            subprocess.run(
                [
                    "swww", "img", img_path,
                    "--transition-type", transition,
                    "--transition-duration", str(duration),
                    "--transition-fps", "60",
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=3,
            )
            return True
        except Exception:
            pass

    return False


def update_blurred_and_ecosystem(img_path):
    ensure_dirs_and_migrate()

    # 1. Record active wallpaper in glyph-shell and legacy ml4w cache
    for target_file in (GLYPH_CURRENT_WP, ML4W_CURRENT_WP):
        try:
            with open(target_file, "w") as f:
                f.write(img_path + "\n")
        except Exception:
            pass

    # 2. Update lockscreen wallpaper symlink (/tmp/nothing_lock_wallpaper)
    try:
        if os.path.lexists(LOCK_SYMLINK):
            os.remove(LOCK_SYMLINK)
        os.symlink(img_path, LOCK_SYMLINK)
    except Exception:
        pass

    # 3. Generate frosted glass blur for DesktopWidgetsWindow & NotificationPopupWindow
    try:
        src_sig = f"{img_path}:{int(os.path.getmtime(img_path))}:v5"
        wp_hash = hashlib.md5(src_sig.encode("utf-8")).hexdigest()[:10]
        custom_blurred_wp = f"/tmp/ml4w_widget_frost_{wp_hash}.jpg"

        if not os.path.exists(custom_blurred_wp):
            for old_f in glob.glob("/tmp/ml4w_widget_frost_*.jpg"):
                try:
                    os.remove(old_f)
                except Exception:
                    pass

            if shutil.which("magick"):
                subprocess.run(
                    [
                        "magick",
                        img_path,
                        "-resize", "1920x1080^",
                        "-gravity", "center",
                        "-extent", "1920x1080",
                        "-blur", "0x16",
                        custom_blurred_wp,
                    ],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=5,
                )
            else:
                from PIL import ImageFilter
                with Image.open(img_path) as im:
                    im_rgb = im.convert("RGB").resize((1920, 1080), Image.Resampling.LANCZOS)
                    im_blur = im_rgb.filter(ImageFilter.GaussianBlur(radius=16))
                    im_blur.save(custom_blurred_wp, "JPEG", quality=85)

        if os.path.exists(custom_blurred_wp):
            shutil.copy2(custom_blurred_wp, ML4W_BLURRED_WP)
    except Exception:
        pass

    # 4. Run matugen in background if available (for GTK/system colors)
    for m_bin in (
        shutil.which("matugen"),
        os.path.expanduser("~/.cargo/bin/matugen"),
        os.path.expanduser("~/.local/bin/matugen"),
    ):
        if m_bin and os.path.isfile(m_bin):
            try:
                subprocess.Popen(
                    [m_bin, "image", img_path, "--source-color-index", "0", "-m", "dark"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
            except Exception:
                pass
            break


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"

    if cmd == "list":
        print(json.dumps(collect_wallpapers()))

    elif cmd == "preview":
        if len(sys.argv) < 3:
            sys.exit(1)
        target = os.path.expanduser(sys.argv[2])
        set_display_wallpaper(target, transition="fade", duration="0.38")
        print(json.dumps({"status": "previewed", "path": target}))

    elif cmd == "apply":
        if len(sys.argv) < 3:
            sys.exit(1)
        target = os.path.expanduser(sys.argv[2])
        skip_display = ("--already-previewed" in sys.argv)
        set_ascii_state(False)
        if not skip_display:
            set_display_wallpaper(target, transition="wipe", duration="0.65", angle="30")
        update_blurred_and_ecosystem(target)
        print(json.dumps({"status": "applied", "path": target}))

    elif cmd == "apply-ascii":
        preset = sys.argv[2] if len(sys.argv) >= 3 else "topo-wave"
        state = set_ascii_state(True, preset)
        print(json.dumps({"status": "applied-ascii", "ascii": state}))

    elif cmd == "ascii-state":
        print(json.dumps(get_ascii_state()))

    elif cmd == "render-ascii-lock":
        preset = sys.argv[2] if len(sys.argv) >= 3 else None
        out = render_ascii_lock_wallpaper(preset)
        print(json.dumps({"status": "rendered-ascii-lock", "path": out}))

    elif cmd == "sample-ascii":
        print(json.dumps(sample_wallpaper_ascii()))

    elif cmd == "random":
        info = collect_wallpapers()
        wps = info.get("wallpapers", [])
        if not wps:
            print(json.dumps({"status": "empty", "message": "No wallpapers found"}))
            sys.exit(0)
        set_ascii_state(False)
        current = info.get("current", "")
        candidates = [w for w in wps if os.path.abspath(w["path"]) != os.path.abspath(current)]
        chosen = random.choice(candidates if candidates else wps)
        set_display_wallpaper(chosen["path"], transition="wipe", duration="0.7", angle="30")
        update_blurred_and_ecosystem(chosen["path"])
        print(json.dumps({"status": "applied", "path": chosen["path"], "name": chosen["name"]}))

    elif cmd == "open-folder":
        ensure_dirs_and_migrate()
        subprocess.Popen(
            ["xdg-open", PRIMARY_WP_DIR],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )


if __name__ == "__main__":
    main()

