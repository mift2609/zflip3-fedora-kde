#!/bin/sh
# Finish install over HTTP from the host (no nc/FIFO backpressure).
set -eu
VG=b2q
MOUNT=/newroot
BASE=http://172.16.42.2:8000

find_part() {
	for u in /sys/class/block/*/uevent; do
		if grep -qx "PARTNAME=$1" "$u"; then
			echo "/dev/$(grep '^DEVNAME=' "$u" | cut -d= -f2)"
			return 0
		fi
	done
	return 1
}

lvm vgchange -ay --sysinit "$VG"
mountpoint -q "$MOUNT" 2>/dev/null || mount -t f2fs -o rw,noatime "/dev/$VG/root" "$MOUNT"

echo "HTTP_FED_START_$$"
wget -q -O - "$BASE/rootfs-tail.tar" | tar -C "$MOUNT" -xf -
sync
echo "HTTP_FED_DONE_$$"

echo "HTTP_OWRT_START_$$"
wget -q -O - "$BASE/owrt-rootfs.img" | dd of="/dev/$VG/owrt" bs=1M conv=fsync 2>/dev/null
sync
echo "HTTP_OWRT_DONE_$$"

echo "HTTP_BOOT_START_$$"
wget -q -O - "$BASE/boot-overlay.tar" | tar -C "$MOUNT" -xf -
sync
echo "HTTP_BOOT_DONE_$$"

for d in proc sys dev dev/pts; do mount --bind "/$d" "$MOUNT/$d"; done
chroot "$MOUNT" useradd -m -G wheel,video,audio,input,render -s /bin/bash qiiin 2>/dev/null || true
echo "password_for_qiiin"
until chroot "$MOUNT" passwd qiiin; do echo "try again"; done
for d in dev/pts dev sys proc; do umount "$MOUNT/$d"; done

BOOTIMG=$MOUNT/boot/linux-zflip3.img
[ -s "$BOOTIMG" ] || { echo "no boot image" >&2; exit 1; }
RECOVERY=$(find_part recovery)
size=$(wc -c < "$BOOTIMG")
sum=$(sha256sum "$BOOTIMG" | cut -d' ' -f1)
dd if="$BOOTIMG" of="$RECOVERY" bs=1M conv=fsync 2>/dev/null
[ "$(head -c "$size" "$RECOVERY" | sha256sum | cut -d' ' -f1)" = "$sum" ] || { echo "recovery verify failed" >&2; exit 1; }
echo "recovery_verified"
sync
umount "$MOUNT"
echo "DUAL_DONE_$$"
