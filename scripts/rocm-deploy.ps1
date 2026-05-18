<#
.SYNOPSIS
Verwaltet die ROCm-7-DLLs fuer Ollama auf RX 9070 XT (gfx1201).

.DESCRIPTION
Drei Modi:

  Deploy   (Default) Kopiert die ROCm-7-DLLs aus der Master-Kopie ins Ollama-Programm-
                    verzeichnis. Stoppt vorher Ollama, sichert bestehenden rocm-Ordner
                    als rocm.bak.<timestamp>. Holt zusaetzlich amdhip64_7.dll aus dem
                    HIP SDK des Nutzers (proprietaere AMD-Datei, daher NICHT in der
                    Master-Kopie / im verteilten ZIP).
                    Nach jedem Ollama-Update oder Neuinstallation aufrufen.

  Snapshot          Macht eine neue Master-Kopie aus dem Build-Output. Erstellt
                    zusaetzlich ein ZIP-Archiv. Filtert dabei AMD-proprietaere Dateien
                    (amdhip64_*.dll) heraus - die landen nur lokal, nicht im ZIP zum
                    Verteilen.
                    Nach jedem erfolgreichen Self-Build aufrufen.

  Verify            Prueft (ohne Aenderungen), ob die aktuell deployten DLLs unsere
                    ROCm-7-Build-Version sind.

.PARAMETER Mode
  Deploy | Snapshot | Verify  - Default: Deploy

.PARAMETER SourcePath
  Quelle fuer Deploy oder Snapshot.
  Bei Deploy:   Master-Kopie (default: <repo>\dist\rocm-gfx1201)
  Bei Snapshot: Build-Output (default: <repo>\ollama\dist\lib\ollama\rocm)

.PARAMETER OllamaPath
  Ollama-Installationsverzeichnis (default: $env:LOCALAPPDATA\Programs\Ollama)

.PARAMETER HipPath
  HIP-SDK-Installation - Quelle fuer amdhip64_7.dll beim Deploy.
  Default: C:\Program Files\AMD\ROCm\7.1

.PARAMETER NoBackup
  Beim Deploy KEIN Backup des bestehenden rocm-Ordners anlegen.

.PARAMETER SkipServiceStop
  Beim Deploy NICHT versuchen, Ollama-Prozesse zu beenden.

.PARAMETER StartAfter
  Nach Deploy "ollama serve" als Hintergrundprozess starten.

.EXAMPLE
  .\scripts\rocm-deploy.ps1
  Standard-Deploy nach Ollama-Update.

.EXAMPLE
  .\scripts\rocm-deploy.ps1 -Mode Snapshot
  Nach erfolgreichem Build die Master-Kopie + ZIP aktualisieren.

.EXAMPLE
  .\scripts\rocm-deploy.ps1 -Mode Verify
  Schnell-Check ob nach einem Update noch unsere DLLs aktiv sind.
#>

[CmdletBinding()]
param(
    [ValidateSet('Deploy','Snapshot','Verify')]
    [string]$Mode = 'Deploy',

    [string]$SourcePath,

    [string]$OllamaPath = "$env:LOCALAPPDATA\Programs\Ollama",

    [string]$HipPath = "C:\Program Files\AMD\ROCm\7.1",

    [switch]$NoBackup,

    [switch]$SkipServiceStop,

    [switch]$StartAfter
)

$ErrorActionPreference = 'Stop'

# --- Pfad-Konstanten ---------------------------------------------------------
$RepoRoot      = Split-Path -Parent $PSScriptRoot
$MasterCopy    = Join-Path $RepoRoot 'dist\rocm-gfx1201'
$ZipPath       = Join-Path $RepoRoot 'dist\ollama-rocm-gfx1201.zip'
$BuildOutput   = Join-Path $RepoRoot 'ollama\dist\lib\ollama\rocm'
$RocmDir       = Join-Path $OllamaPath 'lib\ollama\rocm'

# AMD-proprietaere Dateien: NICHT in Master-Kopie / ZIP - werden beim Deploy
# aus dem lokalen HIP SDK des Nutzers kopiert (rechtlich saubere Trennung).
$HipSdkOnlyFiles = @('amdhip64_7.dll')

# --- Helpers -----------------------------------------------------------------

function Write-Header($text) {
    Write-Host ""
    Write-Host "=== $text ===" -ForegroundColor Cyan
}

# Marker fuer einen Self-Build gfx1201: ggml-hip.dll + mindestens ein Tensile-
# File fuer gfx1201 in rocblas/library/. Funktioniert fuer beide Faelle (Master-
# Kopie OHNE amdhip64_7.dll und Deploy MIT).
function Test-HasGfx1201Build([string]$path) {
    if (-not (Test-Path $path)) { return $false }
    if (-not (Test-Path (Join-Path $path 'ggml-hip.dll'))) { return $false }
    $libDir = Join-Path $path 'rocblas\library'
    if (-not (Test-Path $libDir)) { return $false }
    $hit = Get-ChildItem $libDir -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'gfx1201' } | Select-Object -First 1
    return ($null -ne $hit)
}

function Stop-OllamaService {
    $procs = Get-Process -Name "ollama*" -ErrorAction SilentlyContinue
    if (-not $procs) { Write-Host "  Keine Ollama-Prozesse aktiv"; return }
    foreach ($p in $procs) {
        Write-Host "  Stoppe PID $($p.Id) ($($p.ProcessName))"
        try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { Write-Warning "    Konnte PID $($p.Id) nicht stoppen: $($_.Exception.Message)" }
    }
    Start-Sleep -Seconds 2
    $remaining = Get-Process -Name "ollama*" -ErrorAction SilentlyContinue
    if ($remaining) { throw "Ollama-Prozesse haengen weiter (PIDs: $($remaining.Id -join ',')) - bitte manuell ueber Tray beenden und erneut versuchen." }
}

function Get-FolderSizeMB([string]$path) {
    if (-not (Test-Path $path)) { return 0 }
    $bytes = (Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    return [math]::Round(($bytes / 1MB), 1)
}

function Copy-HipSdkFiles([string]$targetDir) {
    # Holt die AMD-proprietaeren Dateien aus dem lokalen HIP SDK ins Ziel.
    # Voraussetzung: HIP SDK ist installiert (sollte sein, weil Ollama es zur Laufzeit braucht).
    $hipBin = Join-Path $HipPath 'bin'
    if (-not (Test-Path $hipBin)) {
        throw "HIP SDK nicht gefunden unter '$HipPath\bin\'. Bitte HIP SDK 7.1 installieren: https://www.amd.com/en/developer/resources/rocm-hub/hip-sdk.html"
    }
    foreach ($f in $HipSdkOnlyFiles) {
        $src = Join-Path $hipBin $f
        if (-not (Test-Path $src)) { throw "Erwartete HIP-SDK-Datei fehlt: $src" }
        Copy-Item -Path $src -Destination (Join-Path $targetDir $f) -Force
        Write-Host "  Kopiert aus HIP SDK: $f"
    }
}

# --- Modi --------------------------------------------------------------------

function Invoke-Snapshot {
    Write-Header "Snapshot - Master-Kopie aktualisieren"

    if (-not $SourcePath) { $SourcePath = $BuildOutput }

    if (-not (Test-Path $SourcePath)) { throw "Quelle nicht gefunden: $SourcePath`nLaeuft der Build (cmake --install build\rocm --component HIP) sauber durch?" }
    if (-not (Test-HasGfx1201Build $SourcePath)) { throw "Quelle '$SourcePath' enthaelt keine gfx1201-Tensile-Files - Self-Build vermutlich nicht durchgelaufen oder falsche Target-Architektur." }

    Write-Host "  Quelle: $SourcePath ($((Get-FolderSizeMB $SourcePath)) MB)"
    Write-Host "  Ziel:   $MasterCopy"

    if (Test-Path $MasterCopy) {
        Write-Host "  Alte Master-Kopie loeschen ..."
        Remove-Item $MasterCopy -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $MasterCopy | Out-Null
    Copy-Item -Path "$SourcePath\*" -Destination $MasterCopy -Recurse -Force

    Write-Header "AMD-proprietaere Dateien aus Master-Kopie/ZIP herausfiltern"
    foreach ($f in $HipSdkOnlyFiles) {
        $p = Join-Path $MasterCopy $f
        if (Test-Path $p) {
            Remove-Item $p -Force
            Write-Host "  Entfernt: $f  (wird beim Deploy aus dem HIP SDK des Nutzers geholt)"
        }
    }
    Write-Host "  Master-Kopie netto: $((Get-FolderSizeMB $MasterCopy)) MB"

    Write-Header "ZIP-Archiv erstellen (Subfolder-Struktur + deploy.ps1)"
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }

    # Staging-Struktur:
    #   <staging>\rocm\*       (alle ROCm-Files in einem Subfolder)
    #   <staging>\deploy.ps1   (standalone Deploy-Script)
    #   <staging>\LICENSE
    #   <staging>\THIRD_PARTY_LICENSES.md
    #   <staging>\README.txt
    $staging = Join-Path $env:TEMP "ollama-rocm-zip-staging-$(Get-Random)"
    $stagingRocm = Join-Path $staging 'rocm'
    New-Item -ItemType Directory -Force -Path $stagingRocm | Out-Null
    try {
        Copy-Item "$MasterCopy\*" -Destination $stagingRocm -Recurse -Force
        Write-Host "  ROCm-Files in $stagingRocm gestaget"

        $licFiles = @('LICENSE','THIRD_PARTY_LICENSES.md')
        foreach ($lf in $licFiles) {
            $src = Join-Path $RepoRoot $lf
            if (Test-Path $src) {
                Copy-Item $src $staging
                Write-Host "  Lizenz-Datei mitverpackt: $lf"
            } else { Write-Warning "$lf nicht im Repo gefunden - ZIP ohne diese Lizenz-Notice" }
        }

        # Standalone deploy-Script aus dem Repo als deploy.ps1 ins ZIP-Root
        $standaloneSrc = Join-Path $PSScriptRoot 'deploy-from-zip.ps1'
        if (Test-Path $standaloneSrc) {
            Copy-Item $standaloneSrc (Join-Path $staging 'deploy.ps1')
            Write-Host "  Standalone deploy.ps1 eingebettet"
        } else { Write-Warning "deploy-from-zip.ps1 nicht gefunden - ZIP ohne Standalone-Script" }

        $zipReadme = @"
ollama-rocm-gfx1201 - precompiled ROCm 7 binaries for Ollama on AMD
RDNA 4 GPUs (RX 9070, RX 9070 XT, RX 9060 XT - gfx1201).

CONTENTS
========
  rocm\                       Folder with all MIT-licensed binaries:
    ggml-hip.dll              MIT (built from ollama/ollama source)
    rocblas.dll               MIT (AMD ROCm/rocBLAS)
    rocblas\library\*         MIT (rocBLAS Tensile kernels for gfx1201)
    libhipblas.dll            MIT (AMD ROCm/hipBLAS)
    libhipblaslt.dll          MIT (AMD ROCm/hipBLASLt)
  deploy.ps1                  Standalone install script (this archive)
  LICENSE                     MIT license of this packaging
  THIRD_PARTY_LICENSES.md     MIT licenses of each upstream component
  README.txt                  This file

NOT INCLUDED (intentionally, for license-compliance reasons)
============================================================
amdhip64_7.dll is part of AMD's proprietary HIP runtime. It is NOT
redistributed. The deploy script copies it at install time from your
own HIP SDK 7.1 installation (a prerequisite anyway, see below).

HOW TO INSTALL
==============
Prerequisites (one-time):
  1. AMD Adrenalin driver 26.x or newer:
     https://www.amd.com/en/support
  2. AMD HIP SDK 7.1:
     https://www.amd.com/en/developer/resources/rocm-hub/hip-sdk.html
     (default install path: C:\Program Files\AMD\ROCm\7.1\)
  3. Ollama 0.24 or newer:
     https://ollama.com/download

Then:
  1. Extract this ZIP somewhere (anywhere - Desktop, Downloads, ...)
  2. Open the extracted folder
  3. Right-click 'deploy.ps1' -> 'Run with PowerShell'
     (or in a PowerShell window: .\deploy.ps1)
  4. Start Ollama from the Start Menu / tray icon
  5. Verify: open PowerShell, run 'ollama run deepseek-r1:14b'
     then in another PowerShell: 'ollama ps' should show '100% GPU'

VERIFY IT WORKS
===============
After deploy + Ollama start + first model load, run:

    ollama ps

Expected output (PROCESSOR column):

    NAME               PROCESSOR    CONTEXT    UNTIL
    deepseek-r1:14b    100% GPU     4096       4 minutes from now

If you see '100% CPU' instead, see the README on GitHub for troubleshooting.

PROJECT PAGE
============
https://github.com/xnyzer/ollama-rocm

"@
        $zipReadme | Set-Content (Join-Path $staging 'README.txt') -Encoding ascii
        Write-Host "  README.txt eingebettet"

        Compress-Archive -Path "$staging\*" -DestinationPath $ZipPath -CompressionLevel Optimal
    } finally {
        Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
    $zipMB = [math]::Round(((Get-Item $ZipPath).Length / 1MB), 1)
    Write-Host "  Erstellt: $ZipPath ($zipMB MB)"

    Write-Header "Snapshot fertig"
    Write-Host "  Master:  $MasterCopy"
    Write-Host "  Archiv:  $ZipPath  (sicher zum Verteilen - nur MIT-lizenzierte Dateien + Lizenz-Texte + deploy.ps1)"
    Write-Host ""
    Write-Host "Naechster Schritt: '.\scripts\rocm-deploy.ps1' fuer Deployment."
}

function Invoke-Deploy {
    Write-Header "Deploy - ROCm-7-DLLs nach Ollama-Programmverzeichnis"

    if (-not $SourcePath) { $SourcePath = $MasterCopy }

    # Fallback: keine Master-Kopie? Versuch direkt aus Build-Output (enthaelt amdhip64_7.dll, kein Verlust).
    if (-not (Test-Path $SourcePath)) {
        Write-Warning "  Master-Kopie nicht gefunden: $SourcePath"
        if (Test-Path $BuildOutput) {
            Write-Host "  Fallback: verwende Build-Output direkt aus $BuildOutput"
            Write-Host "  (Empfohlen: vorher '.\scripts\rocm-deploy.ps1 -Mode Snapshot' ausfuehren)"
            $SourcePath = $BuildOutput
        } else { throw "Weder Master-Kopie ($MasterCopy) noch Build-Output ($BuildOutput) vorhanden. Erst Self-Build durchfuehren oder ZIP-Archiv extrahieren." }
    }
    if (-not (Test-HasGfx1201Build $SourcePath)) { throw "Quelle '$SourcePath' enthaelt keine gfx1201-Tensile-Files - Abbruch." }

    if (-not (Test-Path $OllamaPath)) { throw "Ollama nicht gefunden in $OllamaPath. Erst Ollama installieren." }

    Write-Host "  Quelle: $SourcePath ($((Get-FolderSizeMB $SourcePath)) MB)"
    Write-Host "  Ziel:   $RocmDir"
    Write-Host "  HIP SDK fuer amdhip64_7.dll: $HipPath"

    # Idempotenz: wenn Deploy schon unser Build ist UND ggml-hip.dll Hashes matchen, abbrechen.
    if (Test-HasGfx1201Build $RocmDir) {
        $srcHash = (Get-FileHash (Join-Path $SourcePath 'ggml-hip.dll') -Algorithm SHA256).Hash
        $dstHash = (Get-FileHash (Join-Path $RocmDir   'ggml-hip.dll') -Algorithm SHA256).Hash
        if ($srcHash -eq $dstHash) {
            Write-Host "  Bestehender Deploy ist identisch (ggml-hip.dll SHA-256 match) - nichts zu tun." -ForegroundColor Green
            return
        }
        Write-Host "  Bestehender Deploy ist UNSER Build, aber andere Version - wird aktualisiert."
    } elseif (Test-Path $RocmDir) {
        Write-Host "  Bestehender Deploy ist nicht unser Build (vermutlich offizielle ROCm-6) - wird ersetzt."
    }

    Write-Header "Ollama-Service stoppen"
    if (-not $SkipServiceStop) { Stop-OllamaService } else { Write-Host "  uebersprungen (SkipServiceStop)" }

    Write-Header "Backup des bestehenden rocm-Ordners"
    if ((Test-Path $RocmDir) -and -not $NoBackup) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupDir = "$RocmDir.bak.$stamp"
        Move-Item -Path $RocmDir -Destination $backupDir -Force
        Write-Host "  Gesichert nach: $backupDir"
    } elseif ((Test-Path $RocmDir) -and $NoBackup) {
        Write-Host "  Loesche bestehenden rocm-Ordner ohne Backup (NoBackup)"
        Remove-Item $RocmDir -Recurse -Force
    } else { Write-Host "  Kein bestehender rocm-Ordner - kein Backup noetig" }

    Write-Header "Replace - MIT-Dateien aus Master-Kopie"
    New-Item -ItemType Directory -Force -Path $RocmDir | Out-Null
    Copy-Item -Path "$SourcePath\*" -Destination $RocmDir -Recurse -Force
    Write-Host "  Kopiert nach: $RocmDir"

    # Pruefen ob amdhip64_7.dll bereits aus der Quelle kam (Build-Output enthaelt sie, Master-Kopie nicht)
    $amdHipInTarget = Test-Path (Join-Path $RocmDir 'amdhip64_7.dll')
    if (-not $amdHipInTarget) {
        Write-Header "AMD-proprietaere Datei aus HIP SDK nachreichen"
        Copy-HipSdkFiles $RocmDir
    } else {
        Write-Host "`n  amdhip64_7.dll war schon in Quelle - kein HIP-SDK-Copy noetig (Build-Output-Source)"
    }

    Write-Header "Verifikation"
    if (-not (Test-HasGfx1201Build $RocmDir)) { throw "Deploy unvollstaendig: gfx1201-Tensile-Files fehlen im Ziel." }
    foreach ($f in $HipSdkOnlyFiles) {
        if (-not (Test-Path (Join-Path $RocmDir $f))) { throw "Deploy unvollstaendig: $f fehlt im Ziel." }
    }
    $gfx1201Count = (Get-ChildItem (Join-Path $RocmDir 'rocblas\library') -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'gfx1201' }).Count
    Write-Host "  ggml-hip.dll:                 vorhanden" -ForegroundColor Green
    Write-Host "  amdhip64_7.dll (vom HIP SDK): vorhanden" -ForegroundColor Green
    Write-Host "  rocblas/library/*gfx1201*:    $gfx1201Count Files"
    if ($gfx1201Count -lt 10) { Write-Warning "Weniger als 10 gfx1201-Files - kann zu reduzierter Performance fuehren." }

    if ($StartAfter) {
        Write-Header "Ollama serve starten (Hintergrund)"
        $exe = Join-Path $OllamaPath 'ollama.exe'
        $proc = Start-Process -FilePath $exe -ArgumentList 'serve' -WindowStyle Hidden -PassThru
        Write-Host "  PID $($proc.Id) - Logs in $env:LOCALAPPDATA\Ollama\server.log"
        Write-Host "  Tipp: nach 10s checken mit 'ollama ps'"
    } else {
        Write-Host ""
        Write-Host "Ollama via Tray-Icon starten oder 'ollama serve' im neuen Terminal."
    }
}

function Invoke-Verify {
    Write-Header "Verify - Status der deployten DLLs"

    if (-not (Test-Path $RocmDir)) { Write-Warning "Kein rocm-Ordner: $RocmDir"; exit 2 }
    Write-Host "  Pfad:    $RocmDir"
    Write-Host "  Groesse: $((Get-FolderSizeMB $RocmDir)) MB"

    $isOurs = Test-HasGfx1201Build $RocmDir
    if ($isOurs) { Write-Host "  Variante: UNSER Self-Build (ROCm 7, gfx1201)" -ForegroundColor Green }
    else { Write-Warning "  Variante: NICHT unser Build (gfx1201-Tensile-Files fehlen) - vermutlich nach Ollama-Update ueberschrieben. Deploy ausfuehren!"; exit 1 }

    # amdhip64_7.dll vorhanden?
    foreach ($f in $HipSdkOnlyFiles) {
        $p = Join-Path $RocmDir $f
        if (Test-Path $p) { Write-Host "  ${f}: vorhanden" -ForegroundColor Green }
        else { Write-Warning "  ${f}: FEHLT - GPU-Discovery wird hangen" }
    }

    # Hash-Match gegen Master-Kopie?
    if (Test-Path $MasterCopy) {
        $srcDll = Join-Path $MasterCopy 'ggml-hip.dll'
        $dstDll = Join-Path $RocmDir 'ggml-hip.dll'
        if ((Test-Path $srcDll) -and (Test-Path $dstDll)) {
            $srcHash = (Get-FileHash $srcDll -Algorithm SHA256).Hash
            $dstHash = (Get-FileHash $dstDll -Algorithm SHA256).Hash
            if ($srcHash -eq $dstHash) { Write-Host "  Master-Kopie match: ja (ggml-hip.dll SHA-256)" -ForegroundColor Green }
            else { Write-Warning "  Master-Kopie match: NEIN - Deploy und Master sind verschiedene Builds." }
        }
    } else { Write-Host "  Keine Master-Kopie unter $MasterCopy - kein Hash-Vergleich moeglich." }

    $gfx1201Count = (Get-ChildItem (Join-Path $RocmDir 'rocblas\library') -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'gfx1201' }).Count
    Write-Host "  rocblas/library/*gfx1201*: $gfx1201Count Files"
}

# --- Entry Point -------------------------------------------------------------
switch ($Mode) {
    'Snapshot' { Invoke-Snapshot }
    'Deploy'   { Invoke-Deploy }
    'Verify'   { Invoke-Verify }
}
