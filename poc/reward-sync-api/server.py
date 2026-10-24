#!/usr/bin/env python3
"""Temporary in-memory HTTP API for the iOS reward-sync PoC."""

from __future__ import annotations

import argparse
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from threading import Lock
from typing import Any


SNAPSHOT_PATH = "/v1/reward-snapshot"
MAX_REQUEST_BYTES = 16 * 1024
snapshot: dict[str, Any] | None = None
snapshot_lock = Lock()


class RewardSnapshotHandler(BaseHTTPRequestHandler):
    server_version = "RewardSyncPoC/0.1"

    def do_GET(self) -> None:
        if self.path != SNAPSHOT_PATH:
            self._write_json(404, {"error": "not_found"})
            return

        with snapshot_lock:
            current_snapshot = snapshot

        if current_snapshot is None:
            self._write_json(404, {"error": "snapshot_not_found"})
            return

        self._write_json(200, current_snapshot)

    def do_POST(self) -> None:
        global snapshot

        if self.path != SNAPSHOT_PATH:
            self._write_json(404, {"error": "not_found"})
            return

        try:
            content_length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self._write_json(400, {"error": "invalid_content_length"})
            return

        if content_length <= 0 or content_length > MAX_REQUEST_BYTES:
            self._write_json(400, {"error": "invalid_request_size"})
            return

        try:
            payload = json.loads(self.rfile.read(content_length))
            validated_snapshot = self._validate_snapshot(payload)
        except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
            self._write_json(400, {"error": "invalid_snapshot", "message": str(error)})
            return

        with snapshot_lock:
            snapshot = validated_snapshot

        self._write_json(201, validated_snapshot)

    @staticmethod
    def _validate_snapshot(payload: Any) -> dict[str, Any]:
        if not isinstance(payload, dict):
            raise ValueError("JSON body must be an object")

        balance = payload.get("balanceMinutes")
        if type(balance) is not int or balance < 0:
            raise ValueError("balanceMinutes must be a non-negative integer")

        unlock_ends_at = payload.get("unlockEndsAt")
        if unlock_ends_at is not None:
            if not isinstance(unlock_ends_at, str):
                raise ValueError("unlockEndsAt must be an ISO 8601 string or null")
            try:
                parsed_date = datetime.fromisoformat(unlock_ends_at.replace("Z", "+00:00"))
            except ValueError as error:
                raise ValueError("unlockEndsAt must be an ISO 8601 date") from error
            if parsed_date.tzinfo is None:
                raise ValueError("unlockEndsAt must include a timezone")
            unlock_ends_at = parsed_date.isoformat().replace("+00:00", "Z")

        return {"balanceMinutes": balance, "unlockEndsAt": unlock_ends_at}

    def _write_json(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="0.0.0.0", help="interface to listen on")
    parser.add_argument("--port", type=int, default=8787, help="port to listen on")
    args = parser.parse_args()

    with ThreadingHTTPServer((args.host, args.port), RewardSnapshotHandler) as server:
        print(f"PoC reward API listening on http://{args.host}:{args.port}{SNAPSHOT_PATH}")
        print("This server stores one snapshot in memory and is intended for the PoC only.")
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\nStopping PoC reward API.")


if __name__ == "__main__":
    main()
