#!/usr/bin/env bash
# GitHub Actions variant: assemble Fedora 45 KDE rootfs from the official RAW image.
set -euo pipefail
WS=$(cd "$(dirname "$0")/.." && pwd)
cd "$WS"

ROOT=work/rootfs
KDIR=out/kernel
CACHE=cache
PORT=port
ART=artifact
mkdir -p "$ROOT" work/mnt "$ART"
KREL=$(cat "$KDIR/kernelrelease")
echo "[1/5] kernel $KREL"

echo "[2/5] extract rootfs from RAW"
if [ ! -s "$CACHE/fedora.raw" ]; then
  xz -T0 -dc "$CACHE/fedora.raw.xz" > "$CACHE/fedora.raw.part"
  mv "$CACHE/fedora.raw.part" "$CACHE/fedora.raw"
fi
LOOP=$(losetup -Pf --show "$CACHE/fedora.raw")
cleanup() { umount "$WS/work/mnt" 2>/dev/null || true; losetup -d "$LOOP" 2>/dev/null || true; }
trap cleanup EXIT
PART=$(lsblk -ln -o NAME,FSTYPE,SIZE "$LOOP" | awk '$2=="ext4"||$2=="btrfs"{print $1,$3}' | sort -k2 -hr | head -1 | cut -d' ' -f1)
[ -n "$PART" ] || { echo "no ext4/btrfs partition in RAW" >&2; exit 1; }
echo "      root partition /dev/$PART"
mount -o ro "/dev/$PART" work/mnt
tar -C work/mnt -cf - . | tar -C "$ROOT" -xf -
umount work/mnt
losetup -d "$LOOP"
trap - EXIT

echo "[3/5] firmware from the port image"
FW=$(tar --zstd -tf "$CACHE/arch.tar.zst" 2>/dev/null | grep -m1 -E '(^\./)?usr/lib/firmware/' || true)
if [ -n "$FW" ]; then
  FWDIR=${FW%/*}
  tar --zstd -xf "$CACHE/arch.tar.zst" -C work "$FWDIR"
  mkdir -p "$ROOT/usr/lib/firmware"
  cp -a "work/$FWDIR/." "$ROOT/usr/lib/firmware/"
else
  echo "      WARNING: no firmware in port image" >&2
fi

echo "[4/5] kernel modules, boot image, b2q config"
tar --zstd -xf "$KDIR/modules.tar.zst" -C "$ROOT"
[ -d "$ROOT/usr/lib/modules/$KREL" ] || { echo "modules missing" >&2; exit 1; }
install -Dm644 "$KDIR/kernel.config" "$ROOT/boot/config-$KREL"
install -Dm644 "$CACHE/linux.img" "$ROOT/boot/linux-zflip3.img"
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

echo "[5/5] pack rootfs"
tar --zstd -cf "$ART/fedora-kde-rootfs.tar.zst" -C "$ROOT" .
sha256sum "$ART/fedora-kde-rootfs.tar.zst" > "$ART/fedora-kde-rootfs.tar.zst.sha256"
echo "SELESAI: $(du -sh "$ART/fedora-kde-rootfs.tar.zst" | cut -f1)"
cat "$ART/fedora-kde-rootfs.tar.zst.sha256"
