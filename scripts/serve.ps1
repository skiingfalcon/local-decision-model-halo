# Starts laya-serve in the foreground with .env applied; output is appended to state\logs\laya.log.
#   -Supervise   restart the server whenever it exits (10 s, doubling to 2 min between attempts;
#                reset after 10 minutes of uptime). The LayaServe scheduled task runs this mode,
#                because Task Scheduler's own restart-on-failure only covers a failed *start*.
# Stop a supervised server with scripts\stop.ps1, which ends the task and frees the port.
param([switch]$Supervise)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_env.ps1')
Set-Location $ProjectRoot

$logDir = Join-Path $ProjectRoot 'state\logs'
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir 'laya.log'

# LAYA_VENV (relative to the project) selects an alternate environment, e.g. .venv-rocm for the
# ROCm GPU build of torch. Unset = the project's uv-managed .venv.
$venv = if ($env:LAYA_VENV) { $env:LAYA_VENV } else { '.venv' }
$cmd = if ($env:LAYA_VENV) { "`"$(Join-Path $ProjectRoot "$venv\Scripts\laya-serve.exe")`"" } else { 'uv run --no-sync laya-serve' }

$delay = 10
while ($true) {
    "==== $(Get-Date -Format o) starting laya-serve on $(Get-LayaBaseUrl) device=$($env:LAYA_DEVICE) venv=$venv ====" | Add-Content $log
    $started = Get-Date
    # cmd handles the redirect so uvicorn's stderr lands in the log as plain text, not PS error records.
    cmd /c "$cmd >> `"$log`" 2>&1"
    $code = $LASTEXITCODE
    if (-not $Supervise) { exit $code }
    if (((Get-Date) - $started).TotalMinutes -ge 10) { $delay = 10 }
    "==== $(Get-Date -Format o) laya-serve exited ($code); restarting in $delay s ====" | Add-Content $log
    Start-Sleep -Seconds $delay
    $delay = [math]::Min($delay * 2, 120)
}
