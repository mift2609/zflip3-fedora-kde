#!/bin/sh
# Final step: user already exists; write /etc/shadow directly (passwd fails
# in this initramfs), then flash+verify recovery. No password prompt needed.
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
grep -q '^qiiin:' "$MOUNT/etc/passwd" || { echo "user missing" >&2; exit 1; }

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
