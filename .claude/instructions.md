# Claude Code Instructions — `ollama-rocm`

## Projekt

Ollama mit ROCm-GPU-Beschleunigung auf AMD RDNA 4 GPUs (`gfx1201` — RX 9070, RX 9070 XT, RX 9060 XT) unter Windows 11.

Funktioniert mit Ollama 0.16.1 und 0.24.0 (Stand 2026-05-18). Discovery in ~1.3 s, `ollama ps` zeigt `100% GPU`.

**Typ:** C++/CMake-Build-Projekt — Output sind DLLs (vor allem `ggml-hip.dll`), die Ollamas mitgelieferte ROCm-6-Libs ersetzen.

**Endnutzer-Doku:** [README.md](../README.md) — beschreibt beide Install-Pfade (ZIP oder Self-Build).

**Sprache:** Kommunikation mit dem Maintainer auf Deutsch. Code, Scripts, README auf Englisch.

---

## Scripts

| Script | Zweck |
|---|---|
| [scripts/build-rocm.ps1](../scripts/build-rocm.ps1) | Vollständige Build-Pipeline (Check / Configure / Build / All / Clean) |
| [scripts/rocm-deploy.ps1](../scripts/rocm-deploy.ps1) | Repo-internes Deploy / Snapshot / Verify |
| [scripts/deploy-from-zip.ps1](../scripts/deploy-from-zip.ps1) | Standalone-Deploy, wird beim Snapshot als `deploy.ps1` ins Release-ZIP gepackt |

Verified-Defaults: HIP SDK 7.1 + `gfx1201` + `--parallel 4` + Preset `ROCm 7`. Parameter siehe Script-Header.

---

## Graphiti Knowledge Graph

**`group_id` für dieses Projekt: `ollama-rocm`**

### Lesen — bei jeder neuen Frage zuerst Graphiti

1. `mcp__graphiti-memory__search_nodes` — Entitäten
2. `mcp__graphiti-memory__search_memory_facts` — Beziehungen
3. `mcp__graphiti-memory__get_episodes` — Roh-Kontext

Erst danach Code/Dateien durchsuchen, falls Graphiti die Frage nicht beantwortet.

### Schreiben — automatisch nach jedem signifikanten Schritt

`mcp__graphiti-memory__add_memory` ohne Rückfrage. Routing:

| Inhalt | `group_id` |
|---|---|
| Projektspezifisch (Build-Befehle, Versionen, Pfade, Test-Ergebnisse, Konfig-Edits) | `ollama-rocm` |
| Allgemein über Maintainer (Präferenzen, Stil, andere Projekte) | `main` |

### Umgang mit überholten Fakten

1. Neue Episode schreiben — im Body benennen, was sie ersetzt: *"Ersetzt vorherige Episode XYZ vom TT.MM.JJJJ — Grund: ..."*
2. Bei kompletter Falsch-Information: Korrektur-Episode mit Namens-Präfix `[VERALTET]`.
3. `delete_episode` nur, wenn die Info nie hätte gespeichert werden dürfen.

---

## Konventionen

- Code-Edits direkt machen, keine langen Vorab-Erklärungen.
- Antworten knapp halten, Deutsch, kein Filler.
- Bei langen Builds `run_in_background`.
- Nach signifikanten Schritten: Episode in Graphiti.
- Commits: `xnyzer` + GitHub-Noreply-Email (siehe `git config`), jeder Commit braucht `Co-Authored-By: Claude <noreply@anthropic.com>`.
