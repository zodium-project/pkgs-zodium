#!/bin/bash
# =============================================================================
#  helium-drm/build.sh
# =============================================================================
set -euo pipefail

info() { echo "[•] $*"; }
ok()   { echo "[✓] $*"; }
die()  { echo "[✗] $*" >&2; exit 1; }

# 1 — Install dependencies
# =============================================================================
info "Installing dependencies..."
dnf install -y \
    dnf-plugins-core \
    wget curl python3 \
    rpmrebuild \
    --setopt=install_weak_deps=False -q

info "Enabling imput/helium COPR..."
dnf copr enable -y imput/helium -q

info "Installing helium-bin..."
dnf install -y helium-bin -q
ok "helium-bin installed"

# 2 — Get installed version info
# =============================================================================
INSTALLED_VER=$(rpm -q helium-bin --queryformat '%{VERSION}')
info "helium-bin version: $INSTALLED_VER"

if [[ -n "${HELIUM_VERSION:-}" && "$INSTALLED_VER" != "$HELIUM_VERSION" ]]; then
    die "Version mismatch: expected $HELIUM_VERSION, got $INSTALLED_VER"
fi

HELIUM_DIR=$(rpm -ql helium-bin \
    | grep -E '^(/usr/share/helium|/opt/helium)' \
    | head -1 | sed 's|/[^/]*$||' || true)
[[ -n "$HELIUM_DIR" ]] || die "Could not determine Helium install directory"
info "Helium install dir: $HELIUM_DIR"

# 3 — Download Chrome and extract WidevineCdm directly into helium's dir
info "Fetching latest stable Chrome version..."
CHROME_VER=$(curl -sL \
    "https://dl.google.com/linux/chrome/deb/dists/stable/main/binary-amd64/Packages" \
    | grep -A5 "Package: google-chrome-stable" \
    | grep "^Version:" | head -1 \
    | awk '{print $2}' | cut -d'-' -f1)
[[ -n "$CHROME_VER" ]] || die "Could not determine Chrome version"
ok "Chrome version: $CHROME_VER"

WORKDIR=$(mktemp -d)
DEB="google-chrome-stable_${CHROME_VER}-1_amd64.deb"
info "Downloading $DEB..."
wget -q "https://dl.google.com/linux/deb/pool/main/g/google-chrome-stable/$DEB" \
    -O "$WORKDIR/$DEB"

info "Extracting WidevineCdm..."
mkdir -p "$WORKDIR/chrome_extract"
cd "$WORKDIR/chrome_extract"
ar x "$WORKDIR/$DEB"
tar -xf data.tar.xz ./opt/google/chrome/WidevineCdm
cd /

WIDEVINE_SRC="$WORKDIR/chrome_extract/opt/google/chrome/WidevineCdm"
[[ -d "$WIDEVINE_SRC" ]] || die "WidevineCdm not found in Chrome package"

WIDEVINE_VER=$(python3 -c "
import json; m = json.load(open('$WIDEVINE_SRC/manifest.json'))
print(m.get('version', 'unknown'))
")
ok "Widevine version: $WIDEVINE_VER"

# 4 — Drop WidevineCdm into helium's live install dir
# =============================================================================
info "Installing WidevineCdm into $HELIUM_DIR/WidevineCdm ..."
rm -rf "$HELIUM_DIR/WidevineCdm"
cp -r "$WIDEVINE_SRC" "$HELIUM_DIR/WidevineCdm"
ok "WidevineCdm in place"

# 5 — Repack with rpmrebuild
# =============================================================================
info "Repacking helium-bin as helium-drm..."
rpmrebuild \
    --change-spec-preamble="sed -e 's/^Name:.*/Name: helium-drm/' \
        -e 's/^Summary:.*/Summary: Helium browser with Widevine DRM (Widevine ${WIDEVINE_VER})/' \
        -e '/^Conflicts:/d' \
        -e '\$a Provides: helium-bin = %{version}\nConflicts: helium-bin'" \
    --package \
    helium-bin

RPM_FILE=$(find ~/rpmbuild/RPMS -name "helium-drm-*.rpm" 2>/dev/null | head -1)
[[ -f "$RPM_FILE" ]] || die "RPM not found after rpmrebuild"

cp "$RPM_FILE" /output/
ok "RPM ready: /output/$(basename "$RPM_FILE")"
echo ""
rpm -qp --info "/output/$(basename "$RPM_FILE")"