#!/usr/bin/env python3
"""Serve the filtered list to TrafficGuard over a temporary loopback endpoint."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import sys
import threading


def apply_list(path, command=('traffic-guard',)):
    data = Path(path).read_bytes()
    if not data.strip():
        raise ValueError('Пустой список блокировки')
    fetched = threading.Event()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != '/blocklist':
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            fetched.set()

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    try:
        url = f'http://127.0.0.1:{server.server_port}/blocklist'
        subprocess.run([*command, 'full', '-u', url], check=True, stdin=subprocess.DEVNULL)
        if not fetched.is_set():
            raise ValueError('TrafficGuard не прочитал список блокировки')
    finally:
        server.shutdown()
        server.server_close()
        worker.join()


if __name__ == '__main__':
    try:
        apply_list(sys.argv[1])
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print('Ошибка TrafficGuard: ' + str(error), file=sys.stderr)
        sys.exit(1)
