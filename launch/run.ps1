# Sets up Paradox on Windows the first time, then starts it.
# Everything it downloads (a private Python, the libraries, the judging models) stays inside this folder,
# so deleting the folder removes all of it and nothing piles up on C:. Only Ollama, if you use it, is installed system-wide.
param([switch]$Brain)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)
$root = $PWD.Path
$plat = "windows-x64"
if (-not (Get-ChildItem "bin\$plat\paradox.*" -ErrorAction SilentlyContinue)) { throw "The Windows build is missing from bin\$plat." }

# Settings from .env (the same file Paradox itself reads): with a cloud API set there, Ollama isn't needed at all.
if (Test-Path .env) {
    foreach ($line in Get-Content .env) {
        if ($line -match '^\s*(PARADOX_LLM_URL|PARADOX_LLM_MODEL)\s*=\s*(.+?)\s*$') {
            if (-not [Environment]::GetEnvironmentVariable($matches[1])) { Set-Item "env:$($matches[1])" $matches[2].Trim('"').Trim("'") }
        }
    }
}
$model = if ($env:PARADOX_LLM_MODEL) { $env:PARADOX_LLM_MODEL } else { "qwen2.5:7b-instruct" }
$url = if ($env:PARADOX_LLM_URL) { $env:PARADOX_LLM_URL } else { "http://localhost:11434/v1" }

function Have($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }
function Refresh-Path { $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User") }

if ($url -match "localhost:11434|127\.0\.0\.1:11434") {
    if (-not (Have "ollama")) {
        Write-Host "Installing Ollama..."
        winget install -e --id Ollama.Ollama --accept-package-agreements --accept-source-agreements
        Refresh-Path
    }
    try { Invoke-RestMethod http://localhost:11434/api/tags -TimeoutSec 3 | Out-Null }
    catch { Start-Process ollama -ArgumentList "serve" -WindowStyle Hidden; Start-Sleep 5 }
    ollama pull $model
} else {
    Write-Host "Using $model at $url (from .env), so no local model is downloaded."
}

# A private Python 3.12 and its libraries, set up once by uv, all inside .tools and .venv.
$env:UV_INSTALL_DIR = Join-Path $root ".tools\uv"
$env:UV_PYTHON_INSTALL_DIR = Join-Path $root ".tools\python"
$env:UV_CACHE_DIR = Join-Path $root ".tools\cache"
$env:UV_NO_MODIFY_PATH = "1"
$uv = Join-Path $env:UV_INSTALL_DIR "uv.exe"
if (-not (Test-Path $uv)) {
    Write-Host "Getting uv (sets up Python for Paradox)..."
    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://astral.sh/uv/install.ps1 | iex" | Out-Null
    if (-not (Test-Path $uv)) { throw "Could not get uv. Check the internet connection and start again." }
}
if ((Test-Path .venv) -and -not (Test-Path .venv\Scripts\python.exe)) { Remove-Item -Recurse -Force .venv }
if (-not (Test-Path .venv\Scripts\python.exe)) {
    Write-Host "Setting up Python 3.12 and the libraries (first run only)..."
    & $uv venv --python 3.12 .venv -q
    & $uv pip install --python .venv\Scripts\python.exe -q torch --index-url https://download.pytorch.org/whl/cpu
    & $uv pip install --python .venv\Scripts\python.exe -q -r requirements.txt
    if (-not (Test-Path .venv\Scripts\python.exe)) { throw "Could not set up Python." }
}

$env:PYTHONPATH = Join-Path $root "bin\$plat"
$env:PYTHONIOENCODING = "utf-8"
$env:HF_HOME = Join-Path $root "models"
$env:PARADOX_HOME = Join-Path $root "data"
$env:PARADOX_UI = Join-Path $root "ui\dist\index.html"
if ($Brain) {
    Write-Host "Starting the brain at http://localhost:8100 (close this window to stop)"
    Start-Job { Start-Sleep 6; Start-Process "http://localhost:8100" } | Out-Null
    .\.venv\Scripts\python -m uvicorn paradox.api:app --port 8100
} else {
    .\.venv\Scripts\python launch\paradox_cli.py --trace @args
}
