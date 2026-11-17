<p align="center">
  <h1 align="center">GLYPH-SHELL</h1>
  <p align="center">
    <strong>Nothing OS 3.0 Dot-Matrix & Chameleon Frosted Glass Desktop Shell Suite for Hyprland</strong>
  </p>
  <p align="center">
    <a href="https://quickshell.outfoxxed.me/"><img src="https://img.shields.io/badge/Engine-Quickshell%20Qt6-black?style=for-the-badge&logo=qt" alt="Engine"></a>
    <a href="https://hyprland.org/"><img src="https://img.shields.io/badge/Compositor-Hyprland%20Wayland-00aaee?style=for-the-badge" alt="Compositor"></a>
    <a href="https://nothing.tech/"><img src="https://img.shields.io/badge/Style-Nothing%20OS%203.0-D71921?style=for-the-badge" alt="Design"></a>
    <a href="https://lrclib.net/"><img src="https://img.shields.io/badge/Lyrics-LRCLIB%20API-30D158?style=for-the-badge" alt="Lyrics"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-white?style=for-the-badge" alt="License: MIT"></a>
  </p>
</p>

---

## 🌟 Tentang glyph-shell

**`glyph-shell`** adalah *desktop shell suite* modern, elegan, dan kaya fitur yang dirancang khusus untuk ekosistem Wayland / Hyprland. Terinspirasi dari filosofi desain perangkat keras dan perangkat lunak **Nothing OS 3.0**, proyek ini menggabungkan estetika **Tipografi Dot-Matrix**, **Chameleon Frosted Glass** (GPU Dual-Kawase blur yang warnanya mengekstrak secara cerdas dari wallpaper dan cover album), serta komponen interaktif yang saling terintegrasi penuh tanpa memerlukan status bar konvensional (Waybar).

Dibangun secara native menggunakan framework **[Quickshell](https://quickshell.outfoxxed.me/) (Qt6 / QML)** dengan dukungan background daemon Python yang sangat ringan, hemat baterai, dan responsif.

<p align="center">
  <img src="assets/preview.png" alt="glyph-shell Desktop Preview" width="100%" />
</p>

---

## 🏛️ Arsitektur & Fitur Utama

```text
                               ┌────────────────────────────────────────────────┐
                               │   TOP NOTCH & DYNAMIC ISLAND STATUS (notch/)   │
                               └──────────────────────┬─────────────────────────┘
                                                      │
         ┌────────────────────────────────────────────┼────────────────────────────────────────┐
         │                                            │                                        │
┌────────▼─────────────────────────┐   ┌──────────────▼────────────────────┐   ┌───────────────▼────────────────────────┐
│  DESKTOP BENTO GRID (widgets/)   │   │ UNIFIED APP LAUNCHER (launcher/)  │   │  NOTIF & SIDEBAR (notifications/side/) │
│  • Nothing Dot-Matrix Clock      │   │ • 2D Icon Grid Matrix (4-Arah)    │   │  • Native D-Bus Frosted Notif Server   │
│  • Weather & IP Geolocation      │   │ • Smart App Fuzzy Search          │   │  • Shutter Sound Screenshot Suppress   │
│  • AutoMix Player + Synced Lyric │   │ • Instant Antigravity IDE Folder  │   │  • Slide-Out Music & Multi-Player      │
│  • Circular Ring Gauges (Gauges) │   │ • Tab Mode: [ALL] [APP] [FOLDER]  │   │  • Live Notification History Drawer    │
│  • Power & Sleep Capsule         │   └───────────────────────────────────┘   └────────────────────────────────────────┘
└──────────────────────────────────┘                                                           │
         │                                                                                     │
         └────────────────────────────────────────────┬────────────────────────────────────────┘
                                                      │
                               ┌──────────────────────▼─────────────────────────┐
                               │   DOT-MATRIX LOCK SCREEN (lockscreen/hyprlock) │
                               │   • Native PAM hyprlock + Dynamic WP Blur      │
                               │   • Media Player Pill + Glyph Passcode Capsule │
                               └────────────────────────────────────────────────┘
```

---

### 1. 👁️ Interactive Top Notch & Dynamic Island (`notch/`)
* **Mata Pelacak Kursor Interaktif:** Sepasang mata putih bergaya *Angry Eyes* dengan paralaks 2-layer dinamis yang melacak pergerakan kursor mouse di seluruh layar lewat Hyprland IPC daemon (`cursor.py`), lengkap dengan kedipan acak (*random blinks*).
* **Hover-to-Peek Status Capsule:** Tempelkan kursor ke ujung atas tengah layar untuk menampilkan kapsul status (*Dynamic Island*) horizontal 3-segmen:
  1. 🔋 **Baterai:** Icon dinamis (`󰂄` saat charging / `󰁹` saat baterai) + persentase dot-matrix `Ndot57`.
  2. 🕒 **Jam & Tanggal:** Jam digital dot-matrix + tanggal ringkas monospace.
  3. 📶 **WiFi Aktif:** Icon dot-matrix + nama SSID aktif (`HANA`).
* **Low Battery Rage Mode ($\le 15\%$):** 
  * Saat baterai kritis dan belum dicolok charger, Notch otomatis turun ke layar (*force drop-down*).
  * Sepasang mata merah menyala bergetar marah (*rage vibration*), teks savage dot-matrix yang berganti tiap 4.5s (*"CHARGE YOUR FUCKING LAPTOP RIGHT NOW!"*), dan animasi colokan yang bergerak maju-mundur meminta dicolok.
  * Klik Notch sekali untuk *snooze* selama 4 menit jika sedang dalam keadaan darurat.
* **Charger Relief Mode (Saat Dicolok):**
  * Begitu charger dicolok, Notch berubah menjadi hijau segar (`#30D158`), mata tersenyum lega (`^  ^`), teks adem (*"AHHH LEGA... SWEET ELECTRICITY ⚡"*), dan colokan nancep rapat dengan kilat `⚡` sebelum kembali sembunyi mulus.
* **Nothing OS Volume & Brightness HUD OSD:** Notch bermorfosis menjadi indikator volume/kecerahan dot-matrix saat tombol multimedia ditekan atau saat di-scroll langsung di atas notch.
* **WiFi Network Manager Popover (`Super + W`):** Menu koneksi WiFi bergaya dot-matrix dengan kekuatan sinyal bertingkat, inline password input, dan toggle ON/OFF.
* **Bluetooth Manager Popover (`Ctrl + Super + B`):** Menu Bluetooth native berbasis **BlueZ (`bluetoothctl`)** tanpa ketergantungan `blueman-manager`, menampilkan perangkat TWS/audio/input tersimpan dengan *1-click connect/disconnect*, indikator persentase baterai TWS, tombol scan perangkat sekitar, dan saklar power Bluetooth ON/OFF.
* **Display / HDMI Projection Menu (`Super + P`):** Pengalih mode multi-monitor instan (PC Only, Duplicate, Extend, Second Screen) menggunakan perintah native Hyprland.

---

### 2. 🍱 Desktop Bento Grid Widgets (`widgets/`)
* **Jam & Tanggal Digital Nothing OS:** Jam digital besar menggunakan font resmi `Ndot57` dan tanggal monospace `LetteraMonoLL`.
* **Kartu Cuaca & Lokasi Real-Time:** Icon cuaca dot-matrix, suhu tertinggi/terendah harian, suhu besar `Ndot55`, kondisi cuaca, serta deteksi lokasi otomatis berdasarkan IP publik dengan cache lokal 15 menit.
* **AutoMix BitChord Media Player:**
  * **Cover Bleed ke Blurred Glass:** Cover album bertransisi mulus (*smoothstep S-curve opacity mask*) ke frosted glass di bawahnya.
  * **Ambient Glass Color Wash:** Latar belakang kaca mengekstrak warna dominan bagian bawah cover album lagu yang sedang diputar.
  * **Lirik Tersinkronisasi Real-Time:** Mengambil lirik sinkron dari [LRCLIB](https://lrclib.net/) berdasarkan posisi pemutaran `playerctl` dengan baris aktif yang disorot otomatis.
* **Circular Ring Gauges (Grid 2x2):**
  * Menggantikan bar garis konvensional dengan 4 cincin melingkar (*circular gauges*) bergaya iOS/macOS:
    1. 💻 **BATTERY:** Persentase baterai laptop + icon dinamis (hijau / merah saat kritis).
    2. 🧠 **RAM / MEMORY:** Persentase dan jumlah pemakaian RAM real-time dari `/proc/meminfo`.
    3. 💾 **ROOT (`/`):** Kapasitas dan pemakaian partisi sistem Linux.
    4. 📁 **HOME (`/home`):** Kapasitas dan pemakaian partisi user.
* **Poster Frame Estetik:** Frame foto portrait 20px dengan *auto-reload* otomatis saat file [`assets/poster.jpg`](assets/poster.jpg) diganti.
* **Kapsul Kontrol Daya:** Tombol cepat untuk *Lock Screen* (`󰌾`), *Sleep/Suspend* (`󰤄`), *Power Off* (`󰐥`), dan *Reboot* (`󰑐`).

---

### 3. 🔔 Chameleon Notification Server (`notifications/`)
* Menggantikan daemon eksternal (seperti `dunst`, `mako`, atau `swaync`) melalui interface D-Bus `org.freedesktop.Notifications`.
* Kartu notifikasi floating dengan sudut membulat 20px, highlight tepi kaca, dan GPU Dual-Kawase blur.
* **Filter Khusus Screenshot:** Hasil tangkapan layar tidak menampilkan popup notifikasi, melainkan langsung memutar efek suara *shutter* kamera bawaan GNOME (*cekrek*) via PipeWire (`pw-play`).
* **Suppress Notif Baterai Sistem:** Notifikasi baterai bawaan otomatis diredam karena sudah ditangani secara interaktif oleh Notch Rage & Relief Mode.
* **Aksi Pintar Antigravity IDE:** Menampilkan tombol cepat interaktif untuk berpindah workspace ke Antigravity IDE saat ada prompt permission atau input.

---

### 4. 🎛️ Music Sidebar & Notification History Drawer (`sidebar/`)
* Dibuka/tutup dengan shortcut **`Ctrl + Super + S`** atau klik tombol di widget.
* **Multi-Player Switcher:** Beralih antar pemutar musik (Spotify, YouTube di Brave/Firefox/Chrome, VLC) secara instan.
* **My Playlist Drawer:** Simpan lagu favorit ke playlist lokal, langsung diputar via Spotify D-Bus (`org.mpris.MediaPlayer2.Player.OpenUri`).
* **Live Notification History:** Bagian bawah sidebar menampung seluruh riwayat notifikasi masuk yang dapat dihapus per item (`✕`) atau sekaligus (`CLEAR ALL`).

---

### 5. 🔒 Native Quickshell Dot-Matrix Lock Screen (`lockscreen/`)
* 100% Native **Quickshell (`WlSessionLock` + `Quickshell.Services.Pam`)** — tanpa ketergantungan `hyprlock` untuk tampilan utama.
* **Tengah Layar Bersih & Sinkronisasi Wallpaper:**
  * **Mode ASCII (`SILENT BLADE`):** Merender langsung shader GPU pedang 3D berputar di belakang layar dengan warna background pilihan lo.
  * **Mode Image:** Menampilkan wallpaper aktif dengan *Chameleon Frosted Glass blur*.
* **Bottom Widget Dock Minimalis:**
  * **Analog + Dot-Matrix Clock Card (`#000000`, `radius: 26`):** Jam analog real-time dengan 3 jarum bergerak tiap detik + jam digital `Ndot57` dua warna (oranye/putih) + tanggal.
  * **Auto-Hide Music Pill (MPRIS):** Muncul otomatis *hanya* saat memutar lagu (memprioritaskan Spotify di atas tab browser), lengkap dengan cover album `OpacityMask`, progress bar real-time, dan 3 kontrol bulat (`‹`, `▶/⏸`, `›`).
* **Auto-Show Passcode Dots (Zero Capsule):** Input password tersembunyi saat idle; begitu mengetik atau klik layar, titik-titik putih muncul mulus dari kiri ke kanan tanpa kotak kapsul.

---

### 6. 🚀 Unified App & IDE Project Launcher (`launcher/`)
* Dibuka/tutup dengan shortcut **`Ctrl + Super + Enter`**.
* **Unified Smart Search (Opsi B):** Satu kolom pencarian cerdas untuk mencari **Aplikasi Desktop** sekaligus **Folder Project / Repo Git**.
* **Open Folder in Antigravity IDE:** Memilih folder project (berbadge merah `IDE`) dan menekan `Enter` akan langsung membuka folder tersebut di **Antigravity IDE** (`/opt/antigravity/antigravity-ide <path>`).
* **Layout Grid 2D (5 Kolom):** Icon besar dengan nama ringkas, mendukung navigasi keyboard 4 arah penuh (**`←`**, **`→`**, **`↑`**, **`↓`**), dan tombol **`Tab`** untuk beralih filter `[ALL]`, `[APPS]`, dan `[FOLDERS]`.

---

### 7. 🖼️ Native Wallpaper Carousel & 100% Pure GPU Live ASCII (`wallpaper/`)
* Dibuka/tutup dengan shortcut **`Ctrl + Super + W`** (dan **`Super + Shift + W`** untuk random wallpaper).
* **Dual-Mode Switcher (`[ IMAGE ]` | `[ ⠿ ASCII LIVE ]`):** Tekan **`Tab`** atau klik pill di header untuk beralih antara galeri foto statis dan live shader ASCII.
* **`SILENT BLADE` — Minimalist 3D Shade-Block Sword (`480×270`):**
  * Menampilkan bilah pedang 3D *raymarched* beresolusi tinggi menggunakan **Edge-to-Edge Unicode Shade Blocks (`░ ▒ ▓ █`)** di atas background polos bersih tanpa *clutter*.
  * Melayang naik-turun, berputar pelan 360°, serta bereaksi terhadap gerakan kursor (*3D tilt* halus) dengan aksen **Nothing Red (`#D71921`)**.
* **100% Pure GPU Shader & Smart Auto-Pause:**
  * Dirender langsung di GPU menggunakan **Qt6 RHI `ShaderEffect` (GLSL 440 → SPIR-V `.qsb`)** tanpa loop JavaScript per-frame (**0% beban CPU**).
  * Otomatis **pause (0% CPU & 0% GPU)** ketika ada window aplikasi yang terbuka di workspace aktif, dan langsung **mati total (*unloaded*)** saat memakai wallpaper gambar biasa.
* **HSV Background Color Picker (`BG #HEX`):**
  * Tombol **`BG #HEX`** di header mode ASCII membuka popover **HSV Color Picker** (*2D Saturation × Darkness box*, *Rainbow Hue slider*, *Preview Swatch*, input kode `#HEX`, dan tombol **`RESET`** ke `#07080A`) dengan *live preview* real-time dan adaptasi kontras otomatis.
* **Bottom-Edge Horizontal Filmstrip & Live Preview:** Muncul mulus dari sisi bawah layar (bottom dock), membiarkan 85% layar tetap bersih. Geser dengan **`←`** / **`→`**, tekan **`Enter`** untuk menerapkan & menyinkronkan ke seluruh ekosistem (Frosted Glass widget, Lockscreen `hyprlock`, & `matugen`), atau **`ESC`** untuk batal.

---

### 8. 📋 Native Clipboard History (`clipboard/`)
* Dibuka/tutup dengan shortcut **`Super + V`**.
* **Smart Content Classification:** Otomatis membedakan tipe riwayat clipboard: **Gambar / Screenshot** (dengan preview thumbnail visual), **URL / Link**, **Kode / CLI Command**, dan **Teks Biasa**.
* **Filter Pills Real-Time:** Filter cepat dengan tombol **`[ALL]`**, **`[TEXT]`**, **`[CODE]`**, **`[IMAGES]`**, dan **`[LINKS]`** (atau tekan **`Tab`**).
* **Keyboard-First:** Navigasi dengan panah **`↑`** / **`↓`**, tekan **`Enter`** untuk menyalin ke clipboard aktif, dan tekan **`Delete`** untuk menghapus item.

---

### 9. 😀 Native Emoji Picker (`emoji/`)
* Dibuka/tutup dengan shortcut **`Ctrl + Super + E`**.
* **Grid Emoji Frosted Glass:** Tampilan grid emoji cepat dengan pencarian kata kunci real-time, kategori emoji, dan penyalinan instan ke clipboard (`wl-copy`) saat dipilih.

---

### 10. ⌨️ Keybindings Viewer & Search (`keybinds/`)
* Dibuka/tutup dengan shortcut **`Ctrl + Super + K`**.
* **Dual Search (Aksi & Tombol):** Cari shortcut berdasarkan deskripsi/nama fitur maupun langsung berdasarkan **kombinasi tombol** (misal ketik `super + v` untuk langsung menemukan Clipboard History).
* **Auto-Parsed dari Konfigurasi Hyprland:** Membaca langsung daftar binding aktif Hyprland secara real-time dengan pengelompokan kategori dan badge visual.

---

### 11. 🪟 Workspace Overview & Scratchpad (`overview/`)
* Dibuka/tutup dengan shortcut **`Super + Tab`**.
* **Live Window Thumbnails & App Icons:** Menampilkan preview real-time tiap workspace dan jendela aplikasi aktif (termasuk ikon aplikasi seperti Antigravity IDE), lengkap dengan dukungan **Special Workspace / Scratchpad** (`Super + S` / `Super + Shift + S`).
* **Dynamic Workspace Rows & Navigasi 4-Arah:** Navigasi penuh dengan tombol panah **`←`**, **`→`**, **`↑`**, **`↓`**; baris slot 5-workspace baru otomatis muncul saat turun dan hilang kembali jika tidak terpakai.
* **Manajemen Window Interaktif:** *Drag & drop* window antar workspace, *middle-click* untuk menutup window, dan transisi mulus keluar dari scratchpad ke workspace normal saat menekan **`Enter`**.

---

### 12. ⏻ Vertical Dot-Matrix Power Menu (`power/`)
* Dibuka/tutup dengan shortcut **`Ctrl + Super + P`**.
* **9×9 Nothing OS Dot-Matrix Capsule:** Kapsul vertikal *icon-only* di sisi kanan layar dengan efek *frosted glass* dan 5 tombol bulat berikon **9×9 LED dot-matrix** (**Lock**, **Suspend**, **Logout**, **Restart**, dan **Power Off**).
* **Smart Safe Shutdown:** Sebelum menjalankan *Logout*, *Restart*, atau *Power Off*, backend `power.py` otomatis menutup window secara aman; jika ada aplikasi yang menahan penutupan (seperti dialog *unsaved changes* atau konfirmasi tutup tab browser), fokus otomatis diarahkan ke window tersebut.
* **Keyboard & Force Mode:** Mendukung navigasi **`↑`** / **`↓`** + **`Enter`**, shortcut huruf (**`L`**, **`S`**, **`E`**, **`R`**, **`P`**), serta tahan **`Shift`** untuk mode paksa (`--force`).

---

## ⌨️ Shortcut Keyboard & Kontrol Cepat

| Shortcut / Aksi | Komponen | Fungsi |
| :--- | :--- | :--- |
| **`Super + Tab`** | **Workspace Overview** | Buka/tutup Workspace Overview & Scratchpad |
| **`Ctrl + Super + P`** | **Power Menu** | Buka/tutup Vertical 9×9 Dot-Matrix Power Menu |
| **`Ctrl + Super + K`** | **Keybindings** | Buka/tutup Keybindings Viewer & Search (cari via aksi atau tombol) |
| **`Ctrl + Super + E`** | **Emoji Picker** | Buka/tutup Native Nothing OS Emoji Picker |
| **`Super + V`** | **Clipboard** | Buka/tutup Native Clipboard History Modal (Nothing OS) |
| **`Ctrl + Super + Enter`** | **Launcher** | Buka/tutup Unified Application & Project Folder Launcher (2D Grid) |
| **`Ctrl + Super + W`** | **Wallpaper Carousel** | Buka/tutup Horizontal Wallpaper Selector dengan Live Instant Preview |
| **`Super + Shift + W`** | **Random Wallpaper** | Ganti ke wallpaper acak secara instan |
| **`Ctrl + Super + L`** | **Lockscreen** | Kunci layar dengan Nothing OS Dot-Matrix Lock Screen |
| **`Ctrl + Super + S`** | **Sidebar** | Buka/tutup panel sidebar pemutar musik & riwayat notifikasi |
| **`Super + W`** | **WiFi Manager** | Buka/tutup menu WiFi dot-matrix di Notch |
| **`Ctrl + Super + B`** | **Bluetooth Manager** | Buka/tutup menu Bluetooth dot-matrix di Notch (Pure BlueZ) |
| **`Super + P`** | **Display** | Buka/tutup menu proyeksi monitor (PC, Duplicate, Extend, Second) |
| **`XF86AudioRaiseVolume`** | Volume Up | Naikkan volume + tampilkan HUD Nothing OS |
| **`XF86AudioLowerVolume`** | Volume Down | Turunkan volume + tampilkan HUD Nothing OS |
| **`XF86AudioMute`** | Audio Mute | Toggle mute/unmute audio |
| **`XF86MonBrightnessUp`** | Brightness Up | Naikkan kecerahan + tampilkan HUD Nothing OS |
| **`XF86MonBrightnessDown`**| Brightness Down | Turunkan kecerahan + tampilkan HUD Nothing OS |
| **Tempel Kursor ke Atas** | **Dynamic Island** | Tampilkan status Baterai, Jam & WiFi di Notch |
| **Scroll di atas Notch** | Audio Volume | Atur volume langsung dengan mouse/touchpad |
| **Shift + Scroll di Notch**| Kecerahan | Atur kecerahan layar langsung |
| **Klik Kiri di Notch** | WiFi | Buka WiFi Manager (atau Snooze saat low battery rage) |
| **Klik Tengah di Notch** | Display | Buka Display Projection Manager |

---

## 📦 Kebutuhan Sistem (Dependencies)

Pastikan paket-paket berikut sudah terpasang di sistem Linux lo:

1. **Quickshell (`qs`)** (Framework UI Wayland Qt6)
   * Fedora: `sudo dnf copr enable errornointernet/quickshell && sudo dnf install quickshell`
   * Arch Linux: `yay -S quickshell-git`
2. **Hyprland** (Compositor Wayland) & **hyprlock** (Lock screen engine)
3. **playerctl** (Kontrol MPRIS & sinkronisasi lirik)
4. **brightnessctl** (Kontrol backlight kecerahan layar)
5. **NetworkManager (`nmcli`)** (Manajemen jaringan WiFi)
6. **ImageMagick (`magick`)** (Pemrosesan blur wallpaper)
7. **Python 3** (Daemon lirik, cuaca, partisi, pelacak kursor, dan playlist)
8. **Font:**
   * Font resmi Nothing OS (`Ndot55`, `Ndot57`, `NType82`, `LetteraMonoLL`) **sudah disertakan di dalam folder `assets/fonts/`** dan otomatis dipasang oleh script installer.
   * **FiraCode Nerd Font** (icon baterai, RAM, disk, media): `sudo dnf install fira-code-fonts` / `sudo pacman -S ttf-fira-code`.

---

## 🚀 Panduan Instalasi Cepat

### 1. Clone Repository
Clone repo ini ke direktori konfigurasi Quickshell:
```bash
git clone https://github.com/azizhehe01/glyph-shell.git ~/.config/quickshell/glyph-shell
cd ~/.config/quickshell/glyph-shell
```

### 2. Jalankan Installer Otomatis
Jalankan script installer yang sudah disediakan:
```bash
chmod +x install.sh
./install.sh
```
*Script ini otomatis menginstal font Nothing OS, mengonfigurasi Fontconfig alias Pango, mengatur permission script, menghubungkan lockscreen ke Hyprland, dan memeriksa kelengkapan paket sistem.*

### 3. Autostart di Hyprland
Tambahkan baris berikut ke konfigurasi autostart Hyprland lo (misal di `~/.config/hypr/hyprland.conf`):
```ini
exec-once = qs -p ~/.config/quickshell/glyph-shell
```

---

## 📁 Struktur Direktori Proyek

```text
glyph-shell/
├── assets/                         # Font Nothing OS, icon SVG dot-matrix, suara, dan gambar
│   ├── fonts/
│   │   ├── Ndot55-Regular.otf      # Font angka suhu cuaca dot-matrix
│   │   ├── Ndot57-Regular.otf      # Font jam digital, volume & baterai dot-matrix
│   │   ├── NType82-Regular.otf     # Font sans-serif bento grid & judul musik
│   │   └── LetteraMonoLL-Regular.otf # Font tanggal, artis & teks teknikal monospace
│   ├── camera-shutter.oga          # Efek suara cekrek kamera (GNOME) saat screenshot
│   ├── notif.mp3                   # Efek suara notifikasi masuk
│   ├── poster.jpg                  # Foto portrait frame bento grid (auto-reload)
│   ├── album.jpg                   # Cover album fallback
│   ├── folder-dot.svg              # Icon folder project dot-matrix
│   ├── search-dot.svg              # Icon search dot-matrix
│   └── *.svg                       # Icon WiFi, display, media, volume, cuaca, dll.
├── launcher/
│   ├── LauncherWindow.qml          # Modal Chameleon Frosted Glass 2D Grid App & IDE Launcher
│   └── apps.py                     # Provider aplikasi .desktop & pembuka folder project Antigravity IDE
├── clipboard/
│   ├── ClipboardWindow.qml         # Modal Clipboard History Nothing OS (search, preview, filter)
│   └── clipboard.py                # Engine cliphist extractor, categorizer & thumbnail generator
├── emoji/
│   ├── EmojiWindow.qml             # Modal Emoji Picker Nothing OS
│   ├── emoji.py                    # Provider & filter pencarian emoji
│   └── emojis.json                 # Database daftar emoji & kata kunci
├── keybinds/
│   ├── KeybindsWindow.qml          # Modal Keybindings Viewer & Search (cari aksi/tombol)
│   └── keybinds.py                 # Parser konfigurasi keybindings Hyprland
├── lockscreen/
│   ├── LockscreenWindow.qml        # Native WlSessionLock + PamContext lockscreen (Clock & MPRIS Dock)
│   ├── lock.sh                     # Launcher IPC lockscreen Quickshell (dengan fallback hyprlock)
│   ├── hyprlock.conf               # Konfigurasi fallback darurat untuk hyprlock
│   └── status.py                   # Provider data status fallback
├── hypr/
│   ├── autostart.lua               # Konfigurasi startup mandiri Hyprland (zero ML4W bloat)
│   └── keybindings.lua             # Preset lengkap shortcut glyph-shell untuk Hyprland
├── notch/
│   ├── NotchWindow.qml             # Window Top Notch, Angry Eyes, Dynamic Island, Rage & Relief Mode
│   ├── bluetooth.py                # Daemon Bluetooth native berbasis BlueZ (bluetoothctl)
│   ├── cursor.py                   # Daemon IPC pelacak kursor & active window
│   ├── display.py                  # Handler proyeksi layar multi-monitor HDMI
│   ├── status.py                   # Provider status cepat baterai & WiFi
│   └── wifi.py                     # Daemon pemindaian dan koneksi WiFi nmcli
├── notifications/
│   └── NotificationPopupWindow.qml # Server notifikasi native frosted glass
├── overview/
│   └── OverviewWindow.qml          # Workspace Overview, Live Thumbnails & Scratchpad Manager
├── power/
│   ├── PowerWindow.qml             # Kapsul vertikal Power Menu 9x9 Dot-Matrix
│   └── power.py                    # Backend Smart Safe Shutdown & manajemen window
├── sidebar/
│   ├── SidebarWindow.qml           # Panel slide-out musik, multi-player switcher & riwayat notifikasi
│   └── playlist.py                 # Service D-Bus & JSON manager playlist lagu
├── widgets/
│   ├── DesktopWidgetsWindow.qml    # Window utama bento grid widget desktop & circular ring gauges
│   └── stats.py                    # Service pengambil lirik, cuaca, RAM, partisi sistem & baterai
├── wallpaper/
│   ├── WallpaperWindow.qml         # Bottom-edge wallpaper filmstrip, Dual-Mode & HSV Color Picker
│   ├── AsciiWallpaperWindow.qml    # 100% Pure GPU ShaderEffect host + Smart Window Auto-Pause
│   ├── ascii_wallpaper.frag        # GLSL 440 raymarched 3D Shade-Block Sword shader
│   ├── ascii_wallpaper_v2.frag.qsb # Compiled Qt6 RHI SPIR-V shader binary
│   ├── ascii_font_atlas.png        # Monospace GPU glyph texture atlas
│   └── wallpaper.py                # Engine wallpaper standalone, state JSON, lockscreen & blur sync
├── wallpapers/                     # Koleksi wallpaper mandiri glyph-shell
├── install.sh                      # Turnkey setup & installer script
├── LICENSE                         # Lisensi MIT
├── shell.qml                       # Entry point Quickshell yang memuat seluruh modul
└── README.md                       # Dokumentasi lengkap
```

---

## 📜 Lisensi & Kredit
* Dirilis di bawah **[MIT License](LICENSE)** — bebas digunakan, dimodifikasi, dan didistribusikan.
* Dikembangkan oleh [@azizhehe01](https://github.com/azizhehe01) untuk ekosistem Wayland / Hyprland.
* Dibuat menggunakan framework [Quickshell](https://quickshell.outfoxxed.me/).
* Estetika visual terinspirasi dari filosofi desain hardware & software [Nothing OS](https://nothing.tech/).
* Database lirik musik didukung oleh komunitas terbuka [LRCLIB](https://lrclib.net/).
