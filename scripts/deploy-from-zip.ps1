<#
.SYNOPSIS
Standalone deploy script - installs the precompiled ROCm 7 files for Ollama
on AMD RX 9070 (XT) / 9060 XT (gfx1201). Bundled inside ollama-rocm-gfx1201.zip
as deploy.ps1.

.DESCRIPTION
Reads the rocm/ subfolder next to this script, stops Ollama, backs up the
existing rocm folder in the Ollama install dir, copies the MIT-licensed
files from the ZIP, then copies amdhip64_7.dll from your local HIP SDK
install (a prerequisite - see README.txt in this archive).

.PARAMETER OllamaPath
Ollama installation directory.
Default: $env:LOCALAPPDATA\Programs\Ollama

.PARAMETER HipPath
HIP SDK installation - source for amdhip64_7.dll.
Default: C:\Program Files\AMD\ROCm\7.1

.PARAMETER NoBackup
Skip creating rocm.bak.<timestamp>; just delete the existing rocm folder.

.PARAMETER StartAfter
Start "ollama serve" in the background after deploying (otherwise launch
Ollama via the Start Menu / tray icon manually).

.EXAMPLE
.\deploy.ps1
Default install. Works with the ZIP extracted as-is.

.EXAMPLE
.\deploy.ps1 -StartAfter
Install and immediately start Ollama.
#>

[CmdletBinding()]
param(
    [string]$OllamaPath = "$env:LOCALAPPDATA\Programs\Ollama",
    [string]$HipPath    = "C:\Program Files\AMD\ROCm\7.1",
    [switch]$NoBackup,
    [switch]$StartAfter
)

$ErrorActionPreference = 'Stop'

function Write-Header($t) { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Cyan }
function Write-Ok($t)     { Write-Host "  [OK]    $t" -ForegroundColor Green }
function Write-Fail($t)   { Write-Host "  [FAIL]  $t" -ForegroundColor Red }
function Die($t)          { Write-Fail $t; exit 1 }

$ScriptDir  = $PSScriptRoot
$SourceRocm = Join-Path $ScriptDir 'rocm'
$TargetRocm = Join-Path $OllamaPath 'lib\ollama\rocm'

Write-Header "Pre-flight checks"

if (-not (Test-Path $SourceRocm)) {
    Write-Fail "rocm\ subfolder not found next to this script."
    Write-Host  "        Expected at: $SourceRocm"
    Write-Host  "        Make sure you extracted the ZIP fully and ran the script"
    Write-Host  "        from inside the extracted folder (not from the ZIP preview)."
    exit 1
}
Write-Ok "Source: $SourceRocm"

$reqFiles = @('ggml-hip.dll','rocblas.dll','libhipblas.dll','libhipblaslt.dll')
foreach ($f in $reqFiles) {
    if (-not (Test-Path (Join-Path $SourceRocm $f))) { Die "Missing in ZIP: $f" }
}
Write-Ok "All MIT-licensed binaries present in ZIP"

if (-not (Test-Path $OllamaPath)) {
    Die "Ollama not installed at: $OllamaPath`n        Install Ollama from https://ollama.com/download first."
}
Write-Ok "Ollama install: $OllamaPath"

$amdHipSource = Join-Path $HipPath 'bin\amdhip64_7.dll'
if (-not (Test-Path $amdHipSource)) {
    Die "HIP SDK 7.1 not found at: $HipPath`n        Expected file: $amdHipSource`n        Install AMD HIP SDK 7.1 from:`n        https://www.amd.com/en/developer/resources/rocm-hub/hip-sdk.html"
}
Write-Ok "HIP SDK: $HipPath  (amdhip64_7.dll found)"

Write-Header "Stopping Ollama"
$procs = Get-Process -Name "ollama*" -ErrorAction SilentlyContinue
if ($procs) {
    foreach ($p in $procs) {
        Write-Host "  Stopping PID $($p.Id) ($($p.ProcessName))"
        try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { Write-Warning "    Could not stop PID $($p.Id)" }
    }
    Start-Sleep -Seconds 2
    $remaining = Get-Process -Name "ollama*" -ErrorAction SilentlyContinue
    if ($remaining) { Die "Ollama still running (PID $($remaining.Id -join ',')). Quit Ollama from the tray icon and retry." }
    Write-Ok "Ollama stopped"
} else { Write-Ok "No Ollama processes running" }

Write-Header "Backing up existing rocm folder"
if (Test-Path $TargetRocm) {
    if ($NoBackup) {
        Remove-Item $TargetRocm -Recurse -Force
        Write-Ok "Existing rocm folder removed (NoBackup)"
    } else {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupDir = "$TargetRocm.bak.$stamp"
        Move-Item $TargetRocm $backupDir -Force
        Write-Ok "Backup at: $backupDir"
    }
} else {
    Write-Ok "No existing rocm folder - nothing to back up"
}

Write-Header "Installing MIT-licensed files from ZIP"
New-Item -ItemType Directory -Force -Path $TargetRocm | Out-Null
Copy-Item -Path "$SourceRocm\*" -Destination $TargetRocm -Recurse -Force
Write-Ok "Copied $(((Get-ChildItem $SourceRocm -Recurse -File).Count)) files into $TargetRocm"

Write-Header "Copying amdhip64_7.dll from HIP SDK"
Copy-Item -Path $amdHipSource -Destination $TargetRocm -Force
Write-Ok "amdhip64_7.dll installed from $amdHipSource"

Write-Header "Verifying installation"
$gfx1201Count = (Get-ChildItem (Join-Path $TargetRocm 'rocblas\library') -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'gfx1201' }).Count
if (-not (Test-Path (Join-Path $TargetRocm 'ggml-hip.dll'))) { Die "ggml-hip.dll missing after install" }
if (-not (Test-Path (Join-Path $TargetRocm 'amdhip64_7.dll'))) { Die "amdhip64_7.dll missing after install" }
if ($gfx1201Count -lt 10) { Write-Warning "Only $gfx1201Count gfx1201 Tensile files found - performance may be reduced" }
Write-Ok "ggml-hip.dll      present"
Write-Ok "amdhip64_7.dll    present (from HIP SDK)"
Write-Ok "gfx1201 kernels   $gfx1201Count files"

if ($StartAfter) {
    Write-Header "Starting Ollama"
    $exe = Join-Path $OllamaPath 'ollama.exe'
    $proc = Start-Process -FilePath $exe -ArgumentList 'serve' -WindowStyle Hidden -PassThru
    Write-Ok "Ollama started (PID $($proc.Id))"
    Write-Host "  Check with: ollama ps"
    Write-Host "  Server log: $env:LOCALAPPDATA\Ollama\server.log"
} else {
    Write-Host ""
    Write-Host "Done. Now start Ollama from the Start Menu / tray icon." -ForegroundColor Green
    Write-Host "Then verify with: ollama ps   (should show '100% GPU' when a model is loaded)"
}
