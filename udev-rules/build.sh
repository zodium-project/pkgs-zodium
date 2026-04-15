#!/bin/bash
set -euo pipefail

info() { echo "[•] $*"; }
ok()   { echo "[✓] $*"; }
die()  { echo "[✗] $*" >&2; exit 1; }

info "Enabling ublue-os/packages COPR..."
dnf install -y -q dnf5-plugins
dnf copr enable -y ublue-os/packages -q

info "Downloading ublue-os-udev-rules + oversteer-udev..."
dnf download --arch x86_64 --arch noarch \
    ublue-os-udev-rules \
    oversteer-udev \
    --destdir /output -q

[[ "$(ls /output/ublue-os-udev-rules-[0-9]*.rpm 2>/dev/null | wc -l)" -gt 0 ]] \
    || die "ublue-os-udev-rules RPM not downloaded"
[[ "$(ls /output/oversteer-udev-[0-9]*.rpm 2>/dev/null | wc -l)" -gt 0 ]] \
    || die "oversteer-udev RPM not downloaded"

ok "Downloaded: $(ls /output/ublue-os-udev-rules-[0-9]*.rpm /output/oversteer-udev-[0-9]*.rpm | xargs -n1 basename)"
rpm -qp --info /output/ublue-os-udev-rules-[0-9]*.rpm
rpm -qp --info /output/oversteer-udev-[0-9]*.rpm