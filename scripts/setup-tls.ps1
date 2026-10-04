# Builds state\certs\ca-bundle.pem (certifi + Cisco Umbrella root) and installs the
# strict-flag hook (tls\local_tls.py) into the venv. Re-run after `uv sync` recreates .venv.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_env.ps1')   # puts uv on PATH
$root = $ProjectRoot
Set-Location $root

$certDir = Join-Path $root 'state\certs'
New-Item -ItemType Directory -Force $certDir | Out-Null
$umbrella = Join-Path $certDir 'cisco-umbrella-root.pem'
if (-not (Test-Path $umbrella)) {
    # Cisco's published Umbrella root. SHA-256 must match the value below.
    $tmp = Join-Path $env:TEMP 'Cisco_Umbrella_Root_CA.cer'
    Invoke-WebRequest 'https://d36u8deuxga9bo.cloudfront.net/certificates/Cisco_Umbrella_Root_CA.cer' -OutFile $tmp -UseBasicParsing
    Copy-Item $tmp $umbrella
}
$cert = New-Object Security.Cryptography.X509Certificates.X509Certificate2($umbrella)
$sha256 = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($cert.RawData)) -replace '-', ''
$expected = '20337C06F749287D526D0752C429483421CE830AC28B322B84B118BE5AF5787D'
if ($sha256 -ne $expected) { throw "Umbrella root fingerprint mismatch: $sha256" }

$certifi = uv run python -c "import certifi;print(certifi.where())"
$bundle = (Get-Content $certifi -Raw) + "`n# Cisco Umbrella Root CA (corporate TLS inspection)`n" + (Get-Content $umbrella -Raw)
Set-Content (Join-Path $certDir 'ca-bundle.pem') $bundle -Encoding ascii -NoNewline

$site = uv run python -c "import sysconfig;print(sysconfig.get_paths()['purelib'])"
Copy-Item (Join-Path $root 'tls\local_tls.py') $site -Force
Set-Content (Join-Path $site 'local_tls.pth') 'import local_tls' -Encoding ascii
Write-Host "CA bundle and TLS hook installed into $site"
