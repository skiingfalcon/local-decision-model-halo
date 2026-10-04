PS := powershell -NoProfile -ExecutionPolicy Bypass -File

.PHONY: sync rocm tls weights serve smoke stop install-task remove-task llama rune-weights serve-rune smoke-rune stop-rune install-rune

sync:
	uv sync
	$(PS) scripts/setup-tls.ps1

rocm:
	$(PS) scripts/setup-rocm.ps1

stop:
	$(PS) scripts/stop.ps1

tls:
	$(PS) scripts/setup-tls.ps1

weights:
	$(PS) scripts/fetch-weights.ps1

serve:
	$(PS) scripts/serve.ps1

smoke:
	$(PS) scripts/smoke.ps1

install-task:
	$(PS) scripts/install-task.ps1 -StartNow

remove-task:
	$(PS) scripts/install-task.ps1 -Remove

# Rune 26B-A4B v3 via llama-server
llama:
	$(PS) scripts/setup-llama.ps1

rune-weights:
	$(PS) scripts/fetch-rune.ps1 Q8_0 BF16

serve-rune:
	$(PS) scripts/serve-rune.ps1

smoke-rune:
	$(PS) scripts/smoke.ps1 -Server rune

stop-rune:
	$(PS) scripts/stop.ps1 -Model rune

install-rune:
	$(PS) scripts/install-task.ps1 -Model rune -StartNow
