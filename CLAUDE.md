# CLAUDE.md

Single source of truth for any AI coding agent working on this repo. Read top-to-bottom before making changes. Update this file whenever you change architecture, conventions, or add a target.

> **Important**: project info lives **here**, not in the agent's local memory system. If you learn something durable about this project, write it here, not to `~/.claude/memory/`.

---

## 1. What this project is

A `brew.sh`-inspired one-liner post-install script for Linux running on Apple MacBooks. The user pastes one command into a fresh-installed Linux terminal and the script:

1. Detects the device + distro
2. Installs critical hardware drivers automatically (WiFi, codecs, fn-key fix, etc.)
3. Presents an interactive checklist (whiptail) of "universally-agreed must-haves" — user picks before install
4. Re-execs under `sudo`, runs the install, reports what needs a reboot

**Currently supported**:
- MacBook Air 2017 (`MacBookAir7,2`) + Fedora Workstation 44 (kernel 6.19)
- MacBook Air 2017 (`MacBookAir7,2`) + Debian 13 / Trixie (kernel 6.12 LTS)

**Next**: Ubuntu 24.04 LTS (kernel 6.8). Then more devices (other MBA/MBP models).

---

## 2. The one-liner pattern

Two forms shipped on the landing page (some distros default to `wget`, some to `curl`):

```bash
bash -c "$(curl -fsSL https://nookied.github.io/mac-linux-postinstall/install.sh)"
bash -c "$(wget -qO- https://nookied.github.io/mac-linux-postinstall/install.sh)"
```

**Why `bash -c "$(…)"` instead of `… | bash`**: piping detaches stdin from the terminal, breaking interactive prompts and whiptail. Command substitution puts the script in argv and leaves stdin attached. Do not change this pattern.

**Hosting**: GitHub Pages from `/docs`. The bootstrap **is** `docs/install.sh` — there is no separate `bootstrap.sh` at the repo root. Single source of truth, no drift between dev and shipped versions.

---

## 3. File map

```
mac-linux-postinstall/
├── docs/
│   ├── install.sh                 # Bootstrap — entry point. THE script users curl.
│   └── index.html                 # Landing page (brew.sh-style copy-paste box)
├── lib/                           # Sourced by bootstrap after tarball download
│   ├── common.sh                  # log/warn/err, sudo re-exec, reboot tracking
│   ├── pkg.sh                     # dnf/apt abstraction (install whiptail, etc.)
│   ├── ui.sh                      # whiptail wrappers (checklist, msgbox, yesno)
│   └── detect.sh                  # device + distro → target id resolution
├── targets/
│   ├── macbookair7_2-fedora44/    # MBA7,2 + Fedora 44 (kernel 6.19)
│   │   ├── essentials.sh          # Critical, auto-install (no opt-out)
│   │   └── extras.sh              # Optional, presented via whiptail checklist
│   └── macbookair7_2-debian13/    # MBA7,2 + Debian 13 (kernel 6.12 LTS)
│       ├── essentials.sh
│       └── extras.sh
├── tests/
│   └── qa.sh                      # Automated unit tests (bash, no hardware needed)
├── README.md                      # User-facing only
├── AGENTS.md                      # Pointer to this file
├── CLAUDE.md                      # ← you are here
└── CHANGELOG.md                   # Detailed history of every change/fix/issue
```

---

## 4. How the bootstrap works (execution flow)

```
1. User pastes one-liner
2. docs/install.sh runs as the user (NOT root)
3. Sanity checks: Linux? normal user? curl OR wget? tar? bash?
4. Banner + plain-text "continue? [y/N]" (no whiptail dep yet)
5. Download repo tarball → tempdir, extract with --strip-components=1
6. Source lib/*, detect device + distro → resolve target id (e.g. "macbookair7_2-fedora44")
7. If unsupported target → print friendly message + open issue link, exit **before sudo**
8. sudo -v   (cache credentials, abort if user denies)
9. Install whiptail (newt on Fedora, whiptail on Debian-family) via lib/pkg.sh
10. Source targets/<id>/extras.sh → show whiptail checklist with defaults
11. Write user selections to $tmpdir/selections.env
12. Re-exec the install runner under sudo, passing $tmpdir
13. Runner sources selections.env + essentials.sh + extras.sh (gated by selections)
14. Print summary + reboot reminder if any step appended to $MACLIN_REBOOT_FILE
```

---

## 5. Conventions

### Shell style

- `#!/usr/bin/env bash` everywhere
- `set -euo pipefail` at the top of every script (bootstrap relaxes this only where intentional)
- Functions: `lower_snake_case`. Constants/exported vars: `UPPER_SNAKE_CASE`
- Use `lib/common.sh::log/warn/err` — do not echo raw status messages
- Idempotent steps: every install should be safe to re-run. Use `dnf install -y` (no-op if installed), `flatpak remote-add --if-not-exists`, `systemctl enable --now` (idempotent), guards like `[ -f /etc/modprobe.d/foo.conf ] || …`
- Call `mark_reboot "<short reason>"` (defined in `common.sh`) when a step requires reboot. It appends to `$MACLIN_REBOOT_FILE`; bootstrap reads that file at the end. Reason: env vars don't survive the sudo re-exec boundary, so file-based.

### Target naming

Format: `<device-slug>-<distro><major-version>` — lowercase, underscore for product-name commas, no dots in version.

Examples:
- `macbookair7_2-fedora44`  (`MacBookAir7,2` → `macbookair7_2`)
- `macbookair7_2-debian13`
- `macbookair7_2-ubuntu2404` (planned)
- `macbookpro11_3-ubuntu2404` (future)
- `macbookair7_2-popos2204` (future)

Detection logic in `lib/detect.sh` maps `(DMI product, distro id, distro version)` → target dir name.

### Adding a new target

1. Create `targets/<slug>/{essentials.sh,extras.sh}` (copy nearest existing target as template)
2. Add the case in `lib/detect.sh::detect_target`
3. Add a row to the support matrix in `README.md`
4. Add a CHANGELOG entry under `## [Unreleased]`

### Adding a new step

- **Critical/auto** (driver, codec, distro essential) → `essentials.sh`. No flag, just runs.
- **Optional/preference** (TLP, dev tools, GNOME tweaks) → `extras.sh` as a function `install_<name>` plus a checklist entry in the target's extras manifest

---

## 6. Known gotchas (read these — they bite)

1. **Curl vs wget**: never assume one is present. The landing page offers both. Bootstrap itself uses whichever the user invoked it with — once the bootstrap is running, we know at least one works because that's how it got here.
2. **Stdin under `bash -c "$(curl …)"`**: works for interactive prompts (`read`, whiptail) because stdin stays attached to the terminal. Do **not** refactor to `curl … | bash`.
3. **Sudo re-exec**: bootstrap escalates by writing the install phase to a tempfile and running `sudo bash <tempfile> <tmpdir>`. Doing `sudo bash -c "..."` with multi-line content from a curl-fetched script is fragile.
4. **Whiptail package name differs**: Fedora ships it in `newt`, Debian-family ships it in `whiptail`. `lib/pkg.sh::install_tui` handles this.
5. **GitHub Pages doesn't follow symlinks**: `docs/install.sh` must be a real file, not a symlink to `bootstrap.sh`. That's why bootstrap lives only in `docs/`.
6. **`/sys/class/dmi/id/product_name`** is readable without sudo on Linux — use it instead of `dmidecode` for pre-escalation device detection. Fall back to `dmidecode` only if the sys file is missing.
7. **Akmod build for Broadcom WiFi**: the `akmods --force` step can spuriously report errors but the module usually still builds on next boot. Treat its non-zero exit as a warning, not failure.
8. **FaceTime HD camera** — read this whole entry before touching the camera install path. Multiple compounding gotchas, several discovered the hard way on real hardware:
   - **COPR name**: use `mulderje/facetimehd-kmod`, NOT `mulderje/facetimehd-dkms`. The `-dkms` COPR does not exist (we wasted a real-hardware test discovering this). The `-kmod` variant ships pre-built modules per kernel version, so DO NOT add DKMS-build logic.
   - **Upstream kernel regression on 6.15+** ([patjak/facetimehd#315](https://github.com/patjak/facetimehd/issues/315)): module loads, captures one frame, then the GStreamer/PipeWire pipeline cannot continue. Cheese, GNOME Snapshot, and other GStreamer-based apps freeze on the first frame. Confirmed by multiple users on Arch/Fedora/Ubuntu kernels 6.15 through 6.19+. **No upstream fix as of May 2026.**
   - **Browser-based apps work**: WebRTC capture (Zoom web, Google Meet, Discord web, https://webcamtests.com) bypasses GStreamer and streams live correctly even on affected kernels. We still install the module on 6.15+ kernels — browser apps remain functional, and the upstream may eventually patch this.
   - **Older-kernel distros are unaffected**: Debian 13 (kernel 6.12 LTS) and Ubuntu 24.04 LTS (kernel 6.8) sit *before* the regression window, so the camera streams normally in all apps there.
   - **Firmware blob** at `/usr/lib/firmware/facetimehd/firmware.bin` is downloaded from Apple's CDN by the `facetimehd-firmware` package's `%post` scriptlet — silently fails on network errors. We verify after install and offer the manual extract path.
   - **Sensor calibration files** (`1871_01XX.dat` for MBA 2017, `1771_01XX.dat` for older models) only affect color correction — NOT the freeze. The "Direct firmware load … failed -2" message in dmesg is a red herring for the freeze symptom.
   - **Secure Boot** blocks unsigned kmod modules with no visible error in user-facing apps — we pre-check via `mokutil` and abort cleanly if SB is on.
   - **`/etc/modules-load.d/facetimehd.conf`** must be written so the module persists across reboots.
   - **Never redirect stderr from `dnf copr enable`** — silent failure (e.g. wrong COPR name) is exactly how we shipped the broken first version.
   - References: https://copr.fedorainfracloud.org/coprs/mulderje/facetimehd-kmod/ • https://github.com/patjak/facetimehd/issues/315 • https://github.com/patjak/facetimehd/wiki/Get-Started
9. **`power-profiles-daemon` / `tuned-ppd` vs TLP**: they conflict at the **package level** on Fedora 44. `tuned-ppd` ships dbus files that TLP also owns — `dnf install tlp` will fail with an RPM file-conflict error before writing anything. Fix: stop/disable `tuned-ppd.service`, `dnf remove -y tuned-ppd`, mask `power-profiles-daemon.service`, *then* `dnf install tlp tlp-rdw`. Masking the service alone is not enough.
10. **Tarball extraction path**: GitHub's tarball top-level dir is `<repo>-<branch>/`. Use `tar xz --strip-components=1` to flatten.
11. **Unsupported targets must exit before sudo**: full detection currently requires downloading and sourcing the repo first, but `sudo -v` must stay after target resolution so unsupported machines are never asked for elevated privileges.
12. **Debian apt sources format split**: Debian 13 fresh installs use the new deb822 format at `/etc/apt/sources.list.d/debian.sources`; older systems still use the legacy single-line `/etc/apt/sources.list`. Use `add-apt-repository -c <component>` (from `software-properties-common`) to add components — it handles both formats transparently. Don't `sed` the file directly: you'll only edit one of the two formats and silently miss the other.
13. **Initramfs regen command differs**: Fedora uses `dracut --force`; Debian/Ubuntu use `update-initramfs -u`. The `hid_apple` fnmode change must be followed by a regen, so each target's `essentials.sh` calls the right one. Don't unify these — the binaries are not interchangeable.
14. **Conflicting Broadcom kernel modules on Debian**: `broadcom-sta-dkms` builds the proprietary `wl` module, but several open-source variants (`brcmfmac`, `brcmsmac`, `b43`, `b43legacy`, `bcma`, `ssb`) often grab the device first. After installing `broadcom-sta-dkms`, modprobe-remove all of them before loading `wl`. The Debian target's essentials.sh does this in a loop.
15. **Debian `gnome-extensions-app` is named `gnome-shell-extension-manager`**: trivially different package name from Fedora. Do not assume cross-distro name parity for any GNOME-shell-related packages — always check both repos when adding a new target.

---

## 7. Testing checklist (manual — no CI yet)

Run automated unit tests first (no hardware needed):
```bash
bash tests/qa.sh
```

Then, on a clean MBA7,2 + Fedora 44 install:

- [ ] One-liner downloads and runs without error
- [ ] Detection correctly identifies `macbookair7_2-fedora44`
- [ ] Whiptail menu appears, defaults match `extras.sh` declared defaults
- [ ] Sudo re-exec works (user is prompted for password once)
- [ ] After reboot: `lspci -k | grep -A 3 Network` shows `Kernel driver in use: wl`
- [ ] After reboot: `sensors` shows fan RPM
- [ ] Brightness/volume keys work without `Fn`
- [ ] Re-running the script is idempotent (no duplicate Flathub remote, no re-clone, etc.)
- [ ] (if FaceTime HD selected) `/usr/lib/firmware/facetimehd/firmware.bin` exists after install
- [ ] (if FaceTime HD selected) `cat /etc/modules-load.d/facetimehd.conf` shows `facetimehd`
- [ ] (if TLP selected) `systemctl status tlp` shows active + running; `power-profiles-daemon` is masked

For unsupported targets, also verify the friendly error path:
- [ ] Run on non-Apple Linux box → clean abort with the right message
- [ ] Run on Fedora 43 (or whatever isn't 44) → clean abort

---

## 8. Workflow expectations

- **Ask before every commit and every push.** Do NOT commit or push to `origin/main` without explicit user approval **for that specific change**. One previous "yes" does not authorize the next commit — momentum is not consent. This applies even when the change is small, obviously correct, or feels like an inevitable follow-on. Show the diff or summarize the change, ask, wait. Same rule for closing PRs and deleting branches.
- **Pinned to `main`**: there are no version tags yet. The landing page URL fetches `main`. When we cut releases, switch the bootstrap's tarball URL to the tag.
- **CHANGELOG.md is mandatory**: every PR/commit that changes behavior must add a `## [Unreleased]` entry. We use Keep-a-Changelog format. This is what stops us running in circles.
- **Document issues + fixes in the changelog, not just features**: if you debug something for an hour, the lesson goes in CHANGELOG under `### Fixed` with enough detail that the next agent doesn't repeat the dig.
- **README is user-only**: no architecture, no internals. Keep agent docs out.
- **Don't recreate `fedora-mba-setup.sh`**: its content has been split into `targets/macbookair7_2-fedora44/`. The original was deleted intentionally — see CHANGELOG.

---

## 9. Open / deferred decisions

- Custom domain (e.g. `maclin.sh`): deferred. Currently using `nookied.github.io`. When a domain is added, set `docs/CNAME` and update both this file and README.
- Release tagging: deferred until after MVP works end-to-end.
- CI: GitHub Actions workflow at `.github/workflows/qa.yml` runs `tests/qa.sh` on every push to main and PR. Status badge in README. The runner is `ubuntu-latest`; shellcheck is preinstalled there.
- Telemetry / opt-in usage stats: out of scope, do not add.
