# Stops a model's scheduled task (its supervisor loop) and the server process holding its port.
#   -Model rune (default) -> RuneServe / RUNE_PORT;  -Model laya -> LayaServe / LAYA_PORT
param([ValidateSet('laya', 'rune')][string]$Model = 'rune')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_env.ps1')
$task, $port = if ($Model -eq 'rune') { 'RuneServe', $env:RUNE_PORT } else { 'LayaServe', $env:LAYA_PORT }

Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
# Ending the task kills its powershell, but not necessarily the server it launched.
$listener = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listener) {
    Stop-Process -Id $listener.OwningProcess -Force
    Write-Host "stopped $Model server (pid $($listener.OwningProcess)) on port $port"
} else {
    Write-Host "nothing listening on port $port"
}
