#!/usr/bin/env bash
# Build a Fedora 44 + KDE Plasma aarch64 rootfs for b2q, to stream into the
# upstream installer's `nc 172.16.42.1 5555`. Nothing is written to the phone here.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
WORK="$REPO/work"
ROOT="$WORK/rootfs"
CACHE="$WORK/cache"
OUT="$REPO/out"
KDIR="$OUT/kernel-7.3.5-full"
PORT="$REPO/../zflip3"
BOOTIMG="$REPO/../zflip3-openwrt/images/linux.img"
REL=arch-ports-2026.11.18
ARCH_TAR="$CACHE/archlinux-zflip3-rootfs.tar.zst"
URL="https://github.com/noas-slopware/linux-zflip3/releases/download/$REL/archlinux-zflip3-rootfs.tar.zst"

mkdir -p "$ROOT" "$CACHE" "$WORK/arch" "$OUT"
KREL=$(cat "$KDIR/kernelrelease")
echo "[1/5] kernel $KREL, boot image $BOOTIMG"

echo "[2/5] fetch Arch port rootfs (firmware source, 1.4 GB)"
if [ ! -s "$ARCH_TAR" ]; then
  curl -fL --retry 3 -o "$ARCH_TAR.part" "$URL"
  mv "$ARCH_TAR.part" "$ARCH_TAR"
fi
echo "      $ARCH_TAR $(du -sh "$ARCH_TAR" | cut -f1)"

echo "[3/5] dnf install Fedora 44 + KDE Plasma (aarch64, native scriptlets via qemu)"
dnf --installroot="$ROOT" --releasever=44 --forcearch=aarch64 \
    --disablerepo='rpmfusion-*' --disablerepo='tailscale-stable' \
    --setopt=install_weak_deps=False -y \
    install @kde-desktop fedora-release-kde linux-firmware \
    openssh-server sudo NetworkManager iw wpa_supplicant bluez \
    f2fs-tools lvm2

echo "[4/5] kernel modules, boot image, firmware, config"
tar --zstd -xf "$KDIR/modules.tar.zst" -C "$ROOT"
[ -d "$ROOT/usr/lib/modules/$KREL" ] || { echo "modules missing" >&2; exit 1; }
install -Dm644 "$KDIR/kernel.config" "$ROOT/boot/config-$KREL"
install -Dm644 "$BOOTIMG" "$ROOT/boot/linux-zflip3.img"

if tar --zstd -tf "$ARCH_TAR" usr/lib/firmware >"$WORK/firmware-list" 2>/dev/null; then
  echo "      extracting firmware from port image"
  tar --zstd -xf "$ARCH_TAR" -C "$WORK/arch" usr/lib/firmware
  mkdir -p "$ROOT/usr/lib/firmware"
  cp -a "$WORK/arch/usr/lib/firmware/." "$ROOT/usr/lib/firmware/"
else
  echo "      WARNING: no usr/lib/firmware in port image" >&2
fi

install -Dm644 "$PORT/userspace/rootfs/etc/fstab" "$ROOT/etc/fstab"
mkdir -p "$ROOT/etc/sddm.conf.d" "$ROOT/etc/systemd/system/display-manager.service.d"
cat > "$ROOT/etc/sddm.conf.d/10-b2q.conf" <<EOF
[Autologin]
User=qiiin
Session=plasma.desktop
Relogin=false
EOF
ln -sfn /usr/lib/systemd/system/sddm.service "$ROOT/etc/systemd/system/display-manager.service"
for s in sshd NetworkManager bluetooth; do
  mkdir -p "$ROOT/etc/systemd/system/multi-user.target.wants"
  ln -sfn "/usr/lib/systemd/system/$s.service" \
    "$ROOT/etc/systemd/system/multi-user.target.wants/$s.service"
done
if [ -f "$HOME/.ssh/id_rsa.pub" ]; then
  install -Dm600 "$HOME/.ssh/id_rsa.pub" "$ROOT/root/.ssh/authorized_keys"
fi

echo "[5/5] pack rootfs tar.zst"
rm -f "$OUT/fedora-kde-rootfs.tar.zst" "$OUT/fedora-kde-rootfs.tar.zst.sha256"
tar --zstd -cf "$OUT/fedora-kde-rootfs.tar.zst" -C "$ROOT" .
sha256sum "$OUT/fedora-kde-rootfs.tar.zst" > "$OUT/fedora-kde-rootfs.tar.zst.sha256"
echo "SELESAI: $OUT/fedora-kde-rootfs.tar.zst ($(du -sh "$OUT/fedora-kde-rootfs.tar.zst" | cut -f1))"
cat "$OUT/fedora-kde-rootfs.tar.zst.sha256"
