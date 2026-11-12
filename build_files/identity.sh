#!/usr/bin/bash
# Apply the image identity after package installation, before dracut.
set -euo pipefail

root=${1:-/}
root=${root%/}
release="$root/usr/lib/os-release"
read -r component version _ <"$root/usr/lib/mandara/BUILD"
version=${version%,}
if [ "$component" != mandara ] || ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "invalid Mandara version in /usr/lib/mandara/BUILD" >&2
	exit 1
fi

# Keep Fedora's ID, numeric VERSION_ID, CPE and support dates: the package
# repositories and bootc-image-builder use them to select the Fedora base.
sed -i -E '/^(NAME|VERSION|PRETTY_NAME|VERSION_CODENAME|ANSI_COLOR|LOGO|DEFAULT_HOSTNAME|HOME_URL|DOCUMENTATION_URL|SUPPORT_URL|BUG_REPORT_URL|VARIANT|VARIANT_ID|IMAGE_ID|IMAGE_VERSION|BUILD_ID|OSTREE_VERSION|VENDOR_NAME|VENDOR_URL)=/d' "$release"
cat >>"$release" <<EOF
NAME="Mandara OS"
VERSION="$version"
PRETTY_NAME="Mandara OS $version"
VARIANT="Mandara"
VARIANT_ID=mandara-os
IMAGE_ID=mandara-os
IMAGE_VERSION="$version"
BUILD_ID="$version"
OSTREE_VERSION="$version"
ANSI_COLOR="0;38;2;34;211;238"
LOGO=org.mandara.studio
DEFAULT_HOSTNAME=mandara
HOME_URL="https://github.com/theHamdiz/mandara-os"
DOCUMENTATION_URL="https://github.com/theHamdiz/mandara-os#readme"
SUPPORT_URL="https://github.com/theHamdiz/mandara-os/issues"
BUG_REPORT_URL="https://github.com/theHamdiz/mandara-os/issues"
VENDOR_NAME="Mandara"
VENDOR_URL="https://github.com/theHamdiz"
EOF

printf 'Mandara OS release %s\n' "$version" >"$root/usr/lib/mandara-release"
ln -sfn ../usr/lib/os-release "$root/etc/os-release"
ln -sfn ../usr/lib/mandara-release "$root/etc/system-release"
ln -sfn ../usr/lib/mandara-release "$root/etc/redhat-release"
