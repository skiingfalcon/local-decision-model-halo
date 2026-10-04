# Health check plus one typed-decision request (choice + score + noul) against a running server.
#   -Server rune (default) | laya;  -Model picks a Laya checkpoint (english / typed-decisions / multilingual)
param([ValidateSet('laya', 'rune')][string]$Server = 'rune', [string]$Model = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_env.ps1')
$base = Get-ServerBaseUrl $Server
$key = if ($Server -eq 'rune') { $env:RUNE_API_KEY } else { $env:LAYA_API_KEY }
$headers = @{}
if ($key) { $headers['Authorization'] = "Bearer $key" }

$health = Invoke-RestMethod "$base/health" -Headers $headers -TimeoutSec 10
Write-Host "health:" ($health | ConvertTo-Json -Depth 5 -Compress)

$body = @{
    state     = @{
        subject = 'Duplicate charge'
        body    = 'We were billed twice for March. Please refund the duplicate today or we will cancel.'
    }
    questions = @{
        department = @{
            type         = 'choice'
            instructions = 'Which team should handle this request?'
            criteria     = @{ billing = 'invoices, payments, refunds'; technical = 'bugs, outages, errors'; other = 'everything else' }
        }
        urgency    = @{ type = 'score'; instructions = 'How urgent is the request?'; criteria = @('routine', 'soon', 'blocking') }
        churn_risk = @{ type = 'noul'; instructions = 'Does the customer explicitly threaten to cancel?' }
    }
}
if ($Model) { $body['model'] = $Model }

$sw = [Diagnostics.Stopwatch]::StartNew()
$r = Invoke-RestMethod "$base/v1/systemone" -Method Post -Headers $headers -ContentType 'application/json' `
    -Body ($body | ConvertTo-Json -Depth 6) -TimeoutSec 120
$sw.Stop()

$a = $r.answers
Write-Host ("department = {0}  urgency = {1}  churn_risk P(true) = {2:N3}" -f $a.department.choice, $a.urgency.score, $a.churn_risk.noul)
$servedBy = if ($r.routing.model) { $r.routing.model } else { $Server }
Write-Host ("answered by {0} ({1} input tokens); round trip {2} ms" -f $servedBy, $r.usage.input_tokens, $sw.ElapsedMilliseconds)
if ($a.department.choice -ne 'billing') { Write-Warning 'expected department=billing'; exit 1 }
