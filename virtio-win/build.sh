#!/bin/bash
# =============================================================================
#  virtio-win/build.sh
# =============================================================================
set -euo pipefail

info() { echo "[•] $*"; }
ok()   { echo "[✓] $*"; }
die()  { echo "[✗] $*" >&2; exit 1; }

VIRTIO_WIN_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.noarch.rpm"

# 1 — Download virtio-win RPM
# =============================================================================
info "Downloading virtio-win..."
curl -fLsS --output /output/virtio-win.noarch.rpm "$VIRTIO_WIN_URL"
ok "RPM ready: /output/virtio-win.noarch.rpm"

rpm -qp --info /output/virtio-win.noarch.rpm