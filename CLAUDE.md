# CLAUDE.md — `ollama-rocm`

Diese Datei wird von Claude Code automatisch geladen. Sie ist der Einstieg; Details liegen in den verlinkten Quellen.

## Was das ist

Community-Rezept, um **Ollama mit ROCm-GPU-Beschleunigung auf AMD RDNA 4** (`gfx1201` — RX 9070 / 9070 XT / 9060 XT) unter Windows 11 zum Laufen zu bringen.

**Problem:** Ollamas offizielles Windows-Release linkt `ggml-hip.dll` gegen ROCm 6.4.2. Auf RDNA 4 hängt die GPU-Discovery dann 30 s und fällt auf CPU zurück. **Lösung:** `ggml-hip.dll` (+ Begleit-Libs) selbst gegen **HIP SDK 7.1.1** für `gfx1201` bauen und in die Ollama-Installation swappen.

**Typ:** C++/CMake-Build-Projekt. Output sind DLLs (v. a. `ggml-hip.dll`), kein Web-Stack. Verifiziert mit Ollama 0.16.1 und 0.24.0 — Discovery in ~1.3 s, `ollama ps` zeigt `100% GPU`.

**Sprache:** Maintainer-Kommunikation Deutsch. Code, Scripts, README englisch.

## Zuerst lesen

| Quelle | Inhalt |
|---|---|
| [.claude/instructions.md](.claude/instructions.md) | Vollständige Projekt-Instruktionen, Graphiti-Routing, Konventionen |
| [MAINTAINING.md](MAINTAINING.md) | Build- + Release-Playbook (wann Release, Pipeline, Smoke-Test, `gh release`) |
| [README.md](README.md) | Endnutzer-Doku — beide Install-Pfade (ZIP / Self-Build) |
| Graphiti `group_id: ollama-rocm` | Build-Erkenntnisse, Fallstricke, Versionen, Test-Ergebnisse |

**Graphiti zuerst:** Bei jeder neuen Frage erst `search_nodes` / `search_memory_facts` / `get_episodes` mit `group_id=ollama-rocm`, dann Code. Nach signifikanten Schritten `add_memory` ohne Rückfrage (Routing-Tabelle in instructions.md).

## Scripts (alles, was man braucht — keine Befehle von Hand)

| Script | Zweck |
|---|---|
| [scripts/build-rocm.ps1](scripts/build-rocm.ps1) | Build-Pipeline. Modi: `Check` / `Configure` / `Build` / `All` / `Clean` |
| [scripts/rocm-deploy.ps1](scripts/rocm-deploy.ps1) | Repo-internes `Deploy` / `Snapshot` / `Verify` |
| [scripts/deploy-from-zip.ps1](scripts/deploy-from-zip.ps1) | Standalone-Deploy, wird als `deploy.ps1` ins Release-ZIP gepackt |

Typischer Ablauf: `.\scripts\build-rocm.ps1 -Mode Check` → `-Mode All` (Build + Snapshot + ZIP) → `.\scripts\rocm-deploy.ps1` (Deploy ins Ollama-Verzeichnis).

**Verified-Defaults:** HIP SDK 7.1 (`C:\Program Files\AMD\ROCm\7.1`) · `gfx1201` · Preset `ROCm 7` · `--parallel 4` · Ollama-Tag `v0.24.0`.

## Kritische Fallstricke (aus Graphiti — nicht erneut reinlaufen)

- **`--parallel >= 8`** crasht den Compiler in `topk-moe.cu` (Race, keine klare Fehlermeldung). Bei 4 bleiben.
- **VS Build Tools 18** (VS-2025-Gen, MSVC 14.51) produziert inkompatible cmath-Header → Build bricht. **VS 2022 BuildTools (MSVC 14.44)** nutzen.
- **`-DCMAKE_HIP_COMPILER` muss explizit** gesetzt werden, sonst `check_language(HIP)` = NOTFOUND und ggml-hip wird übersprungen.
- Compiler ist der **ROCm-interne clang** (`...\ROCm\7.1\bin\clang++.exe`), nicht das standalone LLVM.
- **`amdhip64_7.dll`** (AMD-proprietär) wird **nie** ins Release-ZIP gepackt — Deploy-Scripts holen sie aus dem lokalen HIP SDK. Keine Privatdaten (Windows-User `mail`) in getrackte Dateien.
- Library-Swaps allein lösen das Timeout **nicht** — nur ein Self-Build gegen ROCm 7.x.

## Erfolgs-Indikatoren (zum schnellen Gegenprüfen)

- **Configure ok:** `-- HIP and hipBLAS found` im CMake-Output.
- **Build-Output plausibel:** `ggml-hip.dll` ist ~57 MB (nur gfx1201). Deutlich >250 MB → `AMDGPU_TARGETS`-Beschränkung hat nicht gegriffen.
- **Deploy ok / GPU läuft:** `server.log` (`%LOCALAPPDATA%\Ollama\server.log`) zeigt
  `inference compute ... library=ROCm compute=gfx1201 ... description="AMD Radeon RX 9070 XT"`,
  Discovery in ~1.3 s (statt 30 s Timeout), und `ollama ps` meldet `100% GPU`.

## Konventionen

- Code-Edits direkt, Antworten knapp, Deutsch, kein Filler.
- Lange Builds mit `run_in_background`.
- Commits: Author/Committer `xnyzer` + GitHub-Noreply-Email (`12890660+xnyzer@users.noreply.github.com`), **nie** echte Adresse. Jeder Commit braucht `Co-Authored-By: Claude <noreply@anthropic.com>`.
