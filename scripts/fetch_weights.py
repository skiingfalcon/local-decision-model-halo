"""Download every checkpoint laya-serve will load into HF_HOME, through the Umbrella-aware transport.

Builds the same Router that laya-serve builds (same LAYA_* env, so the same reviewed revisions)
and preloads it. Everything laya touches lands in the cache, including tokenizer and encoder
files. After this, the server runs with HF_HUB_OFFLINE=1 and never needs the proxy.

    uv run python scripts/fetch_weights.py        (env loaded by scripts/fetch-weights.ps1)
"""

from __future__ import annotations

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tls"))

from umbrella import install_for_huggingface_hub  # noqa: E402

os.environ.pop("HF_HUB_OFFLINE", None)
install_for_huggingface_hub()

from laya.router import Router  # noqa: E402

names = [m.strip() for m in os.environ.get("LAYA_MODELS", "").split(",") if m.strip()] or None
t0 = time.perf_counter()
router = Router(device="cpu", max_loaded=len(names) if names else 3)
router.preload(names)
print(f"preloaded {names or 'all checkpoints'} into {os.environ.get('HF_HOME')} "
      f"in {time.perf_counter() - t0:.1f}s")
