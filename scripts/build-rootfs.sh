#!/usr/bin/env bash
# Build a Fedora 45 KDE Plasma Desktop aarch64 rootfs for b2q to stream into the
# upstream installer (`nc 172.16.42.1 5555`). Run as root:
#   sudo -n env HOME=/home/qiiin bash scripts/build-rootfs.sh
# Nothing here writes to the phone.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
WORK="$REPO/work"
ROOT="$WORK/rootfs"
CACHE="$WORK/cache"
OUT="$REPO/out"
KDIR="$OUT/kernel-7.3.5-full"
PORT="$REPO/../zflip3"
BOOTIMG="$REPO/../zflip3-openwrt/images/linux.img"

FED_RAW=Fedora-KDE-Desktop-Disk-45-1.4.aarch64.raw.xz
FED_URL="https://dl.fedoraproject.org/pub/fedora/linux/releases/45/KDE/aarch64/images/$FED_RAW"
FED_SHA_URL="https://dl.fedoraproject.org/pub/fedora/linux/releases/45/KDE/aarch64/images/Fedora-KDE-45-1.4-aarch64-CHECKSUM"
ARCH_NAME=archlinux-zflip3-2026.11.18-rootfs.tar.zst
ARCH_URL="https://github.com/noas-slopware/linux-zflip3/releases/download/arch-ports-2026.11.18/$ARCH_NAME"
ARCH_TAR="$CACHE/$ARCH_NAME"

mkdir -p "$ROOT" "$CACHE" "$WORK/arch" "$OUT"
KREL=$(cat "$KDIR/kernelrelease")
echo "[1/6] kernel $KREL, boot image $BOOTIMG"

echo "[2/6] Fedora 45 KDE Plasma Desktop raw image (3.8 GiB)"
RAW_XZ="$CACHE/$FED_RAW"
RAW="$CACHE/fedora45.raw"
if [ ! -s "$RAW_XZ" ] || [ -s "$RAW_XZ.aria2" ]; then
  rm -f "$RAW_XZ.part"
  aria2c -c -x 8 -s 8 --dir="$CACHE" --out="$FED_RAW" "$FED_URL"
fi
curl -fsSL "$FED_SHA_URL" | grep -F "SHA256 ($FED_RAW)" |
  awk '{gsub(/[()]/, "", $2); print $4 "  " $2}' > "$CACHE/fedora.sha"
( cd "$CACHE" && sha256sum -c fedora.sha )
if [ ! -s "$RAW" ]; then
  echo "      decompressing raw image"
  xz -T0 -dkc "$RAW_XZ" > "$RAW.part"
  mv "$RAW.part" "$RAW"
fi

echo "[3/6] extract rootfs from raw image"
LOOP=$(losetup -Pf --show "$RAW")
cleanup() { umount "$WORK/mnt" 2>/dev/null || true; losetup -d "$LOOP" 2>/dev/null || true; }
trap cleanup EXIT
mkdir -p "$WORK/mnt"
PART=$(lsblk -ln -o NAME,FSTYPE,SIZE "$LOOP" | awk '$2=="ext4"||$2=="btrfs"{print $1,$3}' | sort -k2 -hr | head -1 | cut -d' ' -f1)
[ -n "$PART" ] || { echo "no ext4/btrfs partition in $RAW" >&2; exit 1; }
echo "      root partition /dev/$PART"
mount -o ro "/dev/$PART" "$WORK/mnt"
tar -C "$WORK/mnt" -cf - . | tar -C "$ROOT" -xf -
umount "$WORK/mnt"
losetup -d "$LOOP"
trap - EXIT

echo "[4/6] fetch port image for b2q firmware (1.4 GB)"
if [ ! -s "$ARCH_TAR" ] || [ -s "$ARCH_TAR.aria2" ]; then
  aria2c -c -x 4 -s 4 --dir="$CACHE" --out="$ARCH_NAME" "$ARCH_URL"
fi
FW=$(tar --zstd -tf "$ARCH_TAR" 2>/dev/null | grep -m1 -E '(^\./)?usr/lib/firmware/' || true)
if [ -n "$FW" ]; then
  FWDIR=${FW%/*}
  echo "      extracting $FWDIR"
  tar --zstd -xf "$ARCH_TAR" -C "$WORK/arch" "$FWDIR"
  mkdir -p "$ROOT/usr/lib/firmware"
  cp -a "$WORK/arch/$FWDIR/." "$ROOT/usr/lib/firmware/"
else
  echo "      WARNING: no b2q firmware found in port image" >&2
fi

echo "[5/6] kernel modules, boot image, b2q config"
tar --zstd -xf "$KDIR/modules.tar.zst" -C "$ROOT"
[ -d "$ROOT/usr/lib/modules/$KREL" ] || { echo "modules missing" >&2; exit 1; }
install -Dm644 "$KDIR/kernel.config" "$ROOT/boot/config-$KREL"
install -Dm644 "$BOOTIMG" "$ROOT/boot/linux-zflip3.img"
install -Dm644 "$PORT/userspace/rootfs/etc/fstab" "$ROOT/etc/fstab"
mkdir -p "$ROOT/etc/sddm.conf.d" "$ROOT/etc/systemd/system/multi-user.target.wants"
cat > "$ROOT/etc/sddm.conf.d/10-b2q.conf" <<EOF
[Autologin]
User=qiiin
Session=plasma.desktop
Relogin=false
EOF
ln -sfn /usr/lib/systemd/system/sddm.service "$ROOT/etc/systemd/system/display-manager.service"
for s in sshd NetworkManager bluetooth; do
  [ -e "$ROOT/usr/lib/systemd/system/$s.service" ] || continue
  ln -sfn "/usr/lib/systemd/system/$s.service" \
    "$ROOT/etc/systemd/system/multi-user.target.wants/$s.service"
done
if [ -f /home/qiiin/.ssh/id_rsa.pub ]; then
  install -Dm600 /home/qiiin/.ssh/id_rsa.pub "$ROOT/root/.ssh/authorized_keys"
fi

echo "[6/6] pack rootfs tar.zst"
rm -f "$OUT/fedora-kde-rootfs.tar.zst" "$OUT/fedora-kde-rootfs.tar.zst.sha256"
tar --zstd -cf "$OUT/fedora-kde-rootfs.tar.zst" -C "$ROOT" .
sha256sum "$OUT/fedora-kde-rootfs.tar.zst" > "$OUT/fedora-kde-rootfs.tar.zst.sha256"
echo "SELESAI: $OUT/fedora-kde-rootfs.tar.zst ($(du -sh "$OUT/fedora-kde-rootfs.tar.zst" | cut -f1))"
cat "$OUT/fedora-kde-rootfs.tar.zst.sha256"
