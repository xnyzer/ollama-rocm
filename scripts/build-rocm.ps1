<#
.SYNOPSIS
Baut Ollama mit ROCm-Support fuer RX 9070 XT (gfx1201) - reproduzierbar.

.DESCRIPTION
Fuenf Modi:

  Check       Pre-flight: prueft alle Tools (Git, CMake, Ninja, VS 2022 BuildTools,
              HIP SDK 7.1) und meldet was fehlt - mit Install-Kommando.

  Configure   Nur CMake Configure. Schnell. Bei Konfig-Iteration nuetzlich.

  Build       Configure + Build + Install. Default-Modus.

  All         Build + Snapshot (Master-Kopie + ZIP fuer Deploy bereitlegen).

  Clean       Loescht build/ und dist/-Output im Ollama-Quellbaum.

.PARAMETER Mode
  Check | Configure | Build | All | Clean   - Default: Build

.PARAMETER OllamaSourcePath
  Pfad zum Ollama-git-Klon. Default: <repo>/ollama.
  Muss CMakeLists.txt + CMakePresets.json enthalten.

.PARAMETER HipPath
  HIP-SDK-Installation. Default: C:\Program Files\AMD\ROCm\7.1

.PARAMETER AmdGpuTargets
  GPU-Architekturen. Default: "gfx1201" (RX 9070 XT).
  Mehrere durch Semikolon trennen, z.B. "gfx1200;gfx1201".

.PARAMETER Preset
  CMake-Preset aus ollama/CMakePresets.json. Default: "ROCm 7"

.PARAMETER ParallelJobs
  Parallele Compile-Jobs. Default: 4.
  WARNUNG: >=8 kann Race-Condition in topk-moe.cu verursachen (Compiler-Crash
  ohne klare Fehlermeldung).

.PARAMETER ExpectedTag
  Erwarteter Git-Tag/Commit im Ollama-Klon. Default: "v0.24.0".
  Nur Warnung bei Abweichung, kein Abbruch.

.PARAMETER NoSnapshot
  Bei -Mode All: Build aber kein Snapshot.

.EXAMPLE
  .\scripts\build-rocm.ps1 -Mode Check
  Prueft ob alle Tools installiert sind. Schlaegt mit klarer Meldung an wenn etwas fehlt.

.EXAMPLE
  .\scripts\build-rocm.ps1
  Standardbuild: Configure + Build + Install.

.EXAMPLE
  .\scripts\build-rocm.ps1 -Mode All
  Vollstaendiger Workflow inkl. Snapshot - direkt fuer Deploy bereit.

.EXAMPLE
  .\scripts\build-rocm.ps1 -AmdGpuTargets "gfx1200;gfx1201"
  Baut fuer RX 9060 XT (gfx1200) + RX 9070/9070 XT (gfx1201).
#>

[CmdletBinding()]
param(
    [ValidateSet('Check','Configure','Build','All','Clean')]
    [string]$Mode = 'Build',

    [string]$OllamaSourcePath,
    [string]$HipPath = "C:\Program Files\AMD\ROCm\7.1",
    [string]$AmdGpuTargets = "gfx1201",
    [string]$Preset = "ROCm 7",
    [int]$ParallelJobs = 4,
    [string]$ExpectedTag = "v0.24.0",
    [switch]$NoSnapshot
)

$ErrorActionPreference = 'Stop'

# --- Pfade -------------------------------------------------------------------
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OllamaSourcePath) { $OllamaSourcePath = Join-Path $RepoRoot 'ollama' }
$BuildDir   = Join-Path $OllamaSourcePath 'build\rocm'
$InstallDir = Join-Path $OllamaSourcePath 'dist'

# --- Output-Helper -----------------------------------------------------------
function Write-Header($text) { Write-Host ""; Write-Host "=== $text ===" -ForegroundColor Cyan }
function Write-Ok($text)     { Write-Host "  [OK]   $text" -ForegroundColor Green }
function Write-Warn($text)   { Write-Host "  [WARN] $text" -ForegroundColor Yellow }
function Write-Fail($text)   { Write-Host "  [FAIL] $text" -ForegroundColor Red }
function Write-Info($text)   { Write-Host "  $text" }

# --- Pre-flight Checks -------------------------------------------------------

function Get-CommandSource($name) {
    # PATH-Update fuer aktuellen Aufruf
    $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
    return (Get-Command $name -ErrorAction SilentlyContinue).Source
}

function Test-Git {
    $src = Get-CommandSource 'git'
    if (-not $src) {
        Write-Fail "git fehlt"
        Write-Info "  Install: winget install Git.Git -e"
        return $false
    }
    $ver = (& git --version) -replace '^git version ',''
    Write-Ok "git $ver  ($src)"
    return $true
}

function Test-CMake {
    $src = Get-CommandSource 'cmake'
    if (-not $src) {
        Write-Fail "cmake fehlt"
        Write-Info "  Install: winget install Kitware.CMake -e"
        return $false
    }
    $verLine = (& cmake --version | Select-Object -First 1)
    if ($verLine -match 'cmake version (\d+)\.(\d+)') {
        $major = [int]$matches[1]; $minor = [int]$matches[2]
        if (($major -lt 3) -or ($major -eq 3 -and $minor -lt 21)) {
            Write-Fail "cmake $major.$minor zu alt (mind. 3.21 noetig)"
            return $false
        }
    }
    Write-Ok "$verLine  ($src)"
    return $true
}

function Test-Ninja {
    $src = Get-CommandSource 'ninja'
    if (-not $src) {
        Write-Fail "ninja fehlt"
        Write-Info "  Install: winget install Ninja-build.Ninja -e"
        return $false
    }
    $ver = (& ninja --version)
    Write-Ok "ninja $ver  ($src)"
    return $true
}

function Test-Vs2022BuildTools {
    $vswhere = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        Write-Fail "vswhere.exe nicht gefunden - kein Visual Studio installiert?"
        Write-Info "  Install: winget install Microsoft.VisualStudio.2022.BuildTools -e ``"
        Write-Info "           --override `"--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended`""
        return $false
    }
    $vs2022 = & $vswhere -version "[17.0,18.0)" -products "*" -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vs2022) {
        Write-Fail "VS 2022 BuildTools mit C++-Workload nicht gefunden"
        Write-Info "  Install: winget install Microsoft.VisualStudio.2022.BuildTools -e ``"
        Write-Info "           --override `"--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended`""
        return $false
    }
    $vcvars = Join-Path $vs2022 'VC\Auxiliary\Build\vcvars64.bat'
    if (-not (Test-Path $vcvars)) {
        Write-Fail "vcvars64.bat fehlt unter $vcvars"
        return $false
    }
    # MSVC-Version aus VC\Tools\MSVC\<version>
    $msvcDir = Get-ChildItem (Join-Path $vs2022 'VC\Tools\MSVC') -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($msvcDir) {
        $msvcVer = $msvcDir.Name
        Write-Ok "VS 2022 BuildTools  ($vs2022)"
        Write-Ok "MSVC $msvcVer"
        if ($msvcVer -match '^14\.5[1-9]' -or $msvcVer -match '^14\.[6-9]' -or $msvcVer -match '^1[5-9]\.') {
            Write-Warn "MSVC $msvcVer ist neuer als 14.4x - moeglicher cmath/__clang_hip-Header-Konflikt"
        }
    } else {
        Write-Warn "MSVC-Toolset nicht erkennbar"
    }
    return $true
}

function Test-HipSdk {
    if (-not (Test-Path $HipPath)) {
        Write-Fail "HIP SDK nicht gefunden: $HipPath"
        Write-Info "  Download: https://www.amd.com/en/developer/resources/rocm-hub/hip-sdk.html"
        return $false
    }
    $hipcc = Join-Path $HipPath 'bin\hipcc.exe'
    $hipclang = Join-Path $HipPath 'bin\clang++.exe'
    if (-not (Test-Path $hipcc))    { Write-Fail "hipcc.exe fehlt unter $hipcc"; return $false }
    if (-not (Test-Path $hipclang)) { Write-Fail "clang++.exe fehlt unter $hipclang"; return $false }
    # Version-Output (hipcc --version)
    $hipVer = (& $hipcc --version 2>&1) | Select-String -Pattern 'HIP version:' | ForEach-Object { ($_ -split ':',2)[1].Trim() }
    Write-Ok "HIP SDK $hipVer  ($HipPath)"
    return $true
}

function Test-Gpu {
    $hipinfo = Join-Path $HipPath 'bin\hipinfo.exe'
    if (-not (Test-Path $hipinfo)) {
        Write-Warn "hipinfo.exe nicht gefunden - kann GPU nicht verifizieren"
        return $true
    }
    $info = & $hipinfo 2>&1
    $gcnArch = $info | Select-String -Pattern 'gcnArchName' | ForEach-Object { ($_ -split ':',2)[1].Trim() }
    $name    = $info | Select-String -Pattern '^Name:'      | ForEach-Object { ($_ -split ':',2)[1].Trim() } | Select-Object -First 1
    if (-not $gcnArch) {
        Write-Warn "Keine GPU via hipinfo erkannt"
        return $true
    }
    Write-Ok "GPU: $name  (gcnArchName: $gcnArch)"
    $targets = $AmdGpuTargets -split ';'
    $match = $targets | Where-Object { $gcnArch -match $_ }
    if (-not $match) {
        Write-Warn "GPU gcnArchName '$gcnArch' nicht in Build-Targets ($AmdGpuTargets)"
        Write-Info "  -AmdGpuTargets `"$gcnArch`" zum Build hinzufuegen oder ignorieren"
    }
    return $true
}

function Test-OllamaSource {
    if (-not (Test-Path $OllamaSourcePath)) {
        Write-Fail "Ollama-Source nicht gefunden: $OllamaSourcePath"
        Write-Info "  Holen: git clone https://github.com/ollama/ollama.git `"$OllamaSourcePath`""
        Write-Info "         git -C `"$OllamaSourcePath`" checkout $ExpectedTag"
        return $false
    }
    if (-not (Test-Path (Join-Path $OllamaSourcePath 'CMakeLists.txt'))) {
        Write-Fail "$OllamaSourcePath enthaelt keine CMakeLists.txt"
        return $false
    }
    if (-not (Test-Path (Join-Path $OllamaSourcePath 'CMakePresets.json'))) {
        Write-Fail "$OllamaSourcePath enthaelt keine CMakePresets.json"
        return $false
    }
    # Git-Status
    $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
    $headInfo = & git -C $OllamaSourcePath log -1 --pretty=format:"%h %d %s" 2>$null
    Write-Ok "Ollama-Source: $OllamaSourcePath"
    Write-Info "  HEAD: $headInfo"
    if ($headInfo -notmatch [regex]::Escape($ExpectedTag)) {
        Write-Warn "Erwarteter Tag $ExpectedTag nicht in HEAD-Referenzen - Build kann trotzdem klappen"
    }
    return $true
}

function Invoke-Check {
    Write-Header "Pre-flight Check"
    $allOk = $true
    $allOk = (Test-Git)             -and $allOk
    $allOk = (Test-CMake)           -and $allOk
    $allOk = (Test-Ninja)           -and $allOk
    $allOk = (Test-Vs2022BuildTools)-and $allOk
    $allOk = (Test-HipSdk)          -and $allOk
    Test-Gpu | Out-Null  # informativ, nicht blockierend
    $allOk = (Test-OllamaSource)    -and $allOk

    Write-Host ""
    if ($allOk) {
        Write-Host "Alle Voraussetzungen erfuellt. Bereit fuer '.\scripts\build-rocm.ps1 -Mode Build'." -ForegroundColor Green
    } else {
        Write-Host "Voraussetzungen unvollstaendig - siehe [FAIL]-Eintraege oben." -ForegroundColor Red
        exit 1
    }
}

# --- Build Environment -------------------------------------------------------

function Initialize-BuildEnvironment {
    Write-Header "Build-Environment laden"
    # PATH refresh
    $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")

    # vcvars64.bat (VS 2022 BuildTools)
    $vswhere = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
    $vs2022 = & $vswhere -version "[17.0,18.0)" -products "*" -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vs2022) { throw "VS 2022 BuildTools nicht gefunden - 'Check' ausfuehren." }
    $vcvars = Join-Path $vs2022 'VC\Auxiliary\Build\vcvars64.bat'
    $vcvarsOut = cmd /c "`"$vcvars`" 2>&1 && set"
    foreach ($line in $vcvarsOut) {
        if ($line -match '^([^=]+)=(.*)$') { Set-Item -Path "env:$($matches[1])" -Value $matches[2] -ErrorAction SilentlyContinue }
    }
    Write-Ok "vcvars64 geladen ($vs2022)"

    # ROCm-Env (Pattern aus scripts/build_windows.ps1 der Ollama-CI)
    $env:HIPCXX            = Join-Path $HipPath 'bin\clang++.exe'
    $env:HIP_PLATFORM      = "amd"
    $env:CMAKE_PREFIX_PATH = $HipPath
    $env:CC                = Join-Path $HipPath 'bin\clang.exe'
    $env:CXX               = Join-Path $HipPath 'bin\clang++.exe'
    Write-Ok "ROCm-Env: HIPCXX, CC, CXX -> $HipPath\bin\clang(++).exe"
}

# --- Configure / Build / Install ---------------------------------------------

function Invoke-Configure {
    Write-Header "CMake Configure"
    Write-Info "Source:   $OllamaSourcePath"
    Write-Info "Build:    $BuildDir"
    Write-Info "Preset:   $Preset"
    Write-Info "Targets:  $AmdGpuTargets"

    if (Test-Path $BuildDir) {
        Write-Info "Alter Build-Dir wird geloescht (frisches Configure)..."
        Remove-Item -Recurse -Force $BuildDir
    }

    Push-Location $OllamaSourcePath
    try {
        & cmake -B build\rocm --preset "$Preset" -G Ninja `
            -DCMAKE_HIP_COMPILER="$($HipPath -replace '\\','/')/bin/clang++.exe" `
            -DCMAKE_HIP_PLATFORM=amd `
            -DCMAKE_C_FLAGS="-parallel-jobs=4 -Wno-ignored-attributes -Wno-deprecated-pragma" `
            -DCMAKE_CXX_FLAGS="-parallel-jobs=4 -Wno-ignored-attributes -Wno-deprecated-pragma" `
            -DAMDGPU_TARGETS="$AmdGpuTargets"
        if ($LASTEXITCODE -ne 0) { throw "cmake configure schlug fehl (Exit $LASTEXITCODE)" }
    } finally { Pop-Location }
    Write-Ok "Configure erfolgreich"
}

function Invoke-BuildStep {
    Write-Header "Build (target=ggml-hip, parallel=$ParallelJobs)"
    if (-not (Test-Path $BuildDir)) { throw "Kein Build-Dir - erst Configure ausfuehren." }
    Push-Location $OllamaSourcePath
    try {
        $start = Get-Date
        & cmake --build build\rocm --target ggml-hip --config Release --parallel $ParallelJobs
        if ($LASTEXITCODE -ne 0) { throw "Build schlug fehl (Exit $LASTEXITCODE). Bei undefined Compiler-Crash: -ParallelJobs auf 4 oder 2 reduzieren." }
        $dur = ((Get-Date) - $start).TotalMinutes
        Write-Ok ("Build erfolgreich in {0:N1} Min" -f $dur)
    } finally { Pop-Location }
}

function Invoke-InstallStep {
    Write-Header "Install --component HIP"
    if (Test-Path $InstallDir) { Remove-Item -Recurse -Force $InstallDir }
    Push-Location $OllamaSourcePath
    try {
        & cmake --install build\rocm --component HIP --strip --prefix "$InstallDir"
        if ($LASTEXITCODE -ne 0) { throw "Install schlug fehl (Exit $LASTEXITCODE)" }
    } finally { Pop-Location }
    $rocmOut = Join-Path $InstallDir 'lib\ollama\rocm'
    if (-not (Test-Path (Join-Path $rocmOut 'amdhip64_7.dll'))) {
        throw "Install unvollstaendig - amdhip64_7.dll fehlt"
    }
    $sizeMB = [math]::Round(((Get-ChildItem $rocmOut -Recurse -File | Measure-Object Length -Sum).Sum / 1MB), 1)
    Write-Ok "Install nach $rocmOut ($sizeMB MB)"
}

function Invoke-Clean {
    Write-Header "Clean"
    if (Test-Path $BuildDir) {
        Remove-Item -Recurse -Force $BuildDir
        Write-Ok "geloescht: $BuildDir"
    } else { Write-Info "kein build/rocm vorhanden" }
    if (Test-Path $InstallDir) {
        Remove-Item -Recurse -Force $InstallDir
        Write-Ok "geloescht: $InstallDir"
    } else { Write-Info "kein dist/ vorhanden" }
}

function Invoke-Snapshot {
    Write-Header "Snapshot (via rocm-deploy.ps1)"
    $deployScript = Join-Path $PSScriptRoot 'rocm-deploy.ps1'
    if (-not (Test-Path $deployScript)) { Write-Warn "rocm-deploy.ps1 nicht gefunden - ueberspringe Snapshot"; return }
    & powershell -ExecutionPolicy Bypass -File $deployScript -Mode Snapshot
    if ($LASTEXITCODE -ne 0) { Write-Warn "Snapshot schlug fehl (Exit $LASTEXITCODE)" }
}

# --- Entry Point -------------------------------------------------------------

switch ($Mode) {
    'Check' {
        Invoke-Check
    }
    'Configure' {
        Initialize-BuildEnvironment
        Invoke-Configure
    }
    'Build' {
        Initialize-BuildEnvironment
        Invoke-Configure
        Invoke-BuildStep
        Invoke-InstallStep
        Write-Host ""
        Write-Host "Fertig. Naechster Schritt:" -ForegroundColor Green
        Write-Host "  .\scripts\rocm-deploy.ps1 -Mode Snapshot   # Master-Kopie + ZIP"
        Write-Host "  .\scripts\rocm-deploy.ps1                  # ins Ollama-Verzeichnis"
    }
    'All' {
        Initialize-BuildEnvironment
        Invoke-Configure
        Invoke-BuildStep
        Invoke-InstallStep
        if (-not $NoSnapshot) { Invoke-Snapshot }
        Write-Host ""
        Write-Host "Komplett fertig - bereit fuer Deploy:" -ForegroundColor Green
        Write-Host "  .\scripts\rocm-deploy.ps1"
    }
    'Clean' {
        Invoke-Clean
    }
}
