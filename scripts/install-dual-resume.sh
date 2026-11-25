#!/bin/sh
# Resume after the first telnet session dropped: LVs already exist, nothing
# has been streamed yet. Do NOT recreate PV/VG/LV or mkfs here.
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
mkdir -p "$MOUNT"
mount -t f2fs -o rw,noatime "/dev/$VG/root" "$MOUNT" || { echo "mount root failed" >&2; exit 1; }
echo "RESUME_MOUNTED"

echo "waiting_fedora_tar"
mkfifo /tmp/nc-fed
exec 3<>/tmp/nc-fed
nc -l -p 5555 <&3 | tar -C "$MOUNT" -xf -
exec 3>&-
rm -f /tmp/nc-fed
sync
echo "fedora_tar_done"

echo "waiting_owrt_image"
mkfifo /tmp/nc-owrt
exec 4<>/tmp/nc-owrt
nc -l -p 5556 <&4 | dd of="/dev/$VG/owrt" bs=1M conv=fsync 2>/dev/null
exec 4>&-
rm -f /tmp/nc-owrt
sync
echo "owrt_image_done"

echo "waiting_bootimg"
mkfifo /tmp/nc-boot
exec 5<>/tmp/nc-boot
nc -l -p 5557 <&5 | tar -C "$MOUNT" -xf -
exec 5>&-
rm -f /tmp/nc-boot
sync
echo "bootimg_done"

for d in proc sys dev dev/pts; do mount --bind "/$d" "$MOUNT/$d"; done
chroot "$MOUNT" useradd -m -G wheel,video,audio,input,render -s /bin/bash qiiin
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
echo "DUAL_DONE"
