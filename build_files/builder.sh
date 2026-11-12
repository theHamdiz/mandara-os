#!/usr/bin/bash
# Stage 1 of the Containerfile: everything that is compiled or downloaded
# rather than installed from Fedora's repositories lands in /out, which the
# final stage copies over its root.
set -euo pipefail

: "${TARGETARCH:?set by podman build --platform}"
: "${MANDARA_VERSION:=latest}" "${MANGO_VERSION:=latest}" "${SCENEFX_VERSION:=0.5}"

OUT=/out
WORK=$(mktemp -d)

case "$TARGETARCH" in
amd64)
	ARCH=x86_64
	CPU_FLAGS="-march=x86-64-v3"
	# Mandara's x86-64-v3 build matches the rest of the image.
	MANDARA_TRIPLE=x86_64-linux-gnu-x86-64-v3
	;;
arm64)
	ARCH=aarch64
	CPU_FLAGS="-mcpu=generic+crypto+crc"
	MANDARA_TRIPLE=aarch64-linux-gnu
	;;
*)
	echo "unsupported architecture: $TARGETARCH" >&2
	exit 1
	;;
esac

dnf5 -y --setopt=install_weak_deps=False install \
	clang lld meson ninja-build git-core curl unzip xz tar \
	pkgconf-pkg-config wayland-devel wayland-protocols-devel \
	'pkgconfig(wlroots-0.20)' libdrm-devel libxkbcommon-devel pixman-devel \
	libinput-devel libseat-devel pcre2-devel cjson-devel pango-devel cairo-devel \
	'pkgconfig(glesv2)' 'pkgconfig(egl)' 'pkgconfig(gbm)' egl-wayland-devel \
	vulkan-loader-devel xcb-util-wm-devel libxcb-devel \
	xorg-x11-server-Xwayland-devel hwdata-devel lcms2-devel libdisplay-info-devel \
	libliftoff-devel

export CC=clang CXX=clang++
export CFLAGS="-O3 ${CPU_FLAGS} -flto=thin -fno-plt"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-fuse-ld=lld -flto=thin"

# The tag behind a project's "latest release" (a redirect, no API quota).
latest_tag() {
	local url
	url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest")
	echo "${url##*/tag/}"
}

fetch() {
	curl -fsSL --retry 5 --retry-all-errors --create-dirs -o "$2" "$1"
}

meson_build() {
	local src=$1
	meson setup "$src/build" "$src" --prefix=/usr --buildtype=release \
		-Db_lto=true -Db_lto_mode=thin "${@:2}"
	ninja -C "$src/build"
	# Into the builder (for the next build) and into the image.
	meson install -C "$src/build" --quiet
	DESTDIR="$OUT" meson install -C "$src/build" --quiet
}

# --- scenefx + MangoWM ------------------------------------------------------
git clone --depth 1 --branch "$SCENEFX_VERSION" https://github.com/wlrfx/scenefx "$WORK/scenefx"
meson_build "$WORK/scenefx" -Dexamples=false

if [ "$MANGO_VERSION" = latest ]; then
	MANGO_VERSION=$(latest_tag mangowm/mango)
fi
git clone --depth 1 --branch "$MANGO_VERSION" https://github.com/mangowm/mango "$WORK/mango"
meson_build "$WORK/mango"

# --- Mandara (the signed release build) -----------------------------------
if [ "$MANDARA_VERSION" = latest ]; then
	MANDARA_VERSION=$(latest_tag theHamdiz/mandara)
fi
MANDARA_VERSION=${MANDARA_VERSION#v}
release="https://github.com/theHamdiz/mandara/releases/download/v$MANDARA_VERSION"
tarball="mandara-$MANDARA_TRIPLE.tar.gz"
fetch "$release/$tarball" "$WORK/$tarball"
fetch "$release/SHA256SUMS" "$WORK/SHA256SUMS"
(cd "$WORK" && grep -E "  $tarball\$" SHA256SUMS | sha256sum -c -)

mkdir "$WORK/mandara"
tar -xzf "$WORK/$tarball" -C "$WORK/mandara" --strip-components=1
# The golden copy; /usr/bin/mandara runs a self-updatable copy of it.
install -Dm755 "$WORK/mandara/bin/mandara" "$OUT/usr/lib/mandara/mandara-bin"
echo "$MANDARA_VERSION" >"$OUT/usr/lib/mandara/VERSION"
install -Dm644 "$WORK/mandara/share/pam.d/mandara-lock" "$OUT/etc/pam.d/mandara-lock"
rm -r "$WORK/mandara/share/pam.d"
mkdir -p "$OUT/usr/share"
cp -r "$WORK/mandara/share/." "$OUT/usr/share/"
install -Dm644 -t "$OUT/usr/share/licenses/mandara" "$WORK/mandara/LICENSE.md" "$WORK/mandara/COPYRIGHT.md"

# --- Rust CLI tools Fedora doesn't package (musl builds, both arches) ------
# install_release REPO TAG ASSET BINARY... : unpack ASSET and install BINARY.
install_release() {
	local repo=$1 tag=$2 asset=$3 dir
	shift 3
	dir=$(mktemp -d)
	fetch "https://github.com/$repo/releases/download/$tag/$asset" "$dir/$asset"
	mkdir "$dir/x"
	case "$asset" in
	*.zip) unzip -q "$dir/$asset" -d "$dir/x" ;;
	*) tar -xf "$dir/$asset" -C "$dir/x" ;;
	esac
	for bin in "$@"; do
		install -Dm755 "$(find "$dir/x" -type f -name "$bin" -print -quit)" "$OUT/usr/bin/$bin"
	done
	rm -rf "$dir"
}

musl="$ARCH-unknown-linux-musl"
t=$(latest_tag starship/starship) && install_release starship/starship "$t" "starship-$musl.tar.gz" starship
t=$(latest_tag sxyazi/yazi) && install_release sxyazi/yazi "$t" "yazi-$musl.zip" yazi ya
t=$(latest_tag zellij-org/zellij) && install_release zellij-org/zellij "$t" "zellij-$musl.tar.gz" zellij
t=$(latest_tag ClementTsang/bottom) && install_release ClementTsang/bottom "$t" "bottom_$musl.tar.gz" btm
t=$(latest_tag imsnif/bandwhich) && install_release imsnif/bandwhich "$t" "bandwhich-$t-$musl.tar.gz" bandwhich
t=$(latest_tag chmln/sd) && install_release chmln/sd "$t" "sd-$t-$musl.tar.gz" sd
t=$(latest_tag ducaale/xh) && install_release ducaale/xh "$t" "xh-$t-$musl.tar.gz" xh
t=$(latest_tag dalance/procs) && install_release dalance/procs "$t" "procs-$t-$ARCH-linux.zip" procs
t=$(latest_tag nextest-rs/nextest) && install_release nextest-rs/nextest "$t" "$t-$musl.tar.gz" cargo-nextest

# --- Cursor and fonts ------------------------------------------------------
t=$(latest_tag ful1e5/Bibata_Cursor)
fetch "https://github.com/ful1e5/Bibata_Cursor/releases/download/$t/Bibata-Modern-Classic.tar.xz" "$WORK/bibata.tar.xz"
mkdir -p "$OUT/usr/share/icons"
tar -xJf "$WORK/bibata.tar.xz" -C "$OUT/usr/share/icons"

fonts="https://github.com/google/fonts/raw/main/ofl"
fetch "$fonts/alexandria/Alexandria%5Bwght%5D.ttf" "$OUT/usr/share/fonts/mandara/Alexandria[wght].ttf"
fetch "$fonts/cairo/Cairo%5Bslnt,wght%5D.ttf" "$OUT/usr/share/fonts/mandara/Cairo[slnt,wght].ttf"
fetch "$fonts/alexandria/OFL.txt" "$OUT/usr/share/licenses/mandara-fonts/Alexandria-OFL.txt"
fetch "$fonts/cairo/OFL.txt" "$OUT/usr/share/licenses/mandara-fonts/Cairo-OFL.txt"

echo "mandara $MANDARA_VERSION, mango $MANGO_VERSION, scenefx $SCENEFX_VERSION" >"$OUT/usr/lib/mandara/BUILD"
rm -rf "$WORK"
