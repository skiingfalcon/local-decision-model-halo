# Downloads Rune GGUFs into state\hf through the proxy. Default Q8_0; e.g. `fetch-rune.ps1 Q8_0 BF16`.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_env.ps1')
Set-Location $ProjectRoot
uv run --no-sync python scripts\fetch_rune.py @args
exit $LASTEXITCODE
