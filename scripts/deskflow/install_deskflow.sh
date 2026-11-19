#!/usr/bin/env bash
# Deskflow (open-source KVM; Barrier/Synergy lineage) installer for the fleet.
# Ubuntu 24.04 (noble): flatpak bundle. Ubuntu 25.04+/Debian: native .deb.
# Windows: winget install Deskflow.Deskflow  (or MSI from github releases)
# https://github.com/deskflow/deskflow/releases
set -euo pipefail

VER="${DESKFLOW_VER:-1.27.0}"
ARCH="$(dpkg --print-architecture)"
CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
BASE="https://github.com/deskflow/deskflow/releases/download/v${VER}"

case "$CODENAME" in
  noble)
    echo ">> noble: flatpak bundle"
    sudo apt-get install -y -qq flatpak
    f="${BASE}/deskflow-${VER}-linux-${ARCH}.flatpak"
    cd /tmp && curl -sLO "$f"
    sudo flatpak install -y "./$(basename "$f")"
    # clean any wrong-arch leftover
    sudo flatpak uninstall -y --system "app/org.deskflow.deskflow/x86_64/master" 2>/dev/null || true
    echo ">> core binary:  flatpak run --command=deskflow-core org.deskflow.deskflow"
    ;;
  plucky|questing|plucky+|stonking|resolute|forky|trixie)
    echo ">> $CODENAME: native .deb"
    f="${BASE}/deskflow-${VER}-${CODENAME}-${ARCH}.deb"
    cd /tmp && curl -sLO "$f"
    sudo apt-get install -y "./$(basename "$f")"
    ;;
  *)
    echo "!! unknown codename '$CODENAME' — grab a matching .deb/flatpak from ${BASE}"
    exit 1
    ;;
esac

# fleet config: shared server conf template lives in ~/env/config/deskflow/
mkdir -p ~/.config/Deskflow
if [ -f ~/env/config/deskflow/deskflow-server.conf ] && [ ! -f ~/.config/Deskflow/deskflow-server.conf ]; then
  cp ~/env/config/deskflow/deskflow-server.conf ~/.config/Deskflow/deskflow-server.conf
  echo ">> installed fleet server config to ~/.config/Deskflow/deskflow-server.conf"
fi
echo ">> done. GUI: 'deskflow' (needs a display). Server conf: ~/.config/Deskflow/deskflow-server.conf"
