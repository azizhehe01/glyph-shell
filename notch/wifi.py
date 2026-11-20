#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys


def get_wifi_status():
    data = {
        "wifi_enabled": True,
        "active_ssid": "",
        "active_ip": "",
        "networks": []
    }

    try:
        radio = subprocess.check_output(
            ["nmcli", "radio", "wifi"], stderr=subprocess.DEVNULL, timeout=2
        ).decode().strip()
        data["wifi_enabled"] = (radio.lower() == "enabled")
    except Exception:
        data["wifi_enabled"] = True

    if not data["wifi_enabled"]:
        return data

    saved = set()
    try:
        lines = subprocess.check_output(
            ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"],
            stderr=subprocess.DEVNULL, timeout=2
        ).decode().splitlines()
        for ln in lines:
            parts = ln.split(":")
            if len(parts) >= 1 and parts[0].strip():
                saved.add(parts[0].strip())
    except Exception:
        pass

    try:
        ip_out = subprocess.check_output(
            ["ip", "-4", "addr", "show"], stderr=subprocess.DEVNULL, timeout=2
        ).decode()
        m = re.search(r"inet (\d+\.\d+\.\d+\.\d+)/\d+.*(wlan|wlp|wlx|wlo)", ip_out)
        if m:
            data["active_ip"] = m.group(1)
    except Exception:
        pass

    seen_ssids = set()
    try:
        scan_out = subprocess.check_output(
            ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list"],
            stderr=subprocess.DEVNULL, timeout=4
        ).decode().splitlines()

        for line in scan_out:
            parts = line.split(":")
            if len(parts) < 3:
                continue
            in_use = (parts[0].strip() == "*")
            ssid = parts[1].strip()
            if not ssid or ssid in seen_ssids:
                continue
            seen_ssids.add(ssid)

            signal_val = 0
            try:
                signal_val = int(parts[2].strip())
            except Exception:
                signal_val = 50

            bars = 1
            if signal_val >= 75:
                bars = 4
            elif signal_val >= 50:
                bars = 3
            elif signal_val >= 25:
                bars = 2

            sec = parts[3].strip() if len(parts) > 3 else ""
            is_locked = bool(sec and sec != "--")

            if in_use:
                data["active_ssid"] = ssid

            data["networks"].append({
                "ssid": ssid,
                "signal": signal_val,
                "bars": bars,
                "security": sec if is_locked else "Open",
                "is_locked": is_locked,
                "is_connected": in_use,
                "is_saved": (ssid in saved)
            })
    except Exception:
        pass

    data["networks"].sort(key=lambda x: (
        not x["is_connected"],
        not x["is_saved"],
        -x["signal"]
    ))

    return data


def toggle_wifi():
    try:
        radio = subprocess.check_output(
            ["nmcli", "radio", "wifi"], stderr=subprocess.DEVNULL, timeout=2
        ).decode().strip().lower()
        new_state = "off" if radio == "enabled" else "on"
        subprocess.run(["nmcli", "radio", "wifi", new_state], check=True, timeout=3)
        return {"success": True, "state": new_state}
    except Exception as e:
        return {"success": False, "error": str(e)}


def connect_wifi(ssid, password=None):
    try:
        # Check if already a saved connection
        saved = set()
        try:
            lines = subprocess.check_output(
                ["nmcli", "-t", "-f", "NAME", "connection", "show"],
                stderr=subprocess.DEVNULL, timeout=2
            ).decode().splitlines()
            saved = {ln.strip() for ln in lines if ln.strip()}
        except Exception:
            pass

        if not password and ssid in saved:
            cmd = ["nmcli", "connection", "up", "id", ssid]
        elif password:
            if ssid in saved:
                subprocess.run(
                    ["nmcli", "connection", "delete", "id", ssid],
                    capture_output=True,
                    timeout=3,
                )
            cmd = ["nmcli", "dev", "wifi", "connect", ssid, "password", password]
        else:
            cmd = ["nmcli", "dev", "wifi", "connect", ssid]

        res = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        if res.returncode == 0:
            return {"success": True, "ssid": ssid, "message": f"Connected to {ssid}"}
        else:
            err = res.stderr.strip() or res.stdout.strip()
            return {"success": False, "ssid": ssid, "message": err or "Failed to connect"}
    except Exception as e:
        return {"success": False, "message": str(e)}


def disconnect_wifi(ssid=None):
    try:
        if ssid:
            cmd = ["nmcli", "connection", "down", "id", ssid]
        else:
            cmd = ["nmcli", "dev", "disconnect", "wlan0"]
            # Fallback to finding wireless device
            try:
                devs = subprocess.check_output(
                    ["nmcli", "-t", "-f", "DEVICE,TYPE", "device"],
                    stderr=subprocess.DEVNULL, timeout=2
                ).decode().splitlines()
                for d in devs:
                    p = d.split(":")
                    if len(p) >= 2 and p[1] == "wifi":
                        cmd = ["nmcli", "dev", "disconnect", p[0]]
                        break
            except Exception:
                pass

        res = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        return {"success": (res.returncode == 0), "message": res.stdout.strip() or res.stderr.strip()}
    except Exception as e:
        return {"success": False, "message": str(e)}


def _gf_init():
    exp = [0] * 512
    log = [0] * 256
    x = 1
    for i in range(255):
        exp[i] = x
        log[x] = i
        x <<= 1
        if x & 0x100:
            x ^= 0x11D
    for i in range(255, 512):
        exp[i] = exp[i - 255]
    return exp, log


_GF_EXP, _GF_LOG = _gf_init()


def _gf_mul(a, b):
    if a == 0 or b == 0:
        return 0
    return _GF_EXP[_GF_LOG[a] + _GF_LOG[b]]


def _rs_generator(ec_count):
    gen = [1]
    for i in range(ec_count):
        nxt = [0] * (len(gen) + 1)
        factor = _GF_EXP[i]
        for j, coef in enumerate(gen):
            nxt[j] ^= coef
            nxt[j + 1] ^= _gf_mul(coef, factor)
        gen = nxt
    return gen


def _rs_remainder(data, ec_count):
    gen = _rs_generator(ec_count)
    res = list(data) + [0] * ec_count
    for i in range(len(data)):
        coef = res[i]
        if coef != 0:
            for j in range(1, len(gen)):
                res[i + j] ^= _gf_mul(gen[j], coef)
    return res[len(data):]


# ISO/IEC 18004 Versions 1-5, Error Correction Level L (single RS block)
_QR_VERSIONS_L = {
    1: (21, 19, 7, []),
    2: (25, 34, 10, [6, 18]),
    3: (29, 55, 15, [6, 22]),
    4: (33, 80, 20, [6, 26]),
    5: (37, 108, 26, [6, 30]),
}


def build_qr_matrix(text):
    """Generates an ISO/IEC 18004 QR Code matrix (0/1 ints) using Byte Mode + EC Level L."""
    raw = text.encode("utf-8")
    ver = None
    for v, (_, data_cw, _, _) in _QR_VERSIONS_L.items():
        # 4 bits mode + 8 bits len + 8*len(raw) bits data <= data_cw * 8
        if 12 + len(raw) * 8 <= data_cw * 8:
            ver = v
            break
    if ver is None:
        ver = 5
        raw = raw[:106]

    size, data_cw, ec_cw, align_pos = _QR_VERSIONS_L[ver]

    # 1. Encode bit stream (Mode 0100 = Byte, 8-bit char count for v1-9)
    bits = []
    def push_bits(val, length):
        for b in range(length - 1, -1, -1):
            bits.append((val >> b) & 1)

    push_bits(0b0100, 4)
    push_bits(len(raw), 8)
    for byte in raw:
        push_bits(byte, 8)

    max_bits = data_cw * 8
    term_len = min(4, max_bits - len(bits))
    push_bits(0, term_len)
    while len(bits) % 8 != 0:
        bits.append(0)

    data_bytes = []
    for i in range(0, len(bits), 8):
        bval = 0
        for j in range(8):
            bval = (bval << 1) | bits[i + j]
        data_bytes.append(bval)

    pad_cycle = (0xEC, 0x11)
    p_idx = 0
    while len(data_bytes) < data_cw:
        data_bytes.append(pad_cycle[p_idx % 2])
        p_idx += 1

    ec_bytes = _rs_remainder(data_bytes, ec_cw)
    all_codewords = data_bytes + ec_bytes
    codeword_bits = []
    for cw in all_codewords:
        for b in range(7, -1, -1):
            codeword_bits.append((cw >> b) & 1)

    # 2. Initialize function pattern grid & reserved mask
    grid = [[0] * size for _ in range(size)]
    reserved = [[False] * size for _ in range(size)]

    def set_func(r, c, val):
        if 0 <= r < size and 0 <= c < size:
            grid[r][c] = 1 if val else 0
            reserved[r][c] = True

    def place_finder(top_r, left_c):
        for dr in range(-1, 8):
            for dc in range(-1, 8):
                r, c = top_r + dr, left_c + dc
                if not (0 <= r < size and 0 <= c < size):
                    continue
                if dr in (-1, 7) or dc in (-1, 7):
                    set_func(r, c, 0)
                elif dr in (0, 6) or dc in (0, 6) or (2 <= dr <= 4 and 2 <= dc <= 4):
                    set_func(r, c, 1)
                else:
                    set_func(r, c, 0)

    place_finder(0, 0)
    place_finder(0, size - 7)
    place_finder(size - 7, 0)

    # Alignment patterns
    for ar in align_pos:
        for ac in align_pos:
            if reserved[ar][ac]:
                continue
            for dr in range(-2, 3):
                for dc in range(-2, 3):
                    is_dark = (max(abs(dr), abs(dc)) == 2) or (dr == 0 and dc == 0)
                    set_func(ar + dr, ac + dc, 1 if is_dark else 0)

    # Timing strips
    for i in range(8, size - 8):
        val = 1 if (i % 2 == 0) else 0
        set_func(6, i, val)
        set_func(i, 6, val)

    # Dark module + reserve format info strips
    set_func(size - 8, 8, 1)
    for i in range(9):
        if i != 6:
            reserved[8][i] = True
            reserved[i][8] = True
    for i in range(8):
        reserved[8][size - 1 - i] = True
    for i in range(7):
        reserved[size - 1 - i][8] = True

    # 3. Place data + EC bits in zig-zag order
    bit_idx = 0
    col = size - 1
    going_up = True
    while col > 0:
        if col == 6:
            col -= 1
        row_range = range(size - 1, -1, -1) if going_up else range(size)
        for r in row_range:
            for dc in (0, -1):
                c = col + dc
                if not reserved[r][c]:
                    grid[r][c] = codeword_bits[bit_idx] if bit_idx < len(codeword_bits) else 0
                    bit_idx += 1
        col -= 2
        going_up = not going_up

    # 4. Evaluate masks 0..7 and select lowest penalty
    def mask_cond(m, r, c):
        if m == 0:
            return (r + c) % 2 == 0
        if m == 1:
            return r % 2 == 0
        if m == 2:
            return c % 3 == 0
        if m == 3:
            return (r + c) % 3 == 0
        if m == 4:
            return (r // 2 + c // 3) % 2 == 0
        if m == 5:
            return ((r * c) % 2 + (r * c) % 3) == 0
        if m == 6:
            return (((r * c) % 2 + (r * c) % 3) % 2) == 0
        return (((r + c) % 2 + (r * c) % 3) % 2) == 0

    def apply_format(mat, mask_id):
        data = (0b01 << 3) | mask_id  # EC Level L = 01
        val = data << 10
        for i in range(14, 9, -1):
            if (val >> i) & 1:
                val ^= 0x537 << (i - 10)
        fmt = ((data << 10) | val) ^ 0x5412

        def fbit(idx):
            return (fmt >> idx) & 1

        c1_coords = [
            (8, 0), (8, 1), (8, 2), (8, 3), (8, 4), (8, 5), (8, 7), (8, 8),
            (7, 8), (5, 8), (4, 8), (3, 8), (2, 8), (1, 8), (0, 8),
        ]
        for idx, (rr, cc) in enumerate(c1_coords):
            mat[rr][cc] = fbit(14 - idx)
        for i in range(7):
            mat[size - 1 - i][8] = fbit(14 - i)
        for i in range(8):
            mat[8][size - 8 + i] = fbit(7 - i)

    def penalty_score(mat):
        score = 0
        # Rule 1: adjacent runs >= 5
        for r in range(size):
            run = 1
            for c in range(1, size):
                if mat[r][c] == mat[r][c - 1]:
                    run += 1
                    if run == 5:
                        score += 3
                    elif run > 5:
                        score += 1
                else:
                    run = 1
        for c in range(size):
            run = 1
            for r in range(1, size):
                if mat[r][c] == mat[r - 1][c]:
                    run += 1
                    if run == 5:
                        score += 3
                    elif run > 5:
                        score += 1
                else:
                    run = 1
        # Rule 2: 2x2 blocks
        for r in range(size - 1):
            for c in range(size - 1):
                v = mat[r][c]
                if v == mat[r][c + 1] == mat[r + 1][c] == mat[r + 1][c + 1]:
                    score += 3
        # Rule 3: finder-like 1:1:3:1:1 patterns with 4-module white margin
        p1 = [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0]
        p2 = [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1]
        for r in range(size):
            row = mat[r]
            for c in range(size - 10):
                seg = row[c:c + 11]
                if seg == p1 or seg == p2:
                    score += 40
        for c in range(size):
            for r in range(size - 10):
                seg = [mat[r + k][c] for k in range(11)]
                if seg == p1 or seg == p2:
                    score += 40
        # Rule 4: dark ratio deviation from 50%
        dark = sum(sum(r) for r in mat)
        pct = (dark * 100) / (size * size)
        prev5 = int(pct // 5) * 5
        next5 = prev5 + 5
        score += min(abs(prev5 - 50) // 5, abs(next5 - 50) // 5) * 10
        return score

    best_mat = None
    best_score = None
    for m in range(8):
        cand = [list(row) for row in grid]
        for r in range(size):
            for c in range(size):
                if not reserved[r][c] and mask_cond(m, r, c):
                    cand[r][c] ^= 1
        apply_format(cand, m)
        sc = penalty_score(cand)
        if best_score is None or sc < best_score:
            best_score = sc
            best_mat = cand

    return best_mat


def _escape_qr_field(val):
    if not val:
        return ""
    out = []
    for ch in val:
        if ch in ("\\", ";", ",", ":", '"'):
            out.append("\\" + ch)
        else:
            out.append(ch)
    return "".join(out)


def get_wifi_share_info(target_ssid=None):
    ssid = (target_ssid or "").strip()
    security = ""
    password = ""

    # Determine current active SSID (same IN-USE field used in get_wifi_status)
    active_ssid = ""
    try:
        active_out = subprocess.check_output(
            ["nmcli", "-t", "-f", "IN-USE,SSID,SECURITY", "dev", "wifi", "list"],
            stderr=subprocess.DEVNULL, timeout=3
        ).decode().splitlines()
        for ln in active_out:
            parts = ln.split(":")
            if len(parts) >= 3 and parts[0].strip() == "*":
                active_ssid = parts[1].strip()
                if not ssid:
                    ssid = active_ssid
                    security = parts[2].strip()
                elif ssid == active_ssid:
                    security = parts[2].strip()
                break
    except Exception:
        pass

    # Query nmcli show-password directly if targeting active connection (or when SSID wasn't resolved yet)
    if not ssid or ssid == active_ssid:
        try:
            sp_out = subprocess.check_output(
                ["nmcli", "dev", "wifi", "show-password"],
                stderr=subprocess.DEVNULL, timeout=3
            ).decode().splitlines()
            sp_ssid = ""
            sp_sec = ""
            sp_pwd = ""
            for ln in sp_out:
                if ln.startswith("SSID:"):
                    sp_ssid = ln.split(":", 1)[1].strip()
                elif ln.startswith("Security:"):
                    sp_sec = ln.split(":", 1)[1].strip()
                elif ln.startswith("Password:"):
                    sp_pwd = ln.split(":", 1)[1].strip()
            if not ssid and sp_ssid:
                ssid = sp_ssid
            if sp_sec:
                security = sp_sec
            if sp_pwd:
                password = sp_pwd
        except Exception:
            pass

    # Fallback: read saved connection PSK / key-mgmt directly via nmcli
    if ssid and not password:
        try:
            sec_out = subprocess.check_output(
                ["nmcli", "-s", "-t", "-g", "802-11-wireless-security.psk,802-11-wireless-security.key-mgmt", "connection", "show", ssid],
                stderr=subprocess.DEVNULL, timeout=3
            ).decode().splitlines()
            if len(sec_out) >= 1 and sec_out[0].strip():
                password = sec_out[0].strip()
            if len(sec_out) >= 2 and sec_out[1].strip() and not security:
                security = sec_out[1].strip()
        except Exception:
            pass

    if not ssid:
        return {"success": False, "error": "No WiFi network selected or connected"}

    sec_upper = (security or "").upper()
    if not password or sec_upper in ("", "--", "NONE", "OPEN"):
        qr_type = "nopass" if not password else "WPA"
    elif "WEP" in sec_upper:
        qr_type = "WEP"
    else:
        qr_type = "WPA"

    if qr_type == "nopass":
        payload = f"WIFI:T:nopass;S:{_escape_qr_field(ssid)};;"
    else:
        payload = f"WIFI:T:{qr_type};S:{_escape_qr_field(ssid)};P:{_escape_qr_field(password)};;"

    matrix = build_qr_matrix(payload)
    return {
        "success": True,
        "ssid": ssid,
        "security": qr_type,
        "password": password,
        "payload": payload,
        "size": len(matrix),
        "matrix": matrix,
    }


if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else "scan"

    if action == "scan":
        print(json.dumps(get_wifi_status()))
    elif action == "toggle":
        print(json.dumps(toggle_wifi()))
    elif action == "connect":
        target_ssid = sys.argv[2] if len(sys.argv) > 2 else ""
        target_pwd = sys.argv[3] if len(sys.argv) > 3 else None
        print(json.dumps(connect_wifi(target_ssid, target_pwd)))
    elif action == "disconnect":
        target_ssid = sys.argv[2] if len(sys.argv) > 2 else None
        print(json.dumps(disconnect_wifi(target_ssid)))
    elif action == "share":
        target_ssid = sys.argv[2] if len(sys.argv) > 2 else None
        print(json.dumps(get_wifi_share_info(target_ssid)))
    else:
        print(json.dumps({"error": f"Unknown action: {action}"}))
