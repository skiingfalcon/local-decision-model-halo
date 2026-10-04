PS := powershell -NoProfile -ExecutionPolicy Bypass -File

.PHONY: setup sync tls llama weights serve smoke stop install-task remove-task \
	laya-sync laya-rocm laya-weights laya-serve laya-smoke laya-stop laya-install laya-remove

# --- Rune (default) ----------------------------------------------------------------------------

# One-time setup: Python env + proxy CA, llama.cpp, Rune Q8_0 weights, scheduled task, smoke test.
setup: sync llama weights install-task smoke

sync:
	uv sync
	$(PS) scripts/setup-tls.ps1

tls:
	$(PS) scripts/setup-tls.ps1

llama:
	$(PS) scripts/setup-llama.ps1

weights:
	$(PS) scripts/fetch-rune.ps1 Q8_0

serve:
	$(PS) scripts/serve-rune.ps1

smoke:
	$(PS) scripts/smoke.ps1

stop:
	$(PS) scripts/stop.ps1

install-task:
	$(PS) scripts/install-task.ps1 -StartNow

remove-task:
	$(PS) scripts/install-task.ps1 -Remove

# --- Laya (optional) ---------------------------------------------------------------------------

laya-sync:
	uv sync --extra laya
	$(PS) scripts/setup-tls.ps1

laya-rocm:
	$(PS) scripts/setup-rocm.ps1

laya-weights:
	$(PS) scripts/fetch-laya.ps1

laya-serve:
	$(PS) scripts/serve-laya.ps1

laya-smoke:
	$(PS) scripts/smoke.ps1 -Server laya

laya-stop:
	$(PS) scripts/stop.ps1 -Model laya

laya-install:
	$(PS) scripts/install-task.ps1 -Model laya -StartNow

laya-remove:
	$(PS) scripts/install-task.ps1 -Model laya -Remove
