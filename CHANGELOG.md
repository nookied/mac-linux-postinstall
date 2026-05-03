# Changelog

All notable changes to this project are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning will follow [SemVer](https://semver.org/) once we tag a `0.1.0`.

**Every behavior-changing commit MUST add an entry under `## [Unreleased]`.** Entries should include enough context that a future agent (or human) can understand *why*, not just *what*. Bug fixes especially: write what was broken, why, and how it was fixed — this is how we avoid running in circles.

---

## [Unreleased]

### Added

- **Project scaffolding** — converted single-script repo into a multi-target framework.
  - `docs/install.sh` — the bootstrap (entry point users `curl`/`wget`).
  - `lib/common.sh`, `lib/pkg.sh`, `lib/ui.sh`, `lib/detect.sh` — shared helpers, sourced by bootstrap after tarball download.
  - `targets/macbookair7_2-fedora44/{essentials,extras}.sh` — MVP target, content lifted and reorganized from the original `fedora-mba-setup.sh`.
  - `docs/index.html` — brew.sh-style landing page hosted via GitHub Pages from `/docs`.
- **CLAUDE.md** — single source of truth for any AI agent touching this repo. Architecture, conventions, gotchas, workflow.
- **AGENTS.md** — short pointer to CLAUDE.md so non-Claude agents (Cursor, Aider, Copilot, Codex) follow the same playbook.
- **CHANGELOG.md** — this file. Mandatory updates on behavior changes.

### Changed

- **One-liner pattern**: settled on `bash -c "$(curl -fsSL …)"` (and `wget` equivalent) instead of the more common `curl … | bash`. Reason: piped form detaches stdin, breaking interactive prompts and whiptail. Command-substitution form puts the script in argv and leaves stdin attached. **Do not regress this.**
- **Privilege model**: bootstrap now runs as the user and self-elevates via `sudo` for the install phase, instead of requiring the user to prefix `sudo bash …`. Brew.sh-aligned UX. Implementation writes the install runner to a tempfile and `sudo`-execs it (`sudo bash -c "..."` with multi-line piped content was fragile).
- **TUI selector**: replaced static `INSTALL_*=true` config flags at the top of the script with a runtime whiptail checklist populated from `extras.sh`. Defaults preserved from the original script.
- **Hosting**: bootstrap lives at `docs/install.sh` (single source of truth). Considered keeping `bootstrap.sh` at root with a copy in `docs/` but rejected because GitHub Pages does not follow symlinks and duplication risks drift.

### Fixed

- **Whiptail checklist double-box visual artifact** (`docs/install.sh`, `lib/ui.sh`): the checklist dialog appeared to render two overlapping dialog boxes because previous terminal output (dnf progress, log messages) remained on screen when whiptail drew its dialog. Fixed by calling `clear` immediately before the `tui_checklist` call so whiptail renders onto a clean terminal. Also capped `list_height` at the actual item count (previously `height - 8` could exceed the number of items on a large terminal, causing whiptail to allocate more list rows than items, which shifts the dialog geometry and can produce rendering glitches on some terminal sizes).

- **Unsupported target flow**: `docs/install.sh` now downloads the repo and runs full target detection before `sudo -v`, so unsupported machines exit with the friendly message before any privilege prompt.
- **mbpfan source fallback**: when Fedora does not provide `mbpfan`, the source build now clones the maintained `linux-on-mac/mbpfan` repo, installs the systemd unit explicitly, and warns instead of aborting the whole run if the optional fallback fails.
- **TLP service conflict handling**: TLP setup now stops/disables and masks `power-profiles-daemon.service` before enabling `tlp.service`, preventing the conflicting daemon from continuing in the current boot.
- **TLP install failure on Fedora 44 (`tuned-ppd` conflict)**: on Fedora 44, `tuned-ppd` (the `tuned`-backed replacement for `power-profiles-daemon`) ships dbus service files that TLP also owns — DNF refuses the install with a file-conflict error before any package is written. Fixed by stopping/disabling `tuned-ppd.service` and removing the `tuned-ppd` package **before** calling `dnf install tlp tlp-rdw`. Also mask `power-profiles-daemon.service` so neither backend can restart. Root cause: earlier fix only masked the service unit; it did not remove the conflicting package, so the RPM transaction still failed.
- **hid_apple config preservation**: function-key setup now updates or appends only the `fnmode=2` option instead of overwriting the whole `/etc/modprobe.d/hid_apple.conf` file.
- **GitHub username**: initial scaffolding hardcoded `karolnowacki` (inferred from the local macOS user dir `/Users/karolnowacki/`). Real GitHub handle is `nookied`. Replaced across `docs/install.sh` (GH_USER + URL comments), `docs/index.html` (install commands + footer links), `README.md` (install commands + issue link), and `CLAUDE.md` (architecture notes). Lesson for future agents: never infer a GitHub username from `$HOME` — always ask.

### Removed

- **`fedora-mba-setup.sh`** (the original framework script provided at project start) — content split into `targets/macbookair7_2-fedora44/essentials.sh` (RPM Fusion, Broadcom WiFi, codecs, fn-key fix) and `extras.sh` (TLP, mbpfan, Flathub, dev tools, GNOME tweaks, FaceTime camera). Git history preserves the original. Do not recreate.

### Decisions / non-changes (recorded so we don't relitigate)

- **Custom domain** (e.g. `maclin.sh`): deferred. GitHub Pages URL is fine for now. Switch by adding `docs/CNAME` later.
- **Release tagging**: deferred until MVP works end-to-end on real hardware. Bootstrap pinned to `main` branch tarball.
- **Whiptail vs plain prompts**: whiptail chosen. Available across Fedora (`newt` package), Debian, Ubuntu, Pop!_OS (`whiptail` package). Bootstrap installs the right package before showing the menu, so we don't depend on it being preinstalled.
- **Curl vs wget on landing page**: ship both one-liners. Some Debian-family minimal installs lack curl; some have only wget. Modern Fedora Workstation has curl by default.
- **Memory system**: project-specific knowledge goes in CLAUDE.md, not in any agent's local memory. Confirmed with user.

- **FaceTime HD camera not working after install (`install_facetimehd`)**: three compounding problems. (1) `dkms autoinstall` was never called after installing `facetimehd-dkms`, so the kernel module was not built for the running kernel — only for the next boot if DKMS ran automatically. (2) The `facetimehd-firmware` RPM's `%post` scriptlet downloads the firmware binary from Apple's CDN; if that network request fails the firmware is silently missing and the camera shows "No Camera Found" even if the module loads. Fixed by checking `/usr/lib/firmware/facetimehd/firmware.bin` after install and looking for any packaged re-download helper, then warning explicitly with the manual URL if firmware is still absent. (3) There was no `/etc/modules-load.d/facetimehd.conf` entry, so even a successfully loaded module would not persist across reboots. All three gaps now addressed.

### Known issues / to verify on real hardware

- End-to-end run on a clean MBA7,2 + Fedora 44 install has not yet happened. Manual test checklist lives in CLAUDE.md §7.
- Akmod build for Broadcom WiFi sometimes reports spurious errors but the module builds on next boot. We treat the `akmods --force` exit code as a warning. Verify on real hardware.
- FaceTime HD camera (`facetimehd-dkms`) availability via COPR varies per Fedora release; the original script defaults this OFF for that reason. Preserved in `extras.sh`.
