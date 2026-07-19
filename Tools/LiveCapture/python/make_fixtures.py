#!/usr/bin/env python3
"""Redact a raw capture into a committed fixture.

Usage:
    make_fixtures.py raw-capture.json docs/fixtures/lukijitsi-join.json

Redacts ephemeral TURN credentials (HMAC-derived from the server's static TURN
secret, time-limited). Only the structure matters for the parser tests.
"""
import json
import re
import sys


def redact(payload: str) -> str:
    payload = re.sub(r"password='[^']*'", "password='REDACTED'", payload)
    payload = re.sub(r'password="[^"]*"', 'password="REDACTED"', payload)
    # Redact inside the JSON metadata message too.
    payload = re.sub(r'(&quot;password&quot;:&quot;)[^&]*(&quot;)', r'\1REDACTED\2', payload)
    return payload


def main() -> None:
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    src, dst = sys.argv[1], sys.argv[2]
    with open(src) as f:
        frames = json.load(f)
    frames = [
        {"direction": fr["direction"], "timestamp": fr["timestamp"], "payload": redact(fr["payload"])}
        for fr in frames
    ]
    with open(dst, "w") as f:
        json.dump(frames, f, indent=2)
    print(f"wrote {dst}: {len(frames)} frames")


if __name__ == "__main__":
    main()
