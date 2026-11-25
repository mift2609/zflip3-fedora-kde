#!/usr/bin/env bash
# Build a boot image whose initramfs boots OpenWrt by default and Fedora when
# Volume Up is held during the first 3 seconds.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
WORK="$REPO/work"
SRC="$REPO/../zflip3-openwrt/images/installer.img"
INIT_SRC="$REPO/../zflip3/userspace/installer/init"
OUT="$REPO/out/boot-dual.img"
STAGE="$WORK/initramfs-dual"
RAM="$WORK/ramdisk-dual.gz"

mkdir -p "$WORK" "$STAGE" "$REPO/out"
rm -rf "$OUT"
rm -rf "$STAGE"/* "$RAM"

python3 - "$SRC" "$WORK/kernel.bin" "$WORK/ramdisk-orig.gz" "$WORK/tail.bin" <<'PY'
import struct,sys
src,kout,rout,tout=sys.argv[1:]
d=open(src,'rb').read()
ks=struct.unpack_from('<I',d,8)[0]; rs=struct.unpack_from('<I',d,16)[0]
p=4096
rs_off=d.find(b'\x1f\x8b', p+ks)      # first gzip stream after the kernel payload
if rs_off < p+ks or rs_off > p+ks+1048576: raise SystemExit('ramdisk not found')
pad = rs_off - (p + ks)
open(kout,'wb').write(d[p:p+ks])
open(rout,'wb').write(d[rs_off:rs_off+rs])
open(tout,'wb').write(d[rs_off+rs:])
print(f'kernel={ks} ramdisk={rs} ramdisk_off={rs_off} pad={pad} tail={len(d)-rs_off-rs}')
PY

gzip -dc "$WORK/ramdisk-orig.gz" | ( cd "$STAGE" && cpio -idmu --quiet --no-absolute-filenames )

python3 - "$INIT_SRC" "$STAGE/init" <<'PY'
import sys
src,dst=sys.argv[1:]
text=open(src).read()
head=text.split('# --- root ---',1)[0]
tail=r'''# --- root: OpenWrt by default, Volume Up -> Fedora ------------------------
echo "Volume Up=Fedora, otherwise OpenWrt (3s)" > /dev/tty0
vol_up() { awk '/Volume Up/{print $2}' /proc/interrupts 2>/dev/null; }
before=$(vol_up)
sleep 3
pick=owrt
[ "$(vol_up)" = "$before" ] || pick=fedora

ok=0
if lvm vgchange -ay --sysinit b2q >/dev/null 2>&1; then
  if [ "$pick" = fedora ]; then
    if mount -t f2fs -o rw,noatime /dev/b2q/root /newroot 2>/dev/null &&
       [ -x /newroot/usr/lib/systemd/systemd ]; then ok=1; fi
  else
    if mount -t ext4 -o rw,noatime /dev/b2q/owrt /newroot 2>/dev/null &&
       [ -x /newroot/sbin/init ]; then
      mkdir -p /newroot/tmp /newroot/var/run /newroot/var/lock /newroot/var/log /newroot/var/state
      mount -t tmpfs tmpfs /newroot/tmp 2>/dev/null
      mount -t tmpfs tmpfs /newroot/var/run 2>/dev/null
      mount -t tmpfs tmpfs /newroot/var/lock 2>/dev/null
      mount -t tmpfs tmpfs /newroot/var/log 2>/dev/null
      mount -t tmpfs tmpfs /newroot/var/state 2>/dev/null
      ok=1
    fi
  fi
fi

if [ "$ok" = 1 ]; then
  echo "booting $pick" > /dev/tty0
  killall telnetd udhcpd 2>/dev/null
  ip addr flush dev "$ifname" 2>/dev/null
  for m in /dev /proc /sys; do mount --move "$m" "/newroot$m"; done
  if [ "$pick" = fedora ]; then
    exec switch_root /newroot /usr/lib/systemd/systemd
  else
    exec switch_root /newroot /sbin/init
  fi
fi
umount /newroot 2>/dev/null
echo "fallback shell: telnet 172.16.42.1" > /dev/tty0
while :; do
  if [ -c /dev/ttyGS0 ]; then
    setsid /bin/sh -i </dev/ttyGS0 >/dev/ttyGS0 2>&1
  fi
  sleep 2
done
'''
open(dst,'w').write(head+tail)
PY
chmod +x "$STAGE/init"

( cd "$STAGE" && find . -print0 | cpio --null -o -H newc --owner=0:0 --reproducible --quiet | gzip -9 ) > "$RAM"

python3 - "$SRC" "$WORK/kernel.bin" "$RAM" "$WORK/tail.bin" "$OUT" <<'PY'
import struct,sys
src,k,r,t,out=sys.argv[1:]
h=bytearray(open(src,'rb').read(4096))
kb=open(k,'rb').read(); rb=open(r,'rb').read(); tb=open(t,'rb').read()
d=open(src,'rb').read()
ks=struct.unpack_from('<I',d,8)[0]
rs_off=d.find(b'\x1f\x8b',4096+ks)
pad=rs_off-(4096+ks)
struct.pack_into('<I',h,16,len(rb))
with open(out,'wb') as f:
    f.write(h); f.write(kb); f.write(b'\0'*pad); f.write(rb); f.write(tb)
print('boot-dual.img',len(h)+len(kb)+pad+len(rb)+len(tb),'bytes')
PY
sha256sum "$OUT" > "$OUT.sha256"
cat "$OUT.sha256"
