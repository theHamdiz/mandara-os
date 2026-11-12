#!/usr/bin/bash
# Stage 2 of the Containerfile: packages, kernel, services and the initramfs.
# The builder's /out and system_files/ are already copied over the root.
set -euo pipefail

: "${TARGETARCH:?set by podman build --platform}"

# Every install skips weak dependencies: nothing comes in that wasn't asked for.
install() {
	dnf5 -y --setopt=install_weak_deps=False install "$@"
}

install dnf5-plugins
dnf5 -y copr enable scottames/ghostty
dnf5 -y copr enable imput/helium

# --- Kernel ----------------------------------------------------------------
if [ "$TARGETARCH" = amd64 ]; then
	dnf5 -y copr enable bieszczaders/kernel-cachyos-lto
	dnf5 -y copr enable bieszczaders/kernel-cachyos-addons

	# The kernel's install hooks try to build an initramfs and talk to
	# rpm-ostree inside the build; the initramfs is made below instead.
	hooks=/usr/lib/kernel/install.d
	for hook in 05-rpmostree.install 50-dracut.install; do
		if [ -e "$hooks/$hook" ]; then
			mv "$hooks/$hook" "$hooks/$hook.bak"
			printf '#!/bin/sh\nexit 0\n' >"$hooks/$hook"
			chmod +x "$hooks/$hook"
		fi
	done

	rpm -e --nodeps kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra || true
	rm -rf /usr/lib/modules/*
	# cachyos-ksm-settings is what the uksmd package became: KSM for login sessions.
	install kernel-cachyos-lto kernel-cachyos-lto-devel-matched scx-scheds scx-tools cachyos-ksm-settings

	for hook in 05-rpmostree.install 50-dracut.install; do
		if [ -e "$hooks/$hook.bak" ]; then
			mv -f "$hooks/$hook.bak" "$hooks/$hook"
		fi
	done
	# bootc boots the kernel in /usr/lib/modules; the package's /boot copies stay out.
	find /boot -mindepth 1 -delete
	systemctl enable scx_loader.service
else
	# No CachyOS or sched-ext builds for aarch64: Fedora's kernel stays,
	# and so does the scx_loader config (unused there).
	rm -rf /etc/scx_loader
fi

# --- Packages --------------------------------------------------------------
packages=(
	# Desktop: MangoWM's runtime, Mandara's runtime and services, the login screen.
	wlroots cjson pango libinput libxkbcommon pixman pcre2 xcb-util-wm
	xorg-x11-server-Xwayland wayland-utils wlr-randr wl-clipboard slurp
	xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk xdg-utils
	vulkan-loader mesa-vulkan-drivers mesa-dri-drivers fontconfig freetype
	pipewire pipewire-pulseaudio wireplumber seatd greetd cage polkit
	NetworkManager NetworkManager-openvpn NetworkManager-wifi bluez
	accountsservice geoclue2 sound-theme-freedesktop udisks2 upower
	power-profiles-daemon i2c-tools gnome-keyring gnome-keyring-pam fwupd
	plymouth plymouth-plugin-script plymouth-plugin-label btrfs-progs
	papirus-icon-theme
	# Fonts: Latin, Arabic and every other script Mandara is translated into.
	rsms-inter-vf-fonts jetbrains-mono-fonts-all google-noto-color-emoji-fonts
	google-noto-sans-fonts google-noto-sans-arabic-fonts google-noto-sans-devanagari-fonts
	google-noto-sans-bengali-fonts google-noto-sans-telugu-fonts google-noto-sans-cjk-fonts
	# The four apps. Nautilus extracts and compresses archives itself
	# (gnome-autoar, libarchive); ouch covers the terminal.
	ghostty helium-bin nautilus gvfs gvfs-mtp gvfs-smb celluloid
	# Virtual machine guests (each one starts only on its own hypervisor).
	qemu-guest-agent spice-vdagent open-vm-tools-desktop
	# Developer toolchain.
	git git-lfs gh clang lld lldb gcc gcc-c++ cmake meson ninja-build make
	pkgconf-pkg-config openssl-devel jq curl wget unzip zstd strace perf bpftool
	podman podman-compose skopeo buildah moby-engine docker-buildx docker-compose
	rustup fish
	# Rust command-line tools packaged by Fedora (the rest come from stage 1).
	ripgrep bat fd-find helix git-delta zoxide hyperfine atuin just gitui eza
	tokei du-dust
)
if [ "$TARGETARCH" = amd64 ]; then
	packages+=(virtualbox-guest-additions)
else
	# Universal Blue's full ffmpeg (x86_64) decodes H.264 itself. Fedora's
	# ffmpeg-free (aarch64) only decodes it through OpenH264: ask for Cisco's
	# real library so the noopenh264 stub isn't picked for Celluloid's mpv.
	packages+=(openh264)
fi

# Helium installs into /opt, which bootc keeps in /var: install it into a real
# /opt, then move it under /usr so image updates replace it.
if [ -L /opt ]; then
	rm /opt
	mkdir /opt
fi
install "${packages[@]}"
mv /opt/helium /usr/lib/helium
ln -sf /usr/lib/helium/helium-wrapper /usr/bin/helium
rmdir /opt 2>/dev/null || rm -rf /opt
ln -s -T var/opt /opt
mkdir -p /var/opt /var/roothome
# /usr/local is already /var/usrlocal on bootc bases: writable for local installs.
test -L /usr/local

# --- Rust: a stable toolchain seeded into each home on first use -----------
export RUSTUP_HOME=/usr/share/rustup-seed/rustup CARGO_HOME=/usr/share/rustup-seed/cargo
rustup-init -y --no-modify-path --profile minimal --default-toolchain stable \
	--component clippy,rustfmt,rust-analyzer,rust-src
rm -rf "$RUSTUP_HOME/downloads" "$RUSTUP_HOME/tmp"
unset RUSTUP_HOME CARGO_HOME

# --- Login screen ------------------------------------------------------------
# Mandara Login's media folders; its stills are the bundled wallpapers.
mkdir -p /usr/share/mandara/login/videos /usr/share/mandara/login/backgrounds
for wallpaper in /usr/share/backgrounds/mandara/*; do
	ln -sf "$wallpaper" /usr/share/mandara/login/backgrounds/
done

# --- Fonts -----------------------------------------------------------------
fc-cache -f

# --- ujust ----------------------------------------------------------------
# Universal Blue's ujust reads /usr/share/ublue-os/just/60-custom.just; on
# Fedora's own base there is no ujust, so a small one runs these recipes.
if [ ! -x /usr/bin/ujust ]; then
	cat >/usr/bin/ujust <<'EOF'
#!/usr/bin/sh
exec just --justfile /usr/share/ublue-os/just/60-custom.just --working-directory "$HOME" "$@"
EOF
	chmod 0755 /usr/bin/ujust
fi

# --- Services --------------------------------------------------------------
systemctl mask cups.service cups.socket cups.path ModemManager.service \
	avahi-daemon.service avahi-daemon.socket
systemctl enable greetd.service NetworkManager.service bluetooth.service \
	power-profiles-daemon.service fwupd-refresh.timer
systemctl enable mandara-btrfs-compress.service mandara-expire-default-password.service
systemctl enable qemu-guest-agent.service spice-vdagentd.socket vmtoolsd.service
if [ "$TARGETARCH" = amd64 ]; then
	systemctl enable vboxservice.service
fi
# Docker stays off until `ujust mandara-enable-docker`; rootless Podman's API
# socket starts with each session.
systemctl disable docker.service docker.socket 2>/dev/null || true
systemctl --global enable podman.socket
systemctl set-default graphical.target

# --- Boot splash and initramfs ---------------------------------------------
plymouth-set-default-theme mandara-preloader
kernels=$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
if [ "$(printf '%s\n' "$kernels" | wc -l)" -ne 1 ]; then
	echo "expected exactly one kernel, found: $kernels" >&2
	exit 1
fi
kver=$kernels
dracut --no-hostonly --kver "$kver" --reproducible -v --add "ostree btrfs plymouth" \
	-f "/usr/lib/modules/$kver/initramfs.img"
chmod 0600 "/usr/lib/modules/$kver/initramfs.img"

# --- Checks ----------------------------------------------------------------
# Every library MangoWM and Mandara link against is present.
for bin in /usr/bin/mango /usr/bin/mmsg /usr/lib/mandara/mandara-bin; do
	if ldd "$bin" | grep -q 'not found'; then
		ldd "$bin" >&2
		exit 1
	fi
done
# The default MangoWM config parses (`-p` only checks it).
XDG_RUNTIME_DIR=$(mktemp -d) mango -c /etc/mango/config.conf -p
/usr/lib/mandara/mandara-bin --version
ujust --list | grep -q mandara-reset-shell

# --- Clean up --------------------------------------------------------------
for repo in /etc/yum.repos.d/_copr*.repo; do
	sed -i 's/^enabled=1/enabled=0/' "$repo"
done
# /var/cache/libdnf5 is the build's package cache mount; the rest goes.
find /var/cache -mindepth 1 -maxdepth 1 ! -name libdnf5 -exec rm -rf {} +
rm -rf /var/log/* /var/lib/dnf /tmp/* /root/.cache
