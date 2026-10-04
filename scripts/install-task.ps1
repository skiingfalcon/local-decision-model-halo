# Registers (or replaces) a per-user Scheduled Task that runs a model's server under its supervisor
# at logon: -Model laya -> "LayaServe" (serve.ps1 -Supervise, port LAYA_PORT);
#           -Model rune -> "RuneServe" (serve-rune.ps1 -Supervise, port RUNE_PORT).
# The supervisor restarts the server whenever it exits; Task Scheduler's own restart settings only
# cover a failed start of the supervisor itself. -Remove unregisters; scripts\stop.ps1 stops.
param([ValidateSet('laya', 'rune')][string]$Model = 'laya', [switch]$Remove, [switch]$StartNow)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$spec = @{
    laya = @{ name = 'LayaServe'; script = 'serve.ps1'; what = 'Laya decision model (laya-serve)' }
    rune = @{ name = 'RuneServe'; script = 'serve-rune.ps1'; what = 'Rune 26B-A4B v3 decision model (llama-server)' }
}[$Model]

if ($Remove) {
    Unregister-ScheduledTask -TaskName $spec.name -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "removed $($spec.name)"; return
}

$serve = Join-Path $PSScriptRoot $spec.script
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -WorkingDirectory $root `
    -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$serve`" -Supervise"
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $spec.name -Action $action -Trigger $trigger -Settings $settings `
    -Principal $principal -Description "$($spec.what), local-decision-model" -Force | Out-Null
Write-Host "registered $($spec.name) (runs at logon)"
if ($StartNow) { Start-ScheduledTask -TaskName $spec.name; Write-Host "started $($spec.name)" }
