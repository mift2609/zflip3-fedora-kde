#!/bin/sh
# Resume from the partial extraction: receive the remaining tar bytes, then
# finish OpenWrt, boot image, user and recovery. No reformat.
set -eu
VG=b2q
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

lvm vgchange -ay --sysinit "$VG"
mountpoint -q "$MOUNT" 2>/dev/null || mount -t f2fs -o rw,noatime "/dev/$VG/root" "$MOUNT"
rm -f /tmp/nc-fed4 /tmp/nc-owrt4 /tmp/nc-boot4

echo "FED_READY_$$"
mkfifo /tmp/nc-fed4
exec 3<>/tmp/nc-fed4
nc -l -p 5555 <&3 | tar -C "$MOUNT" -xf -
exec 3>&-
rm -f /tmp/nc-fed4
sync
echo "FED_DONE_$$"

echo "OWRT_READY_$$"
mkfifo /tmp/nc-owrt4
exec 4<>/tmp/nc-owrt4
nc -l -p 5556 <&4 | dd of="/dev/$VG/owrt" bs=1M conv=fsync 2>/dev/null
exec 4>&-
rm -f /tmp/nc-owrt4
sync
echo "OWRT_DONE_$$"

echo "BOOT_READY_$$"
mkfifo /tmp/nc-boot4
exec 5<>/tmp/nc-boot4
nc -l -p 5557 <&5 | tar -C "$MOUNT" -xf -
exec 5>&-
rm -f /tmp/nc-boot4
sync
echo "BOOT_DONE_$$"

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
