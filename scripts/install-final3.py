#!/usr/bin/env python3
"""Final dual install: port-probe sequencing, no marker races."""
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

    def read_until(self, pattern, timeout=600):
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


def stream_to(sock, cmd, label):
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    assert p.stdout is not None
    total = 0
    mark = time.time()
    while True:
        chunk = p.stdout.read(1024 * 1024)
        if not chunk:
            break
        sock.sendall(chunk)
        total += len(chunk)
        if time.time() - mark > 20:
            print(f'\n[{label}: {total / 2**30:.2f} GiB]', flush=True)
            mark = time.time()
    sock.shutdown(socket.SHUT_WR)
    sock.close()
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
    t.send("cat > /tmp/install-clean.sh <<'__ZF3EOF3__'\r\n")
    for line in open(a.script):
        t.send(line)
        time.sleep(0.005)
    t.send('__ZF3EOF3__\r\n')
    time.sleep(1)
    t.buf = b''
    t.send('sh /tmp/install-clean.sh\r\n')
    time.sleep(1)
    t.buf = b''

    stream_to(wait_port(5555, t), ['zstd', '-dc', a.tar], 'fedora')
    stream_to(wait_port(5556, t), ['cat', a.owrt], 'openwrt')
    stream_to(wait_port(5557, t), ['cat', a.boot_overlay], 'boot image')

    t.read_until(rb'New password:', timeout=900)
    t.send(pw + '\r\n')
    t.read_until(rb'Retype new password:', timeout=120)
    t.send(pw + '\r\n')
    t.read_until(rb'DUAL_DONE_[0-9]+', timeout=900)
    print('\nDUAL_INSTALL_SELESAI')
    t.send('reboot -f\r\n')


if __name__ == '__main__':
    main()
