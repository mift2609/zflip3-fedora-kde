#!/usr/bin/env python3
"""Drive the HTTP-based dual installer over telnet."""
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

    def read_until(self, pattern, timeout=1800):
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
    ap.add_argument('--password-file', required=True)
    a = ap.parse_args()
    pw = open(a.password_file).read().strip()

    t = Telnet()
    t.send("cat > /tmp/install-http.sh <<'__ZF3EOF5__'\r\n")
    for line in open(a.script):
        t.send(line)
        time.sleep(0.005)
    t.send('__ZF3EOF5__\r\n')
    time.sleep(1)
    t.buf = b''
    t.send('sh /tmp/install-http.sh\r\n')
    time.sleep(1)
    t.buf = b''

    t.read_until(rb'HTTP_FED_DONE_[0-9]+', timeout=1800)
    t.read_until(rb'HTTP_OWRT_DONE_[0-9]+', timeout=900)
    t.read_until(rb'HTTP_BOOT_DONE_[0-9]+', timeout=600)
    t.read_until(rb'New password:', timeout=600)
    t.send(pw + '\r\n')
    t.read_until(rb'Retype new password:', timeout=120)
    t.send(pw + '\r\n')
    t.read_until(rb'DUAL_DONE_[0-9]+', timeout=900)
    print('\nDUAL_INSTALL_SELESAI')
    t.send('reboot -f\r\n')


if __name__ == '__main__':
    main()
