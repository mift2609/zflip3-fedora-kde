#!/usr/bin/env bash
# Dijalankan di konsole laptop supaya progres terlihat.
cd "$(dirname "$0")/.." || exit 1
mkdir -p work
sudo -n env HOME=/home/qiiin bash scripts/build-rootfs.sh 2>&1 | tee work/build-rootfs.log
rc=${PIPESTATUS[0]}
printf '\nSELESAI rc=%s — log: %s\n' "$rc" "$PWD/work/build-rootfs.log"
exec bash
