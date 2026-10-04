# Starts llama-server for Rune 26B-A4B v3 (System One decision endpoint /v1/systemone) with .env
# applied; output is appended to state\logs\rune.log.
#   -Supervise   restart whenever it exits (same backoff as serve-laya.ps1); used by the RuneServe task.
#
# The GGUF's own metadata (gemma4.decision.type=openjev, temperature 2 per question type, the
# surogate prompt template) makes llama-server serve decisions; nothing here configures them.
# Flags: all layers on the iGPU, flash attention, no mmap and -ub 512 per llama-cpp-spark's
# Strix Halo notes (mmap'd weights are slow on this APU; larger ubatch has crashed Vulkan).
param([switch]$Supervise)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_env.ps1')
Set-Location $ProjectRoot

$tag = (Get-Content (Join-Path $ProjectRoot 'LLAMA_CPP_RELEASE') | Where-Object { $_ -and -not $_.StartsWith('#') } | Select-Object -First 1).Trim()
$server = Get-ChildItem (Join-Path $ProjectRoot "vendor\llama.cpp\$tag-$($env:RUNE_LLAMA_BACKEND)") -Recurse -Filter llama-server.exe | Select-Object -First 1
if (-not $server) { throw "llama-server not found for $tag-$($env:RUNE_LLAMA_BACKEND); run scripts\setup-llama.ps1" }

# RUNE_GGUF names the quant file; resolve it inside the HF cache (state\hf) unless it is a path.
$gguf = $env:RUNE_GGUF
if (-not (Test-Path $gguf)) {
    $gguf = Get-ChildItem (Join-Path $env:HF_HOME 'hub\models--owao--surogate-rune-26b-a4b-systemone\snapshots') -Recurse -Filter $env:RUNE_GGUF |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $gguf) { throw "$($env:RUNE_GGUF) not in the HF cache; run scripts\fetch-rune.ps1" }
}

$logDir = Join-Path $ProjectRoot 'state\logs'
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir 'rune.log'

$argv = @(
    # `--load-mode none` is b11382's spelling of the older --no-mmap.
    '-m', "`"$gguf`"", '--jinja', '-ngl', '999', '-fa', 'on', '--load-mode', 'none',
    '-c', $env:RUNE_CTX, '-np', $env:RUNE_PARALLEL, '-ub', $(if ($env:RUNE_UBATCH) { $env:RUNE_UBATCH } else { '512' }),
    '--host', $env:RUNE_HOST, '--port', $env:RUNE_PORT
)
if ($env:RUNE_API_KEY) { $argv += @('--api-key', $env:RUNE_API_KEY) }
# Prometheus-format /metrics (request, token and throughput counters) for Datadog's OpenMetrics
# check. It sits behind the API key like every route except /health. Off by default: with
# --metrics, b11382 Vulkan hit ErrorDeviceLost on the first requests on this machine (2026-10-04).
if ($env:RUNE_METRICS -eq '1') { $argv += '--metrics' }
$cmd = "`"$($server.FullName)`" $($argv -join ' ')"

$delay = 10
while ($true) {
    "==== $(Get-Date -Format o) starting llama-server $tag-$($env:RUNE_LLAMA_BACKEND) $(Split-Path $gguf -Leaf) on $($env:RUNE_HOST):$($env:RUNE_PORT) ====" | Add-Content $log
    $started = Get-Date
    cmd /c "$cmd >> `"$log`" 2>&1"
    $code = $LASTEXITCODE
    if (-not $Supervise) { exit $code }
    if (((Get-Date) - $started).TotalMinutes -ge 10) { $delay = 10 }
    "==== $(Get-Date -Format o) llama-server exited ($code); restarting in $delay s ====" | Add-Content $log
    Start-Sleep -Seconds $delay
    $delay = [math]::Min($delay * 2, 120)
}
