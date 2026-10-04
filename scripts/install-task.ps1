# Registers (or replaces) a Scheduled Task that runs a model's server under its supervisor:
#   -Model rune (default) -> "RuneServe" (serve-rune.ps1 -Supervise, port RUNE_PORT)
#   -Model laya (optional) -> "LayaServe" (serve-laya.ps1 -Supervise, port LAYA_PORT)
# The supervisor restarts the server whenever it exits; Task Scheduler's own restart settings only
# cover a failed start of the supervisor itself. -Remove unregisters; scripts\stop.ps1 stops.
#
# Who runs it:
#   (default)                      the current user, starting when that user logs on (tested).
#   -RunAs <DOMAIN\user>           another account, e.g. an IT service account, starting when it logs on.
#   -RunAs <DOMAIN\user> -AtStartup  that account at boot, whether or not anyone is logged on. Prompts
#                                  for the account's password (stored by Task Scheduler). Needs admin.
#                                  NOT YET TESTED on this machine: GPU (Vulkan) access from a
#                                  non-interactive session must be verified with a reboot.
param(
    [ValidateSet('laya', 'rune')][string]$Model = 'rune',
    [string]$RunAs = "$env:USERDOMAIN\$env:USERNAME",
    [switch]$AtStartup,
    [switch]$Remove,
    [switch]$StartNow
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$spec = @{
    laya = @{ name = 'LayaServe'; script = 'serve-laya.ps1'; what = 'Laya decision model (laya-serve)' }
    rune = @{ name = 'RuneServe'; script = 'serve-rune.ps1'; what = 'Rune 26B-A4B v3 decision model (llama-server)' }
}[$Model]

if ($Remove) {
    Unregister-ScheduledTask -TaskName $spec.name -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "removed $($spec.name)"; return
}

$serve = Join-Path $PSScriptRoot $spec.script
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -WorkingDirectory $root `
    -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$serve`" -Supervise"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew -StartWhenAvailable
$common = @{
    TaskName = $spec.name; Action = $action; Settings = $settings; Force = $true
    Description = "$($spec.what), local-decision-model"
}

if ($AtStartup) {
    # Runs at boot under $RunAs with a stored password ("Run whether user is logged on or not").
    $cred = Get-Credential -UserName $RunAs -Message "Password for $RunAs (stored by Task Scheduler)"
    $trigger = New-ScheduledTaskTrigger -AtStartup
    Register-ScheduledTask @common -Trigger $trigger -User $cred.UserName `
        -Password $cred.GetNetworkCredential().Password -RunLevel Limited | Out-Null
    Write-Host "registered $($spec.name) (runs at startup as $RunAs, no logon needed)"
} else {
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $RunAs
    $principal = New-ScheduledTaskPrincipal -UserId $RunAs -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask @common -Trigger $trigger -Principal $principal | Out-Null
    Write-Host "registered $($spec.name) (runs when $RunAs logs on)"
}
if ($StartNow) { Start-ScheduledTask -TaskName $spec.name; Write-Host "started $($spec.name)" }
