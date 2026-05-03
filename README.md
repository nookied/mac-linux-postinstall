# mac-linux-postinstall

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

| MacBook | Distro | Status |
|---|---|---|
| MacBook Air 2017 (`MacBookAir7,2`) | Fedora Workstation 44 | Supported |
| more devices & distros… | | Planned |

If your hardware/distro combo isn't supported, the script will detect it and exit cleanly. [Open an issue](https://github.com/nookied/mac-linux-postinstall/issues) with what was detected and we'll consider adding it.

## What gets installed

### Critical (always, no opt-out)

- RPM Fusion repos (free + non-free)
- Broadcom BCM4360 WiFi driver (`akmod-wl`)
- Multimedia codecs (H.264, MP3, ffmpeg full)
- Function-key behavior fix (brightness/volume work without `Fn`)

### Optional (interactive checklist before install)

- **TLP** — better battery life than the default `power-profiles-daemon`
- **mbpfan** — sensible fan curves (Apple's default SMC curve runs hot under Linux)
- **Flathub** — the full Flathub remote (Fedora's default is filtered)
- **Dev tools** — git, neovim, tmux, gcc, clang, ripgrep, fd, jq
- **GNOME Tweaks + Extension Manager**
- **FaceTime HD camera driver** — off by default, fragile

## After it finishes

Reboot if the script asks you to, then verify:

```bash
lspci -k | grep -A 3 Network         # → 'Kernel driver in use: wl'
sensors                               # → fan RPM + temps
upower -i $(upower -e | grep BAT)     # → battery info
```

## License

MIT.
