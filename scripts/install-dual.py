#!/usr/bin/env python3
"""Dual-boot installer orchestrator for b2q.

Phone must be running the upstream installer initramfs at 172.16.42.1 and the
host must have 172.16.42.2/24 on its NCM interface.
"""
import argparse
import re
import socket
import subprocess
import sys
import time

IAC = re.compile(rb'\xff[\xfb-\xfe].|\xff\xf0')


def strip_iac(data):
    return IAC.sub(b'', data)


class Telnet:
    def __init__(self, host='172.16.42.1', port=23):
        self.s = socket.create_connection((host, port), timeout=10)
        self.s.settimeout(0.5)
        self.buf = b''

    def read_until(self, pattern, timeout=300, label=None):
        rx = re.compile(pattern, re.I)
        end = time.time() + timeout
        while time.time() < end:
            if rx.search(self.buf):
                self.buf = b''
                return
            try:
                chunk = self.s.recv(65536)
            except socket.timeout:
                continue
            if not chunk:
                raise RuntimeError('telnet closed')
            self.buf += strip_iac(chunk)
            sys.stdout.write(self.buf.decode('utf8', 'replace'))
            sys.stdout.flush()
            if len(self.buf) > 8192:
                self.buf = self.buf[-4096:]
        raise TimeoutError(f'timed out waiting for {label or pattern}')

    def send(self, data, delay=0.01):
        self.s.sendall(data.encode())
        time.sleep(delay)


def stream(port, cmd, label):
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    assert p.stdout is not None
    s = socket.create_connection(('172.16.42.1', port), timeout=15)
    total = 0
    mark = time.time()
    while True:
        chunk = p.stdout.read(1024 * 1024)
        if not chunk:
            break
        s.sendall(chunk)
        total += len(chunk)
        if time.time() - mark > 20:
            print(f'\n[{label}: {total / 2**30:.2f} GiB]', flush=True)
            mark = time.time()
    s.shutdown(socket.SHUT_WR)
    s.close()
    if p.wait():
        raise RuntimeError(f'{cmd[0]} failed')
    print(f'\n[{label} selesai: {total / 2**30:.2f} GiB]', flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--script', required=True)
    ap.add_argument('--tar', required=True)
    ap.add_argument('--owrt', required=True)
    ap.add_argument('--boot-overlay', required=True)
    ap.add_argument('--password-file', required=True)
    a = ap.parse_args()
    pw = open(a.password_file).read().strip()

    t = Telnet()
    t.send("cat > /tmp/install-dual.sh <<'__ZF3EOF__'\r\n")
    for line in open(a.script):
        t.send(line, 0.005)
    t.send('__ZF3EOF__\r\n')
    time.sleep(1)
    t.buf = b''   # discard the PTY echo of the heredoc
    t.send('sh /tmp/install-dual.sh\r\n')
    time.sleep(0.5)
    t.buf = b''

    t.read_until(rb'FED_READY_[0-9]+', timeout=600, label='fedora listener')
    stream(5555, ['zstd', '-dc', a.tar], 'fedora')
    t.read_until(rb'FED_DONE_[0-9]+', timeout=900, label='fedora unpack')

    t.read_until(rb'OWRT_READY_[0-9]+', timeout=600, label='owrt listener')
    stream(5556, ['cat', a.owrt], 'openwrt')
    t.read_until(rb'OWRT_DONE_[0-9]+', timeout=900, label='owrt dd')

    t.read_until(rb'BOOT_READY_[0-9]+', timeout=600, label='boot listener')
    stream(5557, ['cat', a.boot_overlay], 'boot image')
    t.read_until(rb'BOOT_DONE_[0-9]+', timeout=300, label='bootimg unpack')

    t.read_until(rb'New password:', timeout=300, label='passwd')
    t.send(pw + '\r\n')
    t.read_until(rb'Retype new password:', timeout=60, label='passwd retype')
    t.send(pw + '\r\n')
    t.read_until(rb'DUAL_DONE_[0-9]+', timeout=600, label='install done')
    print('\nDUAL_INSTALL_SELESAI')
    t.send('reboot -f\r\n')


if __name__ == '__main__':
    main()
