# Builds .venv-rocm: the same laya install as .venv, but with AMD's ROCm build of torch for the
# Radeon 8060S (gfx1151), so LAYA_DEVICE=cuda runs on the iGPU through HIP.
#
# Keep this venv at a SHORT path: rocBLAS/hipBLASLt Tensile kernel files have ~170-char names,
# and with LongPathsEnabled=0 a deep venv pushes them past MAX_PATH (260). GEMMs then crash with
# 0xC0000005 inside rocblas.dll.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_env.ps1')
Set-Location $ProjectRoot

$venv = Join-Path $ProjectRoot '.venv-rocm'
$torch = 'torch==2.11.0+rocm7.13.0'
uv venv $venv --python 3.13 --allow-existing
uv pip install --python "$venv\Scripts\python.exe" `
    --index-url https://repo.amd.com/rocm/whl/gfx1151/ `
    --extra-index-url https://pypi.org/simple --index-strategy unsafe-best-match `
    $torch 'laya[serve]==0.3.26' psutil
if ($LASTEXITCODE) { exit $LASTEXITCODE }

$longest = (Get-ChildItem $venv -Recurse -File | ForEach-Object { $_.FullName.Length } | Measure-Object -Maximum).Maximum
if ($longest -ge 260) { Write-Warning "longest path in $venv is $longest chars (>= 260): move the project to a shorter path" }

& "$venv\Scripts\python.exe" -c "import torch; assert torch.cuda.is_available(), 'no HIP device'; x=torch.randn(512,512,device='cuda'); (x@x).sum().item(); print('ok', torch.__version__, torch.cuda.get_device_name(0))"
exit $LASTEXITCODE
