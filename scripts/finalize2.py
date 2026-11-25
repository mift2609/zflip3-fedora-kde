#!/usr/bin/env python3
"""Write the shadow hash, flash recovery, verify, reboot."""
import argparse
import re
import socket
import sys
import time

IAC = re.compile(rb'\xff[\xfb-\xfe].|\xff\xf0')


class Telnet:
    def __init__(self):
        self.s = socket.create_connection(('172.16.42.1', 23), timeout=10)
        self.s.settimeout(0.3)
        self.buf = b''

    def drain(self):
        try:
            while True:
                d = self.s.recv(65536)
                if not d:
                    break
                self.buf += IAC.sub(b'', d)
                sys.stdout.write(self.buf.decode('utf8', 'replace'))
                sys.stdout.flush()
                if len(self.buf) > 8192:
                    self.buf = self.buf[-4096:]
        except socket.timeout:
            pass

    def send(self, data):
        self.s.sendall(data.encode())

    def read_until(self, pattern, timeout=600):
        rx = re.compile(pattern, re.I)
        end = time.time() + timeout
        while time.time() < end:
            self.drain()
            if rx.search(self.buf):
                self.buf = b''
                return
            time.sleep(0.3)
        raise TimeoutError(f'timed out waiting for {pattern}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--script', required=True)
    ap.add_argument('--hash-file', required=True)
    a = ap.parse_args()
    h = open(a.hash_file).read().strip()
    assert h.startswith('$6$') and '|' not in h

    t = Telnet()
    t.send("cat > /tmp/finalize2.sh <<'__ZF3EOF7__'\r\n")
    for line in open(a.script):
        t.send(line)
        time.sleep(0.005)
    t.send('__ZF3EOF7__\r\n')
    time.sleep(1)
    t.buf = b''
    t.send(f"sed -i 's|^qiiin:!:|qiiin:{h}:|' /newroot/etc/shadow\r\n")
    time.sleep(0.5)
    t.send('grep -q "^qiiin:" /newroot/etc/shadow && echo SHADOW_SET\r\n')
    time.sleep(0.5)
    t.buf = b''
    t.send('sh /tmp/finalize2.sh\r\n')
    time.sleep(1)
    t.buf = b''

    t.read_until(rb'DUAL_DONE_[0-9]+', timeout=600)
    print('\nFINAL_SELESAI')
    t.send('reboot -f\r\n')


if __name__ == '__main__':
    main()
