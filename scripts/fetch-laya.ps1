# One-time (and after changing LAYA_MODELS / LAYA_REVISION): populate state\hf through the proxy.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_env.ps1')
Set-Location $ProjectRoot
uv run --no-sync python scripts\fetch_laya.py
exit $LASTEXITCODE
