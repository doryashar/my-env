#!/usr/bin/env bash
# RTX 5090 power-limit boot persistence — gpu-box
# Xid 79 "fallen off the bus" remedy: cap power so transient spikes on model
# load can't trip the PSU/board. LLM decode cost at 450W ~1-2% (mem-bw bound).
# Installs a systemd unit that re-applies the cap after every boot, with retry
# (driver module can load late) and post-apply verification.
set -euo pipefail
LIMIT_W="${1:-450}"

cat > /etc/systemd/system/rtx5090-power-limit.service <<UNIT
[Unit]
Description=RTX 5090 power limit ${LIMIT_W}W (Xid 79 remedy) — reapply at boot
After=multi-user.target
Wants=multi-user.target

[Service]
Type=oneshot
# retry until nvidia-smi answers, then set + verify
ExecStart=/bin/bash -c 'for i in \$(seq 1 30); do nvidia-smi -pm 1 >/dev/null 2>&1 && break; sleep 5; done; nvidia-smi -pm 1; nvidia-smi -pl ${LIMIT_W}; L=\$(nvidia-smi --query-gpu=power.limit --format=csv,noheader,nounits | cut -d. -f1); [ "\$L" = "${LIMIT_W}" ] || { echo "VERIFY FAILED: limit=\$L"; exit 1; }'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now rtx5090-power-limit.service

echo "--- applied now:"
nvidia-smi --query-gpu=power.limit,persistence_mode --format=csv,noheader
systemctl --no-pager --lines=3 status rtx5090-power-limit.service | sed -n '1,6p'
