#!/bin/sh
# Finalization only: all payloads are already on disk. Use absolute paths
# because the chroot inherits Android's PATH (no /usr/bin).
set -eu
MOUNT=/newroot

find_part() {
	for u in /sys/class/block/*/uevent; do
		if grep -qx "PARTNAME=$1" "$u"; then
			echo "/dev/$(grep '^DEVNAME=' "$u" | cut -d= -f2)"
			return 0
		fi
	done
	return 1
}

lvm vgchange -ay --sysinit b2q
mountpoint -q "$MOUNT" 2>/dev/null || mount -t f2fs -o rw,noatime /dev/b2q/root "$MOUNT"
for d in proc sys dev dev/pts; do mount --bind "/$d" "$MOUNT/$d"; done
chroot "$MOUNT" /usr/sbin/useradd -m -G wheel,video,audio,input,render -s /bin/bash qiiin 2>/dev/null || true
echo "password_for_qiiin"
chroot "$MOUNT" /usr/bin/passwd qiiin || { echo "passwd failed" >&2; exit 1; }
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
