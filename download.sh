#!/bin/sh
# Downloads Mandara OS for this machine: picks the architecture, fetches the
# release's parts in parallel (resuming where it can), joins them, checks the
# SHA-256 and unpacks disk images.
#
#   curl -fsSL https://raw.githubusercontent.com/theHamdiz/mandara-os/main/download.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/theHamdiz/mandara-os/main/download.sh | sh -s -- qcow2
#
# Usage: download.sh [iso|qcow2|vmdk|raw] [--arch x86_64|aarch64]
#                    [--version X.Y.Z] [--dir DIR] [--jobs N] [--keep] [--list]
#
#   iso    installer for a USB stick or any virtual machine (default)
#   qcow2  GNOME Boxes, virt-manager, QEMU/KVM, Proxmox
#   vmdk   VirtualBox, VMware
#   raw    Parallels, UTM, or writing straight to a disk
#
# Everything runs from main(), called on the last line, so a download that is
# cut short runs nothing.

set -eu

REPO=theHamdiz/mandara-os

say() { printf '%s\n' "$*"; }
die() {
	printf 'mandara-os: %s\n' "$*" >&2
	exit 1
}
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is needed: $2"; }

usage() {
	sed -n '9,16p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//' ||
		say "Usage: download.sh [iso|qcow2|vmdk|raw] [--arch x86_64|aarch64] [--version X.Y.Z] [--dir DIR] [--jobs N] [--keep] [--list]"
}

# The release's architecture name for this machine.
detect_arch() {
	case "$(uname -m)" in
	x86_64 | amd64) echo x86_64 ;;
	aarch64 | arm64) echo aarch64 ;;
	*) die "no Mandara OS build for $(uname -m) (x86_64 and aarch64 only)" ;;
	esac
}

# The newest release's version (the tag behind /releases/latest).
latest_version() {
	url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest") ||
		die "can't reach GitHub"
	tag=${url##*/tag/}
	[ "$tag" != "$url" ] || die "no published release yet"
	echo "${tag#v}"
}

sha256_check() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum -c -
	else
		shasum -a 256 -c -
	fi
}

main() {
	format=iso arch="" version="" dir=. jobs=4 keep=false list=false
	while [ $# -gt 0 ]; do
		case "$1" in
		iso | qcow2 | vmdk | raw) format=$1 ;;
		--arch) arch=${2:?--arch needs x86_64 or aarch64}; shift ;;
		--version) version=${2:?--version needs a version}; shift ;;
		--dir) dir=${2:?--dir needs a folder}; shift ;;
		--jobs) jobs=${2:?--jobs needs a number}; shift ;;
		--keep) keep=true ;;
		--list) list=true ;;
		-h | --help) usage; exit 0 ;;
		*) die "unknown option $1 (try --help)" ;;
		esac
		shift
	done
	case "$arch" in
	"") arch=$(detect_arch) ;;
	x86_64 | aarch64) ;;
	*) die "--arch is x86_64 or aarch64" ;;
	esac
	case "$jobs" in '' | *[!0-9]* | 0) die "--jobs is a positive number" ;; esac
	need curl "to download"
	command -v sha256sum >/dev/null 2>&1 || need shasum "to check the download (or sha256sum)"

	[ -n "$version" ] || version=$(latest_version)
	version=${version#v}
	case "$format" in
	iso) file="mandara-os-$version-$arch.iso" ;;
	*) file="mandara-os-$version-$arch.$format.zst" ;;
	esac
	base="https://github.com/$REPO/releases/download/v$version"

	# This release's files: one whole file, or its numbered parts.
	release=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/tags/v$version") ||
		die "no release v$version (see https://github.com/$REPO/releases)"
	parts=$(printf '%s\n' "$release" | sed -n 's/.*"name": *"\([^"]*\)".*/\1/p' |
		grep -E "^$file(\\.part[0-9]+)?\$" | sort || true)
	[ -n "$parts" ] || die "v$version has no $format for $arch"

	say "Mandara OS $version, $arch, $format"
	if [ "$arch" = x86_64 ] && [ -r /proc/cpuinfo ] && ! grep -q -w avx2 /proc/cpuinfo; then
		say "Note: this CPU has no AVX2. Mandara OS on x86_64 needs an x86-64-v3 processor (Intel Haswell, AMD Zen or newer)."
	fi
	if $list; then
		printf '%s\n' "$parts" | sed "s|^|  $base/|"
		exit 0
	fi

	mkdir -p "$dir"
	cd "$dir"
	curl -fsSL -o "SHA256SUMS-$arch" "$base/SHA256SUMS-$arch" || die "can't download SHA256SUMS-$arch"

	if [ -e "$file" ] || [ -e "${file%.zst}" ]; then
		say "$file is already here; checking it."
	else
		# Up to $jobs parts at a time. Each one downloads to <name>.download and
		# gets its name only when complete; a run that was cut short resumes.
		count=$(printf '%s\n' "$parts" | wc -l | tr -d ' ')
		say "Downloading $count file(s), $jobs at a time, into $(pwd)"
		pids="" running=0 failed=false
		for part in $parts; do
			[ -e "$part" ] && continue
			{
				curl -fL --retry 5 --retry-all-errors --retry-delay 3 -C - -s -S \
					-o "$part.download" "$base/$part" && mv "$part.download" "$part"
			} &
			pids="$pids $!"
			running=$((running + 1))
			if [ "$running" -ge "$jobs" ]; then
				for pid in $pids; do wait "$pid" || failed=true; done
				pids="" running=0
			fi
		done
		for pid in $pids; do wait "$pid" || failed=true; done
		$failed && die "a download failed; run the same command again to resume it"

		if [ "$parts" != "$file" ]; then
			say "Joining the parts"
			# shellcheck disable=SC2086 # the part names have no spaces
			cat $parts >"$file.tmp" && mv "$file.tmp" "$file"
			# shellcheck disable=SC2086 # the part names have no spaces
			$keep || rm -f $parts
		fi
	fi

	if [ -e "$file" ]; then
		say "Checking $file"
		grep "  $file\$" "SHA256SUMS-$arch" | sha256_check >/dev/null || die "$file doesn't match its checksum; delete it and run again"
		case "$file" in
		*.zst)
			need zstd "to unpack the disk image"
			say "Unpacking ${file%.zst}"
			zstd -q -d -f "$file" -o "${file%.zst}"
			$keep || rm -f "$file"
			file=${file%.zst}
			# Give the image's empty space back (a raw disk drops from about
			# 42 GiB to 7 GiB on disk); skipped where fallocate isn't there.
			if command -v fallocate >/dev/null 2>&1; then
				fallocate -d "$file" 2>/dev/null || true
			fi
			;;
		esac
	fi

	say ""
	say "Done: $(pwd)/$file"
	case "$format" in
	iso) say "Write it to a USB stick with Fedora Media Writer, or boot it in a virtual machine." ;;
	qcow2) say "Import it into GNOME Boxes, virt-manager or Proxmox. Sign in as mandara / mandara; you'll pick a new password." ;;
	vmdk) say "Attach it as the disk of a new VirtualBox or VMware machine (UEFI). Sign in as mandara / mandara." ;;
	raw) say "Use it in Parallels or UTM, or write it to a disk. Sign in as mandara / mandara." ;;
	esac
	if [ "$arch" = x86_64 ]; then
		say "On x86_64, turn Secure Boot off; in a virtual machine, pass the host CPU through."
	fi
}

main "$@"
