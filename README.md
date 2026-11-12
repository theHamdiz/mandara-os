# Mandara OS

A bootable, image-based Fedora system built around
[Mandara Shell](https://github.com/theHamdiz/mandara) and
[MangoWM](https://github.com/mangowm/mango), for x86_64 and aarch64. Every
Mandara release builds a new image; installed systems pick it up with a normal
`bootc upgrade`.

## What's inside

- **Desktop:** MangoWM with scenefx effects (blur, shadows, rounded corners),
  built from source with clang and ThinLTO, and Mandara Shell with its login
  screen and lock screen. The theme is Mandara Corniche, with six bundled
  wallpapers in rotation, Papirus-Dark icons and the Bibata Modern Classic
  cursor.
- **Apps:** Ghostty, Helium and Files (Nautilus). Nothing else.
- **Kernel (x86_64):** CachyOS (LTO) with the `scx_lavd` sched-ext scheduler in
  performance mode, plus `uksmd`. On aarch64 it's Fedora's kernel.
- **Tuned for latency:** full preemption, threaded IRQs, BBR, a quiet boot
  through the Mandara splash, and Btrfs with zstd:1 compression.
- **Developer tools:** git, gh, clang/lld/lldb, gcc, cmake, meson, Podman
  (rootless Docker-compatible API on), Docker Engine (off until you ask), and
  Rust through rustup: a stable toolchain with clippy, rustfmt and
  rust-analyzer, ready offline in your home on first use.
- **Rust command-line tools:** ripgrep, bat, fd, starship, helix, delta,
  zoxide, hyperfine, yazi, zellij, atuin, just, gitui, eza, tokei, bottom,
  bandwhich, dust, procs, sd, xh and cargo-nextest, plus fish.
- **Typography:** Inter, JetBrains Mono, Alexandria and Cairo (Latin and
  Arabic as equals), Noto for every other language Mandara speaks, and colour
  emoji.
- **Virtual machines:** guest agents for QEMU/GNOME Boxes, VMware and (x86_64)
  VirtualBox. Each one starts only on its own hypervisor.

## Downloads

Each [release](https://github.com/theHamdiz/mandara-os/releases) is named after
the Mandara version it's built around, and has these files for `x86_64` and
`aarch64`:

| File | Use it for |
|---|---|
| `mandara-os-<version>-<arch>.iso` | A USB stick (Fedora Media Writer, `dd`), or an installer ISO in any VM |
| `mandara-os-<version>-<arch>.qcow2.zst` | GNOME Boxes, virt-manager, QEMU/KVM, Proxmox |
| `mandara-os-<version>-<arch>.vmdk.zst` | VirtualBox, VMware |
| `mandara-os-<version>-<arch>.raw.zst` | Parallels, UTM, or writing straight to a disk |
| `SHA256SUMS-<arch>` | Checksums |

Files over 2 GiB come in parts: join them with
`cat <file>.part* > <file>`. Decompress disks with `zstd -d`. The ready-made
disks sign in as **mandara** with the password **mandara**, and the first
login asks you to choose a new one. The ISO asks for your own account.

Already on a bootc system (Fedora Atomic, Universal Blue)? Switch to it:

```bash
sudo bootc switch ghcr.io/thehamdiz/mandara-os:latest
```

## Before you install

- **x86_64 needs an x86-64-v3 CPU** (AVX2: Intel Haswell, AMD Zen or newer).
  In a VM, pass the host CPU through ("host-passthrough" / "host").
- **Turn Secure Boot off on x86_64.** The CachyOS kernel isn't signed with a key
  your firmware trusts.
- The bootloader is GRUB, with its menu hidden unless you hold Shift (Esc on
  some machines) to choose an older image. bootc installs only GRUB on Fedora
  today.

## Living with it

| Command | What it does |
|---|---|
| `sudo bootc upgrade` | Fetch and stage the newest image (applies at the next boot) |
| `sudo bootc rollback` | Boot the previous image again |
| `ujust mandara-reset-shell` | Go back to the Mandara version that came with the image |
| `ujust mandara-enable-docker [engine\|podman]` | Turn on Docker Engine, or point `docker` at rootless Podman |
| `ujust mandara-unlock-os` | Make `/usr` writable until the next reboot |

Mandara updates itself in place: **Studio → About → Update now** patches the
copy in `/var/lib/mandara/bin` without root. If an updated Mandara fails to
start, the image's version takes over. A newer image brings a newer Mandara
too.

## How it's built

```
theHamdiz/mandara  Release ──► mandara-os.yml ──repository_dispatch──► build-os.yml ──► build-disks.yml
                   (publish)    (version)        mandara-shell-updated   (image, x86_64  (ISO, qcow2, vmdk,
                                                                          + aarch64)      raw → release)
```

- [`Containerfile`](Containerfile): stage 1 compiles scenefx and MangoWM and
  fetches the Mandara release (checksum-verified), the Rust tools, fonts and
  cursor. Stage 2 is the OS:
  [`build_files/build.sh`](build_files/build.sh) plus
  [`system_files/`](system_files), copied over `/`.
- x86_64 builds on Universal Blue's `base-main` (Fedora with codecs, firmware
  and ujust). aarch64 builds on Fedora's own `fedora-bootc`, because
  `base-main` is x86_64-only.
- **The image builds only when a Mandara release asks for it.** Mandara's
  release pipeline sends the dispatch once the release is published. Pull
  requests here are only linted.
- [`build-os.yml`](.github/workflows/build-os.yml) builds both architectures
  on native runners, pushes `ghcr.io/thehamdiz/mandara-os:<version>` and
  `:latest` as one multi-arch image, and signs it with cosign.
  [`build-disks.yml`](.github/workflows/build-disks.yml) then runs
  bootc-image-builder (Btrfs root) for the downloads.

To build locally (nothing is pushed):

```bash
podman build --platform linux/amd64 --cap-add=SYS_ADMIN \
  --build-arg BASE_IMAGE=ghcr.io/ublue-os/base-main:45 \
  --build-arg MANDARA_VERSION=0.28.0 -t mandara-os .
```

### Setup (maintainers)

1. A fine-grained token with **Contents: Read and write** on
   `theHamdiz/mandara-os`, saved as `OS_TRIGGER_PAT` in `theHamdiz/mandara`.
2. A cosign key pair: `COSIGN_PRIVATE_KEY` and `COSIGN_PASSWORD` in this
   repository, with `cosign.pub` committed. Without them, images are pushed
   unsigned (with a warning).
3. The `mandara-os` package on GHCR set to **public**, so `bootc` can pull it
   without logging in.

## Wallpapers

The six wallpapers in
[`system_files/usr/share/backgrounds/mandara`](system_files/usr/share/backgrounds/mandara)
belong to their artists and are included as Mandara OS's defaults.

## License

[GPL-3.0](LICENSE), like Mandara.
