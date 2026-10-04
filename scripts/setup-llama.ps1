# Downloads the pinned llama.cpp release (LLAMA_CPP_RELEASE) as prebuilt Windows zips, one per GPU
# backend, into vendor\llama.cpp\<tag>-<backend>\, then probes each with --version and --list-devices.
# Writes vendor\llama.cpp\<tag>.json (zip SHA-256s and the probe output).
param([string[]]$Backends = @('vulkan', 'rocm'), [switch]$Force)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_env.ps1')
$tag = (Get-Content (Join-Path $ProjectRoot 'LLAMA_CPP_RELEASE') | Where-Object { $_ -and -not $_.StartsWith('#') } | Select-Object -First 1).Trim()
$vendor = Join-Path $ProjectRoot 'vendor\llama.cpp'
New-Item -ItemType Directory -Force $vendor | Out-Null
$zipNames = @{ vulkan = "llama-$tag-bin-win-vulkan-x64.zip"; rocm = "llama-$tag-bin-win-rocm-10.0-x64.zip" }

$record = [ordered]@{ tag = $tag; backends = [ordered]@{} }
foreach ($b in $Backends) {
    $dir = Join-Path $vendor "$tag-$b"
    $zip = Join-Path $vendor $zipNames[$b]
    if ($Force -or -not (Test-Path (Join-Path $dir 'llama-server.exe'))) {
        Write-Host "downloading $($zipNames[$b])"
        # Through Python: GitHub's asset host is behind the Umbrella proxy that Windows does not trust.
        uv run --no-sync --project $ProjectRoot python (Join-Path $PSScriptRoot 'download.py') `
            "https://github.com/ggml-org/llama.cpp/releases/download/$tag/$($zipNames[$b])" $zip
        if ($LASTEXITCODE) { throw "download of $($zipNames[$b]) failed" }
        if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
        Expand-Archive $zip -DestinationPath $dir
    }
    $server = Get-ChildItem $dir -Recurse -Filter llama-server.exe | Select-Object -First 1
    # Through cmd: llama-server prints to stderr, which PowerShell 5.1 turns into terminating errors.
    $version = (cmd /c "`"$($server.FullName)`" --version 2>&1" | Out-String).Trim()
    $devices = (cmd /c "`"$($server.FullName)`" --list-devices 2>&1" | Out-String).Trim()
    $record.backends[$b] = [ordered]@{
        server  = $server.FullName.Substring($ProjectRoot.Length + 1)
        sha256  = if (Test-Path $zip) { (Get-FileHash $zip -Algorithm SHA256).Hash } else { $null }
        version = $version
        devices = $devices
    }
    Write-Host "== $b`n$version`n$devices"
}
$record | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $vendor "$tag.json") -Encoding utf8
