#!/bin/bash
set -euo pipefail

info() { echo "[•] $*"; }
ok()   { echo "[✓] $*"; }
die()  { echo "[✗] $*" >&2; exit 1; }

# 1 — Dependencies
info "Installing dependencies..."
dnf install -y -q --setopt=install_weak_deps=False \
    python3 dnf5-plugins rpmrebuild fedora-workstation-repositories rpm-build

info "Enabling imput/helium COPR..."
dnf copr enable -y imput/helium -q

info "Enabling Google Chrome repo..."
dnf config-manager setopt google-chrome.enabled=1

info "Installing helium-bin..."
dnf install -y -q helium-bin
ok "helium-bin installed"

# 2 — Version + install dir
INSTALLED_VER=$(rpm -q helium-bin --queryformat '%{VERSION}')
ok "helium-bin version: $INSTALLED_VER"

HELIUM_DIR=$(rpm -ql helium-bin \
    | grep -E '^(/opt|/usr/share)/[^/]+$' \
    | head -1)
[[ -n "$HELIUM_DIR" ]] || die "Could not determine Helium install dir"
info "Helium install dir: $HELIUM_DIR"

# 3 — Pull WidevineCdm from Chrome RPM
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

info "Downloading google-chrome-stable RPM..."
dnf download -q --destdir="$WORKDIR" google-chrome-stable
CHROME_RPM=$(find "$WORKDIR" -name "google-chrome-stable-*.rpm" | head -1)
[[ -f "$CHROME_RPM" ]] || die "Chrome RPM not found"
CHROME_VER=$(rpm -qp "$CHROME_RPM" --queryformat '%{VERSION}' 2>/dev/null)
ok "Chrome version: $CHROME_VER"

info "Extracting WidevineCdm..."
cd "$WORKDIR"
rpm2cpio "$CHROME_RPM" | cpio -id --quiet './opt/google/chrome/WidevineCdm/*'
cd /

WIDEVINE_SRC="$WORKDIR/opt/google/chrome/WidevineCdm"
[[ -d "$WIDEVINE_SRC" ]] || die "WidevineCdm not found in Chrome RPM"

WIDEVINE_VER=$(python3 -c \
    "import json; print(json.load(open('$WIDEVINE_SRC/manifest.json'))['version'])")
ok "Widevine version: $WIDEVINE_VER"

# 4 — Patch helium-wrapper
info "Patching helium-wrapper..."
sed -i 's|exec "\$HERE/helium" "\$@"|exec "$HERE/helium" \\\n    --ozone-platform=wayland \\\n    --gtk-version=4 \\\n    --disable-features=Vulkan \\\n    --enable-features=WaylandWindowDecorations \\\n    "$@"|' \
    "$HELIUM_DIR/helium-wrapper"
ok "helium-wrapper patched"

# 5 — Inject WidevineCdm
info "Injecting WidevineCdm into $HELIUM_DIR..."
rm -rf "$HELIUM_DIR/WidevineCdm"
cp -r "$WIDEVINE_SRC" "$HELIUM_DIR/WidevineCdm"
ok "WidevineCdm in place"

# 6 — Repack as helium-drm RPM
info "Repacking helium-bin as helium-drm..."
rpmrebuild --notest-install \
    --change-spec-preamble="sed \
        -e 's/^Name:.*/Name: helium-drm/' \
        -e 's/^Summary:.*/Summary: Helium browser with Widevine DRM (Widevine ${WIDEVINE_VER})/' \
        -e '/^Conflicts:/d' \
        -e \"\\\$a Provides: helium-bin = ${INSTALLED_VER}\" \
        -e \"\\\$a Conflicts: helium-bin\"" \
    --change-spec-files="cat - <(find ${HELIUM_DIR}/WidevineCdm -type d -printf '%%dir %p\n'; find ${HELIUM_DIR}/WidevineCdm -type f -printf '%p\n')" \
    helium-bin

RPM_FILE=$(find ~/rpmbuild/RPMS -name "helium-drm-*.rpm" | head -1)
[[ -f "$RPM_FILE" ]] || die "RPM not found after rpmrebuild"
ok "RPM built: $RPM_FILE"

# 7 — Produce a minimal SRPM for COPR
info "Building SRPM..."
mkdir -p ~/rpmbuild/{SPECS,SOURCES,SRPMS}

cat > ~/rpmbuild/SPECS/helium-drm.spec <<SPEC
Name:           helium-drm
Version:        ${INSTALLED_VER}
Release:        1%{?dist}
Summary:        Helium browser with Widevine DRM (Widevine ${WIDEVINE_VER})
License:        GPL-3.0
URL:            https://github.com/imputnet/helium-linux
BuildArch:      x86_64
Source0:        helium-drm-${INSTALLED_VER}.rpm

Provides:       helium-bin = ${INSTALLED_VER}
Conflicts:      helium-bin

%description
Helium browser repackaged with WidevineCdm ${WIDEVINE_VER} for DRM support.
Widevine is sourced from the official google-chrome-stable RPM (Chrome ${CHROME_VER}).

%prep

%build

%install
mkdir -p %{buildroot}
rpm2cpio %{SOURCE0} | cpio -id --quiet -D %{buildroot}

%files
%{_prefix}/*

%changelog
* $(date '+%a %b %d %Y') zodium <zodium@localhost> - ${INSTALLED_VER}-1
- Repackaged helium-bin ${INSTALLED_VER} with WidevineCdm ${WIDEVINE_VER}
SPEC

# Copy the built RPM as Source0
cp "$RPM_FILE" ~/rpmbuild/SOURCES/helium-drm-${INSTALLED_VER}.rpm

rpmbuild -bs ~/rpmbuild/SPECS/helium-drm.spec \
    --define "_srcrpmdir $(pwd)"

ok "SRPM ready"