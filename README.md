# mac-linux-postinstall

[![QA](https://github.com/nookied/mac-linux-postinstall/actions/workflows/qa.yml/badge.svg)](https://github.com/nookied/mac-linux-postinstall/actions/workflows/qa.yml)

One-line post-install script for Linux running on Apple MacBooks. Inspired by [brew.sh](https://brew.sh).

After a fresh Linux install on your MacBook, paste one command and the script:

- Installs the critical drivers your hardware needs (WiFi, codecs, function keys)
- Asks you which optional must-haves you want (TLP, mbpfan, Flathub, dev tools)
- Tells you when a reboot is required

## Install

If you have `curl` (Fedora and most desktop installs):

```bash
bash -c "$(curl -fsSL https://nookied.github.io/mac-linux-postinstall/install.sh)"
```

If you only have `wget` (some Debian/Ubuntu installs):

```bash
bash -c "$(wget -qO- https://nookied.github.io/mac-linux-postinstall/install.sh)"
```

> Run as your **normal user**, not as root. The script will ask for your sudo password when needed.

## Before you run

1. Finish your Linux install and boot into the new system
2. Get online — wired USB-C ethernet or phone tethering work; WiFi probably doesn't yet (that's what this script fixes)
3. Update your system first:

   ```bash
   sudo dnf upgrade --refresh -y && sudo reboot   # Fedora
   sudo apt update && sudo apt full-upgrade -y && sudo reboot   # Debian/Ubuntu
   ```

## Supported targets

| MacBook | Distro | Kernel | Status |
|---|---|---|---|
| MacBook Air 2017 (`MacBookAir7,2`) | Fedora Workstation 44 | 6.19 | Supported |
| MacBook Air 2017 (`MacBookAir7,2`) | Debian 13 (Trixie) | 6.12 LTS | Supported |
| more devices & distros… | | | Planned |

If your hardware/distro combo isn't supported, the script will detect it and exit cleanly. [Open an issue](https://github.com/nookied/mac-linux-postinstall/issues) with what was detected and we'll consider adding it.

## What gets installed

### Critical (always, no opt-out)

- Distro-specific extra repos enabled (RPM Fusion on Fedora, `non-free-firmware` + `contrib` on Debian)
- Broadcom BCM4360 WiFi driver (`akmod-wl` on Fedora, `broadcom-sta-dkms` on Debian)
- Multimedia codecs (H.264, MP3, full ffmpeg, full GStreamer plugin set)
- Function-key behavior fix (brightness/volume work without `Fn`)

### Optional (interactive checklist before install)

- **TLP** — better battery life than the default `power-profiles-daemon`
- **mbpfan** — sensible fan curves (Apple's default SMC curve runs hot under Linux)
- **Flathub** — the full Flathub remote (Fedora's default is filtered)
- **Dev tools** — git, neovim, tmux, gcc, clang, ripgrep, fd, jq
- **GNOME Tweaks + Extension Manager**
- **FaceTime HD camera driver** — off by default, fragile (see Known Issues below)

## Known issues

### FaceTime HD camera freezes on Fedora 44 (and any Linux on kernel ≥ 6.15)

The reverse-engineered `patjak/facetimehd` driver has an [open upstream regression](https://github.com/patjak/facetimehd/issues/315) on Linux kernels 6.15 and later. The module loads, captures one frame, then the GStreamer/PipeWire pipeline can't continue streaming — so **Cheese, GNOME Snapshot, and similar GStreamer-based camera apps freeze on the first frame**.

**Workaround**: browser-based camera apps work normally. They use v4l2 directly and bypass the broken pipeline.

Confirmed working on the freezing kernels:
- Zoom web client (`https://zoom.us/test`)
- Google Meet
- Discord (web)
- [webcamtests.com](https://webcamtests.com)

The script still installs the module so browser apps work — there's no downside to having it installed. Older-kernel distros sit before the regression window: **Debian 13** ships kernel 6.12 LTS, **Ubuntu 24.04 LTS** ships kernel 6.8 — both stream live in all apps. (Targets coming.)

## After it finishes

Reboot if the script asks you to, then verify:

```bash
lspci -k | grep -A 3 Network         # → 'Kernel driver in use: wl'
sensors                               # → fan RPM + temps
upower -i $(upower -e | grep BAT)     # → battery info
```

## License

MIT.
