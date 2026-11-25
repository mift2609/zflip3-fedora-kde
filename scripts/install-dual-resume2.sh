#!/bin/sh
# Resume after Fedora tar finished extracting but the host timed out waiting
# for the marker. Fedora LV is mounted; stream OpenWrt + boot overlay, create
# the user, write recovery, done.
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
[ -x "$MOUNT/usr/lib/systemd/systemd" ] && [ -f "$MOUNT/etc/os-release" ] || { echo "fedora rootfs incomplete" >&2; exit 1; }
mountpoint -q "$MOUNT" 2>/dev/null || mount -t f2fs -o rw,noatime "/dev/$VG/root" "$MOUNT"
echo "RESUME2_READY_$$"

echo "OWRT_READY_$$"
mkfifo /tmp/nc-owrt2
exec 4<>/tmp/nc-owrt2
nc -l -p 5556 <&4 | dd of="/dev/$VG/owrt" bs=1M conv=fsync 2>/dev/null
exec 4>&-
rm -f /tmp/nc-owrt2
sync
echo "OWRT_DONE_$$"

echo "BOOT_READY_$$"
mkfifo /tmp/nc-boot2
exec 5<>/tmp/nc-boot2
nc -l -p 5557 <&5 | tar -C "$MOUNT" -xf -
exec 5>&-
rm -f /tmp/nc-boot2
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
