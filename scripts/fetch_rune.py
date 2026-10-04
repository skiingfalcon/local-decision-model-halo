"""Download Rune 26B-A4B v3 GGUFs (systemone-patched) into HF_HOME through the Umbrella transport.

owao/surogate-rune-26b-a4b-systemone carries surogate/rune-26b-a4b's weights unmodified. Its
GGUF header adds the llama.cpp System One metadata: decision type `openjev`, temperature 2 per
question type, and the surogate decision prompt template. With those, llama-server (>= b11371)
serves /v1/systemone for it directly.

Files up to 50 GB go through huggingface_hub. Larger ones (BF16, 50.5 GB) exceed its limit for
non-xet downloads, so they are streamed by scripts/download.py into the same snapshot folder
(resumable, SHA-256 checked against the Hub's LFS hash).

    uv run python scripts/fetch_rune.py Q8_0 BF16      (env loaded by scripts/fetch-rune.ps1)
"""

from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tls"))

from umbrella import install_for_huggingface_hub  # noqa: E402

REPO = "owao/surogate-rune-26b-a4b-systemone"
REVISION = "f6cf5c19a05713cb9b2c59a57cd79e85ab8d2ffd"
HUB_LIMIT = 50 * 10**9

os.environ.pop("HF_HUB_OFFLINE", None)
install_for_huggingface_hub()

from huggingface_hub import HfApi, hf_hub_download  # noqa: E402
from huggingface_hub.constants import HF_HUB_CACHE  # noqa: E402

files = {
    s.rfilename: s
    for s in HfApi().model_info(REPO, revision=REVISION, files_metadata=True).siblings
}
snapshot = Path(HF_HUB_CACHE) / f"models--{REPO.replace('/', '--')}" / "snapshots" / REVISION

for quant in sys.argv[1:] or ["Q8_0"]:
    name = f"Rune-26B-A4B-v3-{quant}.gguf"
    info = files[name]
    t0 = time.perf_counter()
    if (info.size or 0) <= HUB_LIMIT:
        path = Path(hf_hub_download(REPO, name, revision=REVISION))
    else:
        path = snapshot / name
        if not (path.exists() and path.stat().st_size == info.size):
            url = f"https://huggingface.co/{REPO}/resolve/{REVISION}/{name}"
            downloader = Path(__file__).with_name("download.py")
            cmd = [sys.executable, str(downloader), url, str(path), "--sha256", info.lfs.sha256]
            subprocess.run(cmd, check=True)
    size = path.stat().st_size / 2**30
    print(f"{quant}: {path} ({size:.2f} GiB) in {time.perf_counter() - t0:.0f}s", flush=True)
