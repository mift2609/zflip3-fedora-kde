#!/usr/bin/env python3
"""Finish install by streaming only the missing tail of the Fedora tar."""
import argparse
import re
import socket
import subprocess
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

    def read_until(self, pattern, timeout=900):
        rx = re.compile(pattern, re.I)
        end = time.time() + timeout
        while time.time() < end:
            self.drain()
            if rx.search(self.buf):
                self.buf = b''
                return
            time.sleep(0.2)
        raise TimeoutError(f'timed out waiting for {pattern}')


def wait_port(port, t, timeout=900):
    end = time.time() + timeout
    while time.time() < end:
        t.drain()
        try:
            return socket.create_connection(('172.16.42.1', port), timeout=5)
        except OSError:
            time.sleep(1)
    raise TimeoutError(f'port {port} never opened')


def stream_file(sock, path, offset, label):
    f = open(path, 'rb')
    f.seek(offset)
    total = 0
    mark = time.time()
    while True:
        chunk = f.read(1024 * 1024)
        if not chunk:
            break
        sock.sendall(chunk)
        total += len(chunk)
        if time.time() - mark > 20:
            print(f'\n[{label}: {total / 2**30:.2f} GiB]', flush=True)
            mark = time.time()
    f.close()
    sock.shutdown(socket.SHUT_WR)
    sock.close()
    print(f'\n[{label} selesai: {total / 2**30:.2f} GiB]', flush=True)


def stream_cmd(sock, cmd, label):
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    assert p.stdout is not None
    total = 0
    while True:
        chunk = p.stdout.read(1024 * 1024)
        if not chunk:
            break
        sock.sendall(chunk)
        total += len(chunk)
    sock.shutdown(socket.SHUT_WR)
    sock.close()
    if p.wait():
        raise RuntimeError(f'{cmd[0]} failed')
    print(f'\n[{label} selesai: {total / 2**30:.2f} GiB]', flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--script', required=True)
    ap.add_argument('--tar', required=True)
    ap.add_argument('--tar-offset', type=int, required=True)
    ap.add_argument('--owrt', required=True)
    ap.add_argument('--boot-overlay', required=True)
    ap.add_argument('--password-file', required=True)
    a = ap.parse_args()
    pw = open(a.password_file).read().strip()

    t = Telnet()
    t.send("cat > /tmp/resume3.sh <<'__ZF3EOF4__'\r\n")
    for line in open(a.script):
        t.send(line)
        time.sleep(0.005)
    t.send('__ZF3EOF4__\r\n')
    time.sleep(1)
    t.buf = b''
    t.send('sh /tmp/resume3.sh\r\n')
    time.sleep(1)
    t.buf = b''

    stream_file(wait_port(5555, t), a.tar, a.tar_offset, 'fedora-tail')
    stream_cmd(wait_port(5556, t), ['cat', a.owrt], 'openwrt')
    stream_cmd(wait_port(5557, t), ['cat', a.boot_overlay], 'boot image')

    t.read_until(rb'New password:', timeout=900)
    t.send(pw + '\r\n')
    t.read_until(rb'Retype new password:', timeout=120)
    t.send(pw + '\r\n')
    t.read_until(rb'DUAL_DONE_[0-9]+', timeout=900)
    print('\nDUAL_INSTALL_SELESAI')
    t.send('reboot -f\r\n')


if __name__ == '__main__':
    main()
