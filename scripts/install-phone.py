#!/usr/bin/env python3
"""Stream the Fedora rootfs into the upstream b2q installer over USB telnet.

Host interface must already be 172.16.42.2/24 on the installer's NCM gadget.
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
    def __init__(self, host, port=23):
        self.s = socket.create_connection((host, port), timeout=10)
        self.s.settimeout(1.0)
        self.buf = b''

    def read_until(self, pattern, timeout=120, label=None):
        rx = re.compile(pattern, re.I)
        end = time.time() + timeout
        while time.time() < end:
            if rx.search(self.buf):
                return True
            try:
                chunk = self.s.recv(65536)
            except socket.timeout:
                continue
            if not chunk:
                raise RuntimeError('telnet closed')
            self.buf += strip_iac(chunk)
            text = self.buf.decode('utf8', 'replace')
            sys.stdout.write(text)
            sys.stdout.flush()
            self.buf = self.buf[-4096:]
        raise TimeoutError(f'timed out waiting for {label or pattern}')

    def send(self, data):
        self.s.sendall(data.encode())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--tar', required=True, help='fedora-kde-rootfs.tar.zst')
    ap.add_argument('--user', default='qiiin')
    ap.add_argument('--password-file', required=True)
    a = ap.parse_args()

    pw = open(a.password_file).read().strip()
    t = Telnet('172.16.42.1')
    t.send(f'install-rootfs --yes-wipe --user {a.user}\r\n')
    t.read_until(rb'waiting for the rootfs tar', timeout=180, label='listener')

    # installer's nc is up; stream the DECOMPRESSED tar
    zstd = subprocess.Popen(['zstd', '-dc', a.tar], stdout=subprocess.PIPE)
    assert zstd.stdout is not None
    sock = socket.create_connection(('172.16.42.1', 5555), timeout=10)
    total = 0
    mark = time.time()
    while True:
        chunk = zstd.stdout.read(1024 * 1024)
        if not chunk:
            break
        sock.sendall(chunk)
        total += len(chunk)
        if time.time() - mark > 15:
            print(f'\n[sent {total / 2**30:.2f} GiB]', flush=True)
            mark = time.time()
    sock.shutdown(socket.SHUT_WR)
    sock.close()
    rc = zstd.wait()
    if rc:
        raise RuntimeError(f'zstd exited {rc}')
    print(f'\n[tar streamed: {total / 2**30:.2f} GiB]')

    t.read_until(rb'New password:', timeout=600, label='passwd prompt')
    t.send(pw + '\r\n')
    t.read_until(rb'Retype new password:', timeout=60, label='passwd retype')
    t.send(pw + '\r\n')
    t.read_until(rb'done\. Reboot', timeout=900, label='install done')
    print('\nINSTALL_SELESAI')


if __name__ == '__main__':
    main()
