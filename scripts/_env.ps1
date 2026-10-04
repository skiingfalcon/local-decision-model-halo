# Dot-sourced helper: loads .env (falling back to .env.example) into the process environment
# and puts uv on PATH. Relative values under state\ are resolved against the project root.
# Variables already set in the process take precedence, so e.g. `$env:LAYA_DEVICE='cuda'`
# before calling serve-laya.ps1 overrides .env for that launch.
$script:ProjectRoot = Split-Path $PSScriptRoot -Parent

$envFile = Join-Path $ProjectRoot '.env'
if (-not (Test-Path $envFile)) { $envFile = Join-Path $ProjectRoot '.env.example' }
foreach ($line in Get-Content $envFile) {
    $t = $line.Trim()
    if (-not $t -or $t.StartsWith('#') -or -not $t.Contains('=')) { continue }
    $k, $v = $t.Split('=', 2)
    $k = $k.Trim(); $v = $v.Trim()
    if ($v -like 'state\*') { $v = Join-Path $ProjectRoot $v }
    # Like dotenv: a variable already set in the process wins over .env.
    if (Test-Path "Env:$k") { continue }
    Set-Item -Path "Env:$k" -Value $v
}

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'Machine')
}

function Get-ServerBaseUrl([string]$Server = 'laya') {
    $hostVar, $port = if ($Server -eq 'rune') { $env:RUNE_HOST, $env:RUNE_PORT } else { $env:LAYA_HOST, $env:LAYA_PORT }
    $h = if ($hostVar -in @('0.0.0.0', '', $null)) { '127.0.0.1' } else { $hostVar }
    "http://${h}:$port"
}

function Get-LayaBaseUrl { Get-ServerBaseUrl 'laya' }
