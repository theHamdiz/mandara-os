# Contributing to Mandara OS

This is the guide for everyone who works on Mandara OS, people and AI coding
agents alike: what the project is, how the repository is laid out, how to
build and check a change, the rules every change follows, and how to add the
common kinds of things.

## What Mandara OS is

Mandara OS is a **Linux distribution**: a bootable, image-based Fedora
desktop operating system tuned for software development and everyday
personal use. It is published as a bootc container image
(`ghcr.io/thehamdiz/mandara-os`) plus installer ISOs and ready-made virtual
machine disks, for x86_64 and aarch64.

It is not a theme or a dotfiles bundle on top of someone else's desktop. The
image decides the whole system:

- **The kernel and scheduler.** On x86_64 the CachyOS LTO kernel replaces
  Fedora's, with sched-ext's `scx_lavd` scheduler in performance mode, KSM
  for login sessions, and low-latency boot arguments (`preempt=full`,
  `threadirqs`, no watchdogs) in `bootc` kargs.
- **The system tuning.** sysctl (BBR, fq, swappiness, map count), Btrfs with
  zstd:1 compression, masked idle services, guest agents that start only on
  their own hypervisor, and no weak dependencies anywhere.
- **The compositor.** MangoWM and scenefx are compiled from source with
  clang, `-O3` and ThinLTO for a fixed baseline: x86-64-v3, or ARMv8 with
  crypto and CRC.
- **The desktop.** [Mandara Shell](https://github.com/theHamdiz/mandara) is
  the shell, the login screen (greetd) and the lock screen, with a Plymouth
  boot splash, fonts, icons, cursor and wallpapers chosen to match.
- **The developer toolchain.** C/C++ and Rust compilers, Podman and Docker,
  git and gh, 23 Rust command-line tools, and a stable Rust toolchain seeded
  into each home on first use.
- **The update model.** Atomic image updates and rollbacks with `bootc`;
  Mandara updates itself in place without root.

A new image is built **only** when Mandara Shell publishes a release.

## Repository map

| Path | What lives there |
|---|---|
| `Containerfile` | Two stages. `builder` (Fedora) compiles scenefx and MangoWM and downloads everything that isn't a Fedora package into `/out`. The final stage starts from the base image, copies `/out` and `system_files/`, and runs `build_files/build.sh`, then `bootc container lint`. |
| `build_files/builder.sh` | Stage 1: compiler flags per architecture, the scenefx and MangoWM builds, the Mandara release (checksum-verified), musl release builds of the Rust tools Fedora lacks, Bibata, Alexandria and Cairo. |
| `build_files/build.sh` | Stage 2: COPRs, the kernel swap, packages, Helium's move out of `/opt`, the Rust seed, services, the Plymouth theme, the initramfs, and build-time checks. |
| `build_files/identity.sh` | Sets Mandara's displayed OS identity from `/usr/lib/mandara/BUILD`, retaining Fedora's package and image-builder compatibility fields. Runs after package installation and before dracut. |
| `build_files/check-fonts.sh` | Checks the actual fontconfig matches for Arabic, mixed text, Latin and monospace, during the image build. |
| `tests/` | Regression tests for OS identity, installer labels, typography defaults and tmpfiles state creation. Run with Python's standard-library unittest runner. |
| `system_files/` | Copied over `/` as is: greetd, MangoWM defaults, `/etc/skel` (shells, git, GTK, Mandara config, wallpapers), sysctl, fontconfig, kargs, tmpfiles, systemd units and drop-ins, the Plymouth theme, the `/usr/bin/mandara` launcher and the ujust recipes. |
| `disk_config/` | bootc-image-builder settings: `disk.toml` for the qcow2, vmdk and raw disks, `iso.toml` for the installer. |
| `download.sh` | The README's one-line download: picks the architecture, fetches a release's parts in parallel (resuming), joins them, checks the SHA-256 and unpacks disks. POSIX `sh`, needs `curl` (and `zstd` for disks); all of it runs from `main()` on its last line, so a cut-off `curl \| sh` runs nothing. |
| `assets/` | The README's emblem and wallpaper previews. |
| `.github/workflows/build-os.yml` | Builds and publishes the image (only on Mandara's dispatch). |
| `.github/workflows/build-disks.yml` | Turns the published image into the downloads (called by `build-os.yml`, or run by hand for a version). |
| `.github/workflows/lint.yml` | The only pull-request check: shellcheck, TOML and fontconfig. |

## How a release flows

1. Mandara Shell's Release workflow publishes `vX.Y.Z`.
2. Its `.github/workflows/mandara-os.yml` sends this repository a
   `repository_dispatch` of type `mandara-shell-updated` with
   `client_payload.version = "X.Y.Z"` (secret `OS_TRIGGER_PAT`).
3. `build-os.yml` checks that the release's `SHA256SUMS` exists, builds both
   architectures on native runners (`ubuntu-24.04`, `ubuntu-24.04-arm`),
   pushes `:X.Y.Z-amd64` and `:X.Y.Z-arm64`, publishes the multi-arch
   `:X.Y.Z`, signs it with cosign, and a serialized job points `:latest` at
   the highest version tag.
4. It then calls `build-disks.yml` with that exact digest, which runs
   bootc-image-builder (Btrfs root) and attaches the ISO, qcow2, vmdk and raw
   files to the GitHub release `vX.Y.Z` here.

## Build and check

```bash
# The image, locally (nothing is pushed). aarch64: --platform linux/arm64
# and BASE_IMAGE=quay.io/fedora/fedora-bootc:45.
podman build --platform linux/amd64 --cap-add=SYS_ADMIN \
  --build-arg BASE_IMAGE=ghcr.io/ublue-os/base-main:45 \
  --build-arg MANDARA_VERSION=0.28.0 -t mandara-os .

# What CI checks on a pull request (.github/workflows/lint.yml).
podman run --rm -v "$PWD:/mnt:Z" -w /mnt docker.io/koalaman/shellcheck:stable \
  --shell=bash build_files/*.sh
podman run --rm -v "$PWD:/mnt:Z" -w /mnt docker.io/koalaman/shellcheck:stable \
  --shell=sh download.sh system_files/usr/bin/mandara \
  system_files/usr/libexec/mandara-os/rustup-seed system_files/etc/profile.d/*.sh
python3 -c 'import pathlib, tomllib; [tomllib.loads(f.read_text()) for d in ("disk_config", "system_files") for f in pathlib.Path(d).rglob("*.toml")]'
xmllint --noout system_files/etc/fonts/conf.d/*.conf
python3 -m unittest discover -s tests -v

# Session logging integration, in a locally built disposable image.
podman run --rm -v "$PWD:/repo:ro" -w /repo --entrypoint /usr/bin/python3 \
  localhost/mandara-os tests/integration/session_logging.py

# Also worth running on workflow changes (not in CI).
podman run --rm -v "$PWD:/repo:Z" -w /repo docker.io/rhysd/actionlint:latest

# MangoWM's own checker on the default config.
XDG_RUNTIME_DIR=$(mktemp -d) mango -c system_files/etc/mango/config.conf -p
```

The image build runs its own checks before it finishes: `ldd` on `mango`,
`mmsg` and Mandara, `mango -p` on the default config, `mandara --version`,
`ujust --list`, resolved fontconfig faces, the Mandara GRUB drop-in's syntax,
and `bootc container lint --fatal-warnings`. Inspect a built image with
`podman run --rm localhost/mandara-os <command>`, for example
`systemctl is-enabled greetd`.

## Hard rules

1. **Only a Mandara release builds the OS.** `build-os.yml` keeps one
   trigger, `repository_dispatch: mandara-shell-updated`. Never add `push`,
   `schedule`, `pull_request` or `workflow_dispatch` builds of the image.
   Pull requests are only linted.
2. **Zero bloat.** Every `dnf5 install` goes through `install` in
   `build.sh` (`--setopt=install_weak_deps=False`). A new package needs a
   reason. A new service must cost nothing while idle (socket- or
   condition-activated) or be off by default with a ujust recipe to turn it
   on.
3. **Facts about Mandara come from Mandara's code.** The greetd command
   (`cage -s -m last -- … greeter`), the MangoWM include line
   (`source_optional=~/.config/mandara/generated/mango.conf`), the
   self-update path (`current_exe()`), config keys and default keybinds are
   read from [theHamdiz/mandara](https://github.com/theHamdiz/mandara)
   before they're wired here. Never guess one.
4. **MangoWM config passes MangoWM's checker.** Every line in
   `system_files/etc/mango/config.conf` passes `mango -p`. A bind that
   collides with one of Mandara's defaults wins over it (Mandara skips its
   own and reports it), so take a Mandara chord only on purpose.
5. **The image owns `/usr`, the user owns `/var` and `/etc`.** Nothing is
   shipped in `/var` or `/opt` (bootc doesn't update them): create runtime
   folders with `tmpfiles.d` and move software installed into `/opt` under
   `/usr/lib`. Per-user defaults go in `/etc/skel`.
6. **Both architectures, or a reason.** A change works on x86_64 and
   aarch64, or is gated on `TARGETARCH` with a comment saying why (as the
   CachyOS kernel, scx and KSM are).
7. **Verify before claiming.** Build the image, or the stage you changed,
   before saying it works. Performance or size figures in the docs come from
   measured builds, rounded, never guessed.
8. **Every change goes through a pull request** with Conventional Commits
   (`feat:`, `fix:`, `docs:`, `ci:`…). Read every CodeRabbit comment and its
   review summary, fix the valid ones, and explain the rest in the thread.
9. **No secrets in the repository.** Signing keys, tokens and passwords stay
   in GitHub secrets. The only shipped password is the ready-made disks'
   public `mandara` one; the docs tell people to change it with `passwd`.

## How to add things

**A Fedora package.** Add it to the `packages` list in `build.sh` in the
group it belongs to. Architecture-only packages go in the
`if [ "$TARGETARCH" = amd64 ]` block below the list.

**A command-line tool Fedora lacks.** Add an `install_release` line to
`builder.sh`: the repository, its latest tag, the musl asset name and the
binaries to install. It must publish both `x86_64` and `aarch64` builds.

**A default setting for new accounts.** Put the file under
`system_files/etc/skel/`. For Mandara, add only the keys you need to
`~/.config/mandara/config.toml`: every Mandara table has defaults, so a
partial file is safe.

**A kernel argument.** Add it to `system_files/usr/lib/bootc/kargs.d/`
(`match-architectures` for architecture-specific ones).

**A systemd unit.** Put it under `system_files/usr/lib/systemd/system/` and
enable it in `build.sh`. A first-boot or one-shot unit records that it ran
with a marker under `/var/lib/mandara-os/`.

**A ujust recipe.** Add it to
`system_files/usr/share/ublue-os/just/60-custom.just`. Recipes that need root
call `sudo` themselves.

## Gotchas

- **Brand after installing packages, before dracut.** Fedora's release RPM
  owns `/usr/lib/os-release`; `identity.sh` changes its display fields only
  after package installation. `ID=fedora`, numeric `VERSION_ID`, the Fedora
  CPE and support date stay intact. `IMAGE_ID=mandara-os` and `IMAGE_VERSION`
  identify the image. `/etc/os-release` links to the image-owned file;
  `/etc/system-release` and `/etc/redhat-release` link to `mandara-release`,
  which also gives bootupd the firmware boot-entry name. dracut then copies
  the branded release into the initramfs.
- **bootupd uses static GRUB drop-ins.** Put installed-menu defaults in
  `/usr/lib/bootupd/grub2-static/configs.d/`, before `10_blscfg.cfg`.
  `/etc/default/grub` does not configure this path. BLS reads the displayed
  OS name; keep its deployment and rollback entries. The installer ISO is
  separate: `customizations.iso.volume_id` in `iso.toml` sets its label
  (`$arch` is expanded by bootc-image-builder). Anaconda uses `NAME` and
  the Fedora `VERSION_ID` for its product and version.
- **Font defaults respect user preferences.** The `52-mandara` fontconfig
  rule selects Alexandria after per-user preferences, before Fedora adds
  Noto aliases. Remove Cantarell's early GNOME `system-ui` aliases so they
  cannot preempt those preferences. `60-mandara` supplies Latin and
  mixed-script fallbacks.
  Keep explicit family choices intact and test `fc-match`, including
  `lang=ar-eg`, Arabic glyph coverage and Latin monospace. GTK and Mandara
  defaults in `/etc/skel`, and `/etc/mandara/greeter.toml`, select Alexandria
  explicitly too.
- **No package state in the image.** `mandara-package-state.conf` recreates
  the greeter's portal mask and package state directories through tmpfiles.
  Remove their package-created copies, kernel RPM transaction state and
  build-only `/run` content before the final warning-fatal bootc lint.
  Fedora bootc also needs `mandara-fedora-state.conf`; Universal Blue already
  has these entries in `rpm-ostree-autovar.conf`, so drop the extra file there.
- **One Fedora release everywhere.** `FEDORA_VERSION` must match between the
  builder and the base image: MangoWM links against the builder's wlroots
  and scenefx.
- **Universal Blue's `base-main` is x86_64-only.** aarch64 builds on
  `quay.io/fedora/fedora-bootc` with the same Fedora release. It has no ujust
  (`build.sh` adds a small one) and no RPM Fusion codecs.
- **CachyOS COPRs are x86_64-only.** The kernel, scx and KSM settings are
  gated on `amd64`. The `uksmd` package is now `cachyos-ksm-settings`.
- **Kernel install hooks.** The swap disables `05-rpmostree` and
  `50-dracut` while installing, empties `/boot`, and rebuilds the initramfs
  with `dracut --add "ostree btrfs plymouth"`. Exactly one directory may be
  left in `/usr/lib/modules`.
- **`/opt` is `/var/opt`.** Helium installs into `/opt/helium`, so
  `build.sh` installs it into a real `/opt`, moves it to `/usr/lib/helium`
  and points `/usr/bin/helium` there.
- **Mandara's self-update.** `/usr/bin/mandara` seeds
  `/var/lib/mandara/bin/mandara` (2775 root:wheel) from
  `/usr/lib/mandara/mandara-bin` and runs it, so Mandara's updater (which
  follows `/proc/self/exe`) can patch it without root. The login screen runs
  the image's copy directly.
- **Never hold back `plymouth-quit`.** Fedora's `greetd.service` waits for
  `plymouth-quit-wait.service`, which waits for the splash to quit: a
  `Conflicts=plymouth-quit.service` on greetd deadlocks the boot. The splash
  stays up into the login screen through `plymouth quit --retain-splash`
  (a drop-in on `plymouth-quit.service`).
- **Keep the boot quiet without discarding diagnostics.** Boot verbosity is
  separate from performance tuning in `12-mandara-quiet-boot.toml`.
  `systemd.show_status=error` shows failures without switching to routine
  progress during a slow boot. The kernel prints levels strictly below
  `loglevel`, so use 4 to include errors (level 3). Do not disable error
  status or redirect graphical-session output to `/dev/null`.
- **greetd attaches session output to its VT.** A service-level journal
  setting does not redirect the session's own stdout/stderr. The greeter
  command and Mango session entry use `systemd-cat` to retain both streams
  under `mandara-greeter` and `mandara-session`. It execs the child, keeping
  stdin, environment, PID and exit status. The container-only integration
  test checks these properties against a private journal stream peer.
- **Btrfs options go through `/var`.** On bootc `/sysroot` is mounted
  read-only, and remounting it fails with "mount point is busy"; `/var` is a
  writable mount of the same file system, so file-system-wide options such
  as `compress=zstd:1` are set by remounting `/var`.
- **Never expire a password the login screen must accept.** Fedora's greetd
  (0.10.3) can't change an expired password: when PAM answers "new password
  required" it ends the login, which Mandara Login shows as a wrong
  password. Expiring the ready-made disks' `mandara` password on first boot
  locked everyone out. (greetd's development branch handles it; revisit when
  Fedora ships a release that does.) `mandara-unexpire-default-password`
  repairs disks that booted that image, once, and only while the password
  is still in the forced-change state.

## Keep the docs in sync

A change a user would notice updates [README.md](README.md) in the same pull
request. A change to the build, the rules or the layout updates this file.
Keep [llms.txt](llms.txt) and [CITATION.cff](CITATION.cff) true when the
facts they state change.
