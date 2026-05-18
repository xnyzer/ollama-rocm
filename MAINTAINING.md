# Maintaining `ollama-rocm`

How to build a new ROCm 7 binary for Ollama, publish a release, and keep
the README in sync. For end-user instructions see [README.md](README.md).

---

## When to release a new build

You need a new release whenever any of these changes meaningfully:

| Component | New release recommended when |
|---|---|
| **Ollama source** | New stable Ollama release (e.g. `v0.25.0` ships and you want users on it) |
| **HIP SDK** | A new HIP SDK version is out and you want to test/ship against it |
| **GPU targets** | You want to add another `gfx*` (e.g. someone reports `gfx1200` needs its own kernels) |
| **Bugfix in scripts** | A user reports the deploy script breaks on their box and you patch it |

Don't release just because you can — a stale release that still works is
preferable to release churn.

---

## Build pipeline (one terminal session, ~30 min)

### 1. Pull / update the Ollama source

```powershell
cd ollama
git fetch --tags
git checkout v0.25.0       # or whichever tag you target
cd ..
```

### 2. Pre-flight

```powershell
.\scripts\build-rocm.ps1 -Mode Check
```

Fix anything that comes back `[FAIL]`. Most common cause when ROCm/MSVC
get newer: `MSVC 14.5x detected — possible cmath/__clang_hip header
conflict`. If that warning appears, either install an older VS 2022
toolset side-by-side or expect build failures.

### 3. Build + snapshot in one shot

```powershell
.\scripts\build-rocm.ps1 -Mode All
```

What this does:
- `cmake configure` against the ROCm 7 preset
- `cmake --build` for `ggml-hip` target with `--parallel 4`
- `cmake --install --component HIP`
- runs `rocm-deploy.ps1 -Mode Snapshot` which:
  - copies the build output to `dist\rocm-gfx1201\`
  - **strips `amdhip64_7.dll` out** (proprietary, not redistributed)
  - creates `dist\ollama-rocm-gfx1201.zip` with:
    - `rocm\*` (MIT binaries only)
    - `deploy.ps1` (standalone install script for end users)
    - `LICENSE`, `THIRD_PARTY_LICENSES.md`, `README.txt`

Build time depends on the CPU. ~25 minutes on a 20-core box. Watch for
the verified-good build pattern: 123 compile units, exit 0,
`ggml-hip.dll` lands around 57 MB for gfx1201-only.

If the build crashes on `topk-moe.cu` with no clear error message, you
hit the parallel-jobs race condition — re-run with
`-ParallelJobs 2`.

### 4. Deploy locally and smoke-test

```powershell
.\scripts\rocm-deploy.ps1
```

This is idempotent — if a SHA-256 match with the master copy is found,
it does nothing. Otherwise it stops Ollama, backs up `rocm` to
`rocm.bak.<timestamp>`, copies the master + `amdhip64_7.dll` into
place, and verifies.

Start Ollama (Start Menu / tray), then in a terminal:

```powershell
ollama run deepseek-r1:14b "Antworte mit einem Satz: 2 + 2 = ?"
# In another terminal:
ollama ps
```

The `PROCESSOR` column **must** show `100% GPU`. If it doesn't, do not
publish the release — debug first. The server log at
`%LOCALAPPDATA%\Ollama\server.log` should show
`library=ROCm compute=gfx1201` and discover the GPU in ~1 second.

---

## Release pipeline

### Tag schema

```
v<ollama-version>-<gpu-target>-<iteration>
```

Examples:
- `v0.24.0-gfx1201-1` — first build against Ollama 0.24.0 for gfx1201
- `v0.24.0-gfx1201-2` — rebuild of same Ollama version (e.g. script bugfix)
- `v0.25.0-gfx1201-1` — first build for the next Ollama
- `v0.24.0-gfx1200-gfx1201-1` — combined build for both GPUs (the script
  takes `-AmdGpuTargets "gfx1200;gfx1201"`)

### Publishing

```powershell
gh release create "v0.25.0-gfx1201-1" `
    "dist\ollama-rocm-gfx1201.zip" `
    --title "Ollama 0.25 + ROCm 7 for gfx1201 (build 1)" `
    --notes-file release-notes.md `
    --latest
```

Notes template:

```markdown
Pre-built ROCm 7 binaries for **Ollama on AMD RX 9070 / RX 9070 XT / RX 9060 XT** (gfx1201) under Windows 11.

## What's inside

(copy from previous release, adjust Ollama version)

## Prerequisites

- AMD HIP SDK 7.1
- Ollama 0.25 or newer
- AMD Adrenalin 26.x or newer

## Install

(copy from previous release)

## Built from / verified against

| | |
|---|---|
| Ollama source | v0.25.0 (commit <short-hash>) |
| HIP SDK | 7.1.1 |
| MSVC | (output of `Check` mode) |
| Tested with | <list models you actually ran> |
```

You can crib the previous release notes via:
```powershell
gh release view v0.24.0-gfx1201-1 --json body --jq .body > release-notes.md
```
…then edit the version numbers and ship.

### After publishing

1. **Check the asset URL** is reachable (open the release page).
2. **Update the README** if the Ollama version table needs a new row:
   ```powershell
   # Edit README.md section "Tested Ollama versions"
   git add README.md
   git commit -m "docs: verify Ollama 0.25 against build 1"
   git push
   ```
3. **Add a Graphiti episode** documenting which combinations were verified.

---

## Updating the README's tested-versions table

The table under `## After it works → Tested Ollama versions` should list
every Ollama version you've actually run with this build. Add a row,
keep older rows so users know the build also works with older Ollama.
Drop a row only when an Ollama version is truly broken and you want to
warn people off.

---

## Rolling back a release

Don't delete tags or releases that other users may already have
downloaded — keep them and just mark new ones as `--latest`. If a
release is genuinely broken (e.g. you accidentally shipped the wrong
ZIP), edit it:

```powershell
gh release edit v0.24.0-gfx1201-1 --prerelease
# attach a note explaining what's wrong
gh release upload v0.24.0-gfx1201-1 ollama-rocm-gfx1201.zip --clobber
```

If a release was made for the wrong Ollama version, leave it and ship
the right one with a new tag. Don't force-overwrite a tag — anyone who
downloaded the ZIP gets confused.

---

## Local dev hygiene

- Never push `dist/` or `ollama/` — both are `.gitignored`. If you ever
  see them in `git status`, check your `.gitignore`.
- Never commit `.claude/settings.local.json` — also gitignored. Other
  files in `.claude/` are tracked (project setup).
- Never let `mail` (the local Windows username) leak into a tracked
  file. Use `%LOCALAPPDATA%`, `$HOME`, `~`, etc.
- Verify before pushing personal data could leak:
  ```powershell
  git grep -i "sascha\|dahms\|Users.\\\\mail" -- ':!ollama/**'
  # Empty output = clean.
  ```

---

## Updating the build for a newer ROCm / HIP SDK

When AMD ships a HIP SDK 7.2 or 8.0:

1. Install the new SDK alongside the old one (different install path).
2. Build with `-HipPath "C:\Program Files\AMD\ROCm\7.2"`.
3. The `ROCm 7` preset name in Ollama's `CMakePresets.json` should
   continue to work for any 7.x. For ROCm 8 you might need a new preset
   or a flag tweak — check Ollama's release notes when they ship 8.x
   support.
4. The deploy script's `amdhip64_7.dll` reference still works as long
   as the SDK ships that filename. If they bump to `amdhip64_8.dll`,
   patch `$HipSdkOnlyFiles` in `rocm-deploy.ps1`.

---

## Sanity-check the published release

Two minutes of validation after every push:

```powershell
# Fresh download (don't trust the local file we just uploaded):
$tmp = "$env:TEMP\ollama-rocm-verify"
mkdir $tmp -Force | Out-Null
gh release download v0.25.0-gfx1201-1 -p "ollama-rocm-gfx1201.zip" -D $tmp
Expand-Archive -Path "$tmp\ollama-rocm-gfx1201.zip" -DestinationPath "$tmp\extracted"

# Confirm structure:
Get-ChildItem $tmp\extracted
# Should list: rocm\, deploy.ps1, LICENSE, README.txt, THIRD_PARTY_LICENSES.md

# Confirm no amdhip64_7.dll inside:
if (Test-Path "$tmp\extracted\rocm\amdhip64_7.dll") {
    Write-Warning "LEAK: amdhip64_7.dll is in the ZIP - investigate"
} else {
    Write-Host "OK: amdhip64_7.dll correctly excluded"
}
Remove-Item $tmp -Recurse -Force
```
