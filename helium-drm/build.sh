#!/bin/bash
# =============================================================================
#  helium-drm/build.sh
# =============================================================================
set -euo pipefail

WORKDIR="/tmp/helium-drm-build"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

info() { echo "[•] $*"; }
ok()   { echo "[✓] $*"; }
die()  { echo "[✗] $*" >&2; exit 1; }

# 1 — Install build dependencies + helium-bin from COPR
# =============================================================================
info "Installing dependencies..."
dnf install -y \
    rpm-build \
    dnf-plugins-core \
    wget \
    curl \
    binutils \
    python3 \
    cpio \
    findutils \
    --setopt=install_weak_deps=False -q

info "Enabling imput/helium COPR..."
dnf copr enable -y imput/helium -q

info "Installing helium-bin..."
dnf install -y helium-bin -q

ok "helium-bin installed"

# =============================================================================
# 2 — Confirm installed version matches expected
# =============================================================================
INSTALLED_VER=$(rpm -q helium-bin --queryformat '%{VERSION}')
info "Installed helium-bin version: $INSTALLED_VER"

if [[ -n "${HELIUM_VERSION:-}" && "$INSTALLED_VER" != "$HELIUM_VERSION" ]]; then
    die "Version mismatch: expected $HELIUM_VERSION, got $INSTALLED_VER"
fi

HELIUM_ARCH=$(rpm -q helium-bin --queryformat '%{ARCH}')

# Find helium's install dir (where WidevineCdm should land)
HELIUM_DIR=$(rpm -ql helium-bin \
    | grep -E '^(/usr/share/helium|/opt/helium)' \
    | head -1 \
    | sed 's|/[^/]*$||' || true)

[[ -n "$HELIUM_DIR" ]] || die "Could not determine Helium install directory"
info "Helium install dir: $HELIUM_DIR"

WIDEVINE_TARGET="$HELIUM_DIR/WidevineCdm"

# 3 — Download Chrome, extract WidevineCdm
# =============================================================================
info "Fetching latest stable Chrome version..."
CHROME_VER=$(curl -sL \
    "https://dl.google.com/linux/chrome/deb/dists/stable/main/binary-amd64/Packages" \
    | grep -A5 "Package: google-chrome-stable" \
    | grep "^Version:" | head -1 \
    | awk '{print $2}' | cut -d'-' -f1)

[[ -n "$CHROME_VER" ]] || die "Could not determine Chrome version"
ok "Chrome version: $CHROME_VER"

DEB="google-chrome-stable_${CHROME_VER}-1_amd64.deb"
info "Downloading $DEB..."
wget -q "https://dl.google.com/linux/deb/pool/main/g/google-chrome-stable/$DEB" \
    -O "$WORKDIR/$DEB"

info "Extracting WidevineCdm..."
mkdir -p "$WORKDIR/chrome_extract"
cd "$WORKDIR/chrome_extract"
ar x "$WORKDIR/$DEB"
tar -xf data.tar.xz ./opt/google/chrome/WidevineCdm
cd "$WORKDIR"

WIDEVINE_SRC="$WORKDIR/chrome_extract/opt/google/chrome/WidevineCdm"
[[ -d "$WIDEVINE_SRC" ]] || die "WidevineCdm not found in Chrome package"

WIDEVINE_VER=$(python3 -c "
import json
m = json.load(open('$WIDEVINE_SRC/manifest.json'))
print(m.get('version', 'unknown'))
")
ok "Widevine version: $WIDEVINE_VER"

# 4 — Stage file tree (helium-bin files + WidevineCdm)
# =============================================================================
info "Staging file tree..."
STAGING="$WORKDIR/staging"

rpm -ql helium-bin | while IFS= read -r f; do
    [[ -f "$f" || -L "$f" ]] || continue
    dest="$STAGING$f"
    mkdir -p "$(dirname "$dest")"
    cp -a "$f" "$dest"
done

mkdir -p "$STAGING$WIDEVINE_TARGET"
cp -r "$WIDEVINE_SRC/." "$STAGING$WIDEVINE_TARGET/"

ok "Staged $(find "$STAGING" -not -type d | wc -l) files"

# 5 — Generate RPM spec and build
# =============================================================================
info "Generating RPM spec..."

RPMBUILD="$WORKDIR/rpmbuild"
mkdir -p "$RPMBUILD"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# Build %files lists
FILES_LIST=$(find "$STAGING" -not -type d | sed "s|$STAGING||" | sort)
DIRS_LIST=$(find "$STAGING" -mindepth 1 -type d | sed "s|$STAGING||" | sort)

cat > "$RPMBUILD/SPECS/helium-drm.spec" <<SPEC
Name:           helium-drm
Version:        ${INSTALLED_VER}
Release:        1%{?dist}
Summary:        Helium browser with Widevine DRM support
License:        BSD-3-Clause and GPL-3.0
URL:            https://github.com/imputnet/helium
BuildArch:      x86_64

Provides:       helium-bin = %{version}
Conflicts:      helium-bin

Requires:       vulkan-loader

%description
Helium browser with Widevine CDM bundled in.
Drop-in replacement for helium-bin — no post-install steps needed.

Widevine version: ${WIDEVINE_VER}
Chrome source:    ${CHROME_VER}

%install
cp -a "${STAGING}/." "%{buildroot}/"

%files
$(echo "$DIRS_LIST" | sed 's/^/%dir /')
$(echo "$FILES_LIST")

%changelog
* $(date '+%a %b %d %Y') pkgs-zodium <actions@github.com> - ${INSTALLED_VER}-1
- Automated build: helium-bin ${INSTALLED_VER} + Widevine ${WIDEVINE_VER}
SPEC

info "Building RPM..."
rpmbuild \
    --define "_topdir $RPMBUILD" \
    -bb "$RPMBUILD/SPECS/helium-drm.spec" \
    2>&1

RPM_FILE=$(find "$RPMBUILD/RPMS" -name "helium-drm-*.rpm" | head -1)
[[ -f "$RPM_FILE" ]] || die "RPM not found after build"

# 6 — Copy to /output (picked up by the workflow)
# =============================================================================
cp "$RPM_FILE" /output/
ok "RPM ready: /output/$(basename "$RPM_FILE")"

echo ""
rpm -qp --info "/output/$(basename "$RPM_FILE")"