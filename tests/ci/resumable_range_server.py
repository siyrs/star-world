#!/usr/bin/env python3
"""Local HTTP server used by the updater's real Range-resume acceptance test."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import socket
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def build_fixture(path: Path, size: int) -> bytes:
    if not path.exists() or path.stat().st_size != size:
        path.parent.mkdir(parents=True, exist_ok=True)
        block = bytes((index * 31 + 17) % 256 for index in range(8192))
        with path.open("wb") as stream:
            remaining = size
            while remaining:
                chunk = block[: min(len(block), remaining)]
                stream.write(chunk)
                remaining -= len(chunk)
    return path.read_bytes()


def append_log(path: Path, payload: dict[str, object], lock: threading.Lock) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with lock:
        with path.open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(payload, ensure_ascii=False) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", required=True)
    parser.add_argument("--ready-file", required=True)
    parser.add_argument("--log-file", required=True)
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--size", type=int, default=2 * 1024 * 1024 + 137)
    args = parser.parse_args()

    fixture_path = Path(args.file).resolve()
    ready_path = Path(args.ready_file).resolve()
    log_path = Path(args.log_file).resolve()
    payload = build_fixture(fixture_path, args.size)
    digest = hashlib.sha256(payload).hexdigest()
    etag = '"starworld-range-fixture-v1"'
    cutoff = min(max(300_000, len(payload) // 3), len(payload) - 1)
    lock = threading.Lock()
    state = {"plain_requests": 0}

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, _format: str, *_arguments: object) -> None:
            return

        def do_GET(self) -> None:  # noqa: N802
            if self.path != "/asset":
                self.send_error(404)
                return
            range_header = self.headers.get("Range", "")
            if_range = self.headers.get("If-Range", "")
            event: dict[str, object] = {
                "range": range_header,
                "if_range": if_range,
                "path": self.path,
            }
            if range_header.startswith("bytes="):
                start_text = range_header[6:].split("-", 1)[0]
                try:
                    start = int(start_text)
                except ValueError:
                    self.send_error(400)
                    return
                if start < 0 or start >= len(payload):
                    self.send_response(416)
                    self.send_header("Content-Range", f"bytes */{len(payload)}")
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    event.update({"action": "range_unsatisfied", "start": start})
                    append_log(log_path, event, lock)
                    return
                if if_range and if_range != etag:
                    start = 0
                    status = 200
                    action = "if_range_restart"
                else:
                    status = 206
                    action = "resume"
                body = payload[start:]
                self.send_response(status)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("ETag", etag)
                self.send_header("Accept-Ranges", "bytes")
                if status == 206:
                    self.send_header("Content-Range", f"bytes {start}-{len(payload) - 1}/{len(payload)}")
                self.end_headers()
                self.wfile.write(body)
                self.wfile.flush()
                event.update({"action": action, "start": start, "bytes_sent": len(body)})
                append_log(log_path, event, lock)
                return

            state["plain_requests"] += 1
            self.send_response(200)
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("ETag", etag)
            self.send_header("Accept-Ranges", "bytes")
            self.end_headers()
            if state["plain_requests"] == 1:
                self.wfile.write(payload[:cutoff])
                self.wfile.flush()
                event.update({"action": "forced_disconnect", "bytes_sent": cutoff})
                append_log(log_path, event, lock)
                try:
                    self.connection.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                self.connection.close()
                return
            self.wfile.write(payload)
            self.wfile.flush()
            event.update({"action": "full", "bytes_sent": len(payload)})
            append_log(log_path, event, lock)

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    actual_port = int(server.server_address[1])
    ready_path.parent.mkdir(parents=True, exist_ok=True)
    ready_path.write_text(
        json.dumps(
            {
                "url": f"http://127.0.0.1:{actual_port}/asset",
                "size": len(payload),
                "sha256": digest,
                "etag": etag,
                "cutoff": cutoff,
                "fixture_path": str(fixture_path),
                "log_path": str(log_path),
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    server.serve_forever(poll_interval=0.1)


if __name__ == "__main__":
    main()
