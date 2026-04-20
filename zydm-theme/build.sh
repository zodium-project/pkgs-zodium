#!/bin/bash
# =============================================================================
#  sddm-theme-zydm/build.sh
# =============================================================================
set -euo pipefail

WORKDIR="/tmp/zydm-theme-build"
THEME_REPO="https://github.com/zodium-project/zydm-theme.git"
THEME_DEST="/etc/sddm/themes/zydm"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

info() { echo "[•] $*"; }
ok()   { echo "[✓] $*"; }
die()  { echo "[✗] $*" >&2; exit 1; }

# 1 — Install build dependencies
# =============================================================================
info "Installing dependencies..."
dnf install -y rpm-build git --setopt=install_weak_deps=False -q

# 2 — Clone theme & extract version from metadata.desktop
# =============================================================================
info "Cloning theme..."
git clone --depth 1 "$THEME_REPO" "$WORKDIR/src"

VERSION=$(grep -Po '(?<=^Version=)\S+' "$WORKDIR/src/metadata.desktop" || echo "0.0.0")
info "Version: $VERSION"

# 3 — Stage assets (strip files not needed at runtime)
# =============================================================================
info "Staging assets..."
STAGING="$WORKDIR/staging${THEME_DEST}"
mkdir -p "$STAGING"

rsync -a \
    --exclude='.git/' \
    --exclude='LICENSE' \
    --exclude='THIRD_PARTY_LICENSE' \
    --exclude='*.md' \
    "$WORKDIR/src/" "$STAGING/"

find "$STAGING" -type d -exec chmod 755 {} \;
find "$STAGING" -type f -exec chmod 644 {} \;

ok "Staged $(find "$STAGING" -not -type d | wc -l) files"

# 4 — Build %files list
# =============================================================================
FILES_SECTION="%dir ${THEME_DEST}"$'\n'

# Emit %dir for every subdirectory discovered
while IFS= read -r d; do
    FILES_SECTION+="%dir ${d}"$'\n'
done < <(find "$STAGING" -mindepth 1 -type d | sed "s|$WORKDIR/staging||" | sort)

# Emit path for every file
while IFS= read -r f; do
    FILES_SECTION+="${f}"$'\n'
done < <(find "$STAGING" -not -type d | sed "s|$WORKDIR/staging||" | sort)

# 5 — Write spec
# =============================================================================
RPMBUILD="$WORKDIR/rpmbuild"
mkdir -p "$RPMBUILD"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

cat > "$RPMBUILD/SPECS/sddm-theme-zydm.spec" <<SPEC
Name:           zydm-theme
Version:        ${VERSION}
Release:        1%{?dist}
Summary:        A clean, modern SDDM theme by zodium-project
License:        MPL-2.0
BuildArch:      noarch
URL:            https://github.com/zodium-project/zydm-theme

Requires:       sddm
Requires:       qt6-qtdeclarative
Requires:       qt6-qtmultimedia
Requires:       qt6-qtquickcontrols2
Requires:       qt6-qtsvg

%description
zydm is modern SDDM greeter theme from the zodium-project.
Features video/static background, clock, calendar, battery indicator,
power bar, and a login card — rendered with Qt 6 QML.

%install
cp -a "${WORKDIR}/staging/." "%{buildroot}/"

%post
systemctl enable sddm.service &>/dev/null || :

%preun
%systemd_preun sddm.service

%postun
%systemd_postun_with_restart sddm.service

%files
${FILES_SECTION}
%changelog
* $(date '+%a %b %d %Y') pkgs-zodium <actions@github.com> - ${VERSION}-1
- Initial package
SPEC

# 6 — Build
# =============================================================================
info "Building RPM..."
rpmbuild \
    --define "_topdir $RPMBUILD" \
    -bb "$RPMBUILD/SPECS/sddm-theme-zydm.spec" \
    2>&1

RPM_FILE=$(find "$RPMBUILD/RPMS" -name "zydm-theme-*.rpm" | head -1)
[[ -f "$RPM_FILE" ]] || die "RPM not found after build"

cp "$RPM_FILE" /output/
ok "RPM ready: /output/$(basename "$RPM_FILE")"

rpm -qp --info "/output/$(basename "$RPM_FILE")"
rpm -qp --list "/output/$(basename "$RPM_FILE")"