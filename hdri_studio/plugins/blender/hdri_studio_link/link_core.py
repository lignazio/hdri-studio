"""HDRI Studio Link — parte indipendente da Cinema 4D: client TCP non bloccante (JSON-lines)
e watcher dei file per il fallback su mtime. Testabile fuori da C4D:

    python link_core.py            # si collega all'app e stampa i messaggi per 15 s
"""
import errno
import json
import os
import select
import socket
import time

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 47820

_INPROGRESS = {errno.EINPROGRESS, errno.EWOULDBLOCK, errno.EALREADY, 10035, 10036, 10037}


class LinkClient:
    """Client TCP non bloccante. poll() va chiamato periodicamente dal thread principale e
    restituisce i messaggi arrivati; si riconnette da solo quando l'app non c'è."""

    def __init__(self, host=DEFAULT_HOST, port=DEFAULT_PORT, retry=2.0, hello=None):
        self.host = host
        self.port = port
        self.retry = retry
        self.hello = hello or {"type": "hello", "host": "python"}
        self.sock = None
        self.connected = False
        self._buf = b""
        self._next_try = 0.0

    def poll(self):
        msgs = []
        if self.sock is None:
            now = time.time()
            if now < self._next_try:
                return msgs
            self._next_try = now + self.retry
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.setblocking(False)
            err = s.connect_ex((self.host, self.port))
            if err != 0 and err not in _INPROGRESS:
                s.close()
                return msgs
            self.sock = s
            self.connected = err == 0
            if self.connected:
                self.send(self.hello)
        try:
            r, w, x = select.select([self.sock], [self.sock], [self.sock], 0)
        except (OSError, ValueError):
            self._drop()
            return msgs
        if not self.connected:
            if x:
                self._drop()
                return msgs
            if not w:
                return msgs
            err = self.sock.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR)
            if err != 0:
                self._drop()
                return msgs
            self.connected = True
            self.send(self.hello)
            return msgs
        if r:
            try:
                data = self.sock.recv(65536)
            except BlockingIOError:
                data = None
            except OSError:
                self._drop()
                return msgs
            if data == b"":
                self._drop()
                return msgs
            if data:
                self._buf += data
                while b"\n" in self._buf:
                    line, self._buf = self._buf.split(b"\n", 1)
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        msgs.append(json.loads(line.decode("utf-8")))
                    except ValueError:
                        pass
        return msgs

    def send(self, msg):
        if self.sock is None:
            return False
        try:
            self.sock.sendall((json.dumps(msg) + "\n").encode("utf-8"))
            return True
        except OSError:
            self._drop()
            return False

    def close(self):
        self._drop()
        self._next_try = 0.0

    def _drop(self):
        if self.sock is not None:
            try:
                self.sock.close()
            except OSError:
                pass
        self.sock = None
        self.connected = False
        self._buf = b""


class MtimeWatcher:
    """Fallback senza socket: segnala i file la cui data di modifica è cambiata."""

    def __init__(self):
        self._seen = {}

    def changed(self, paths):
        out = []
        for p in paths:
            key = norm_path(p)
            try:
                m = os.stat(p).st_mtime
            except OSError:
                continue
            if key in self._seen and self._seen[key] != m:
                out.append(p)
            self._seen[key] = m
        return out

    def touch(self, path):
        try:
            self._seen[norm_path(path)] = os.stat(path).st_mtime
        except OSError:
            pass


def norm_path(p):
    return os.path.normcase(os.path.normpath(p))


def same_file(a, b):
    return norm_path(a) == norm_path(b)


if __name__ == "__main__":
    c = LinkClient(hello={"type": "hello", "host": "python-test", "version": "0"})
    t_end = time.time() + 15
    print("[link_core] mi collego a %s:%d per 15 s…" % (c.host, c.port))
    got = 0
    while time.time() < t_end:
        for m in c.poll():
            print("[link_core] ricevuto:", m)
            if m.get("type") == "hdri_updated":
                got += 1
                if got == 2:
                    # test del LightPaint: camera a -Z che guarda una sfera all'origine → riflesso verso -Z
                    c.send({"type": "lightpaint", "host": "c4d", "point": [0, 0, -1],
                            "normal": [0, 0, -1], "camera": [0, 0, -5]})
                    print("[link_core] inviato lightpaint")
        time.sleep(0.05)
    c.close()
    print("[link_core] hdri_updated ricevuti: %d" % got)
