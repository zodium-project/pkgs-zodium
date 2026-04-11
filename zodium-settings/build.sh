#!/bin/bash
# =============================================================================
#  zodium-settings/build.sh
#  Packages all files from assets/ into an RPM.
#  Runs inside a Fedora container.
#  Mounts: /build/zodium-settings (this dir, ro)
#          /output               (RPM destination)
# =============================================================================
set -euo pipefail

SRCDIR="/build/zodium-settings"
WORKDIR="/tmp/zodium-settings-build"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

info() { echo "[•] $*"; }
ok()   { echo "[✓] $*"; }
die()  { echo "[✗] $*" >&2; exit 1; }

# =============================================================================
# 1 — Install build dependencies
# =============================================================================
info "Installing dependencies..."
dnf install -y rpm-build --setopt=install_weak_deps=False -q

# =============================================================================
# 2 — Version: bump manually as needed
# =============================================================================
VERSION="1.0.0"
info "Version: $VERSION"

# =============================================================================
# 3 — Stage assets
# =============================================================================
info "Staging assets..."
STAGING="$WORKDIR/staging"
cp -a "$SRCDIR/assets/." "$STAGING/"

# Fix permissions
find "$STAGING" -type d -exec chmod 755 {} \;
find "$STAGING" -type f -exec chmod 644 {} \;
chmod 755 "$STAGING/usr/libexec/add_users_to_groups.sh"
chmod 755 "$STAGING/usr/lib/systemd/system/"*.service 2>/dev/null || true

ok "Staged $(find "$STAGING" -not -type d | wc -l) files"

# =============================================================================
# 4 — Build %files list from staging tree
# =============================================================================
FILES_LIST=$(find "$STAGING" -not -type d | sed "s|$STAGING||" | sort)
DIRS_LIST=$(find "$STAGING" -mindepth 1 -type d | sed "s|$STAGING||" | sort)

# =============================================================================
# 5 — Write spec
# =============================================================================
RPMBUILD="$WORKDIR/rpmbuild"
mkdir -p "$RPMBUILD"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

cat > "$RPMBUILD/SPECS/zodium-settings.spec" <<SPEC
Name:           zodium-settings
Version:        ${VERSION}
Release:        1%{?dist}
Summary:        System settings and tweaks for Zodium
License:        MIT
BuildArch:      noarch
URL:            https://github.com/zodium-project/pkgs-zodium

Requires:       systemd
Requires:       zram-generator

%description
System configuration files for Zodium:
- sysctl tweaks
- systemd service/journal/timeout/user limits
- modprobe config (amdgpu, watchdog, ntsync)
- zram generator config
- touchpad Xorg config
- default zsh skeleton
- user group management service

%install
cp -a "${STAGING}/." "%{buildroot}/"

%post
systemctl daemon-reload 2>/dev/null || true
systemctl enable zodium-groups.service 2>/dev/null || true
systemctl enable zodium-hostname.service 2>/dev/null || true
systemctl enable zodium-rfkill.service 2>/dev/null || true
sysctl --system 2>/dev/null || true

%preun
if [ \$1 -eq 0 ]; then
    systemctl disable zodium-groups.service 2>/dev/null || true
    systemctl disable zodium-hostname.service 2>/dev/null || true
    systemctl disable zodium-rfkill.service 2>/dev/null || true
fi

%postun
systemctl daemon-reload 2>/dev/null || true

%files
$(echo "$DIRS_LIST" | sed 's/^/%dir /')
$(echo "$FILES_LIST")

%changelog
* $(date '+%a %b %d %Y') pkgs-zodium <actions@github.com> - ${VERSION}-1
- Initial package
SPEC

# =============================================================================
# 6 — Build
# =============================================================================
info "Building RPM..."
rpmbuild \
    --define "_topdir $RPMBUILD" \
    -bb "$RPMBUILD/SPECS/zodium-settings.spec" \
    2>&1

RPM_FILE=$(find "$RPMBUILD/RPMS" -name "zodium-settings-*.rpm" | head -1)
[[ -f "$RPM_FILE" ]] || die "RPM not found after build"

cp "$RPM_FILE" /output/
ok "RPM ready: /output/$(basename "$RPM_FILE")"

rpm -qp --info "/output/$(basename "$RPM_FILE")"