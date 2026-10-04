"""Download one URL to a file through the corporate proxy: the CA bundle from .env (SSL_CERT_FILE)
plus the Cisco Umbrella session handshake (tls/umbrella.py). Used where Windows' own TLS stack
(Invoke-WebRequest) does not trust the Umbrella root (GitHub release assets), and for Hub files
over huggingface_hub's 50 GB limit for non-xet downloads (Rune BF16).

Resumable: a partial <out>.part is continued with a Range request, and dropped connections are
retried. --sha256 verifies the finished file.

    uv run python scripts/download.py <url> <out-file> [--sha256 <hex>]
"""

from __future__ import annotations

import argparse
import hashlib
import sys
import time
from pathlib import Path

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tls"))
from umbrella import UmbrellaTransport  # noqa: E402


def fetch(client: httpx.Client, url: str, tmp: Path) -> None:
    for attempt in range(20):
        have = tmp.stat().st_size if tmp.exists() else 0
        headers = {"Range": f"bytes={have}-"} if have else {}
        try:
            with client.stream("GET", url, headers=headers) as r:
                if r.status_code == 416:  # already complete
                    return
                r.raise_for_status()
                if have and r.status_code != 206:
                    have = 0  # server ignored the range: start over
                total = have + int(r.headers.get("content-length", 0))
                last = time.monotonic()
                with tmp.open("ab" if have else "wb") as f:
                    for chunk in r.iter_bytes(8 << 20):
                        f.write(chunk)
                        have += len(chunk)
                        if time.monotonic() - last > 30:
                            print(f"  {have / 2**30:.1f} / {total / 2**30:.1f} GiB", flush=True)
                            last = time.monotonic()
            return
        except (httpx.TransportError, httpx.HTTPStatusError) as exc:
            print(f"  attempt {attempt + 1}: {exc}; resuming", flush=True)
            time.sleep(min(2**attempt, 60))
    raise SystemExit(f"giving up on {url}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("url")
    ap.add_argument("out", type=Path)
    ap.add_argument("--sha256")
    args = ap.parse_args()
    out: Path = args.out
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(out.suffix + ".part")
    with httpx.Client(transport=UmbrellaTransport(), follow_redirects=True, timeout=60) as client:
        fetch(client, args.url, tmp)
    if args.sha256:
        h = hashlib.sha256()
        with tmp.open("rb") as f:
            while block := f.read(16 << 20):
                h.update(block)
        if h.hexdigest() != args.sha256.lower():
            raise SystemExit(f"sha256 mismatch: got {h.hexdigest()}, expected {args.sha256}")
    tmp.replace(out)
    print(f"{out} ({out.stat().st_size / 2**20:.1f} MiB)")


if __name__ == "__main__":
    main()
