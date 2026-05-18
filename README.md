# Ollama with ROCm for AMD RDNA 4 (RX 9070 / 9070 XT / 9060 XT)

Run [Ollama](https://ollama.com) with full **GPU acceleration** on AMD's newest
consumer GPUs (Radeon RX 9070, RX 9070 XT, RX 9060 XT — internally `gfx1201`)
under Windows 11.

This repository contains the recipe — and either a pre-built binary or a
push-button self-build script — to get local LLMs running on your GPU instead
of falling back to CPU.

> **Status (May 2026):** Verified working with **Ollama 0.16.1 and Ollama
> 0.24.0**. Discovery in ~1.3 s (vs. 30 s timeout on stock Ollama),
> `ollama ps` reports `100% GPU` for 14B-class models on the 16 GB RX 9070 XT.

---

## Table of contents

- [Why this exists](#why-this-exists)
- [Which path is for you?](#which-path-is-for-you)
- [Hardware requirements](#hardware-requirements)
- [Path A — Use the pre-built ZIP (≈ 10 min)](#path-a--use-the-pre-built-zip--10-min)
- [Path B — Build it yourself (≈ 60 min)](#path-b--build-it-yourself--60-min)
- [After it works](#after-it-works)
- [Maintenance: Ollama updates](#maintenance-ollama-updates)
- [Troubleshooting](#troubleshooting)
- [How this actually works](#how-this-actually-works)
- [Disclaimer & credits](#disclaimer--credits)

---

## Why this exists

The official Ollama Windows installer ships acceleration libraries compiled
against **ROCm 6.4.2**. The Radeon RX 9000 series (RDNA 4) is too new for that
ROCm version — its compute architecture (`gfx1201`) is only supported by
**ROCm 7.x**.

The result on a stock install: Ollama discovers your GPU correctly, then hangs
for 30 seconds trying to initialise it, gives up, and falls back to CPU. You
end up running 9B+ models on your CPU at single-digit tokens per second when
your GPU could do an order of magnitude better.

This repository ships the missing piece: an `ml/backend/ggml/ggml/src/ggml-hip`
build linked against **ROCm 7.1.1**, with `amdhip64_7.dll` and 56 Tensile
kernel files specifically for `gfx1201`. Drop it on top of a normal Ollama
install and the GPU works.

**No patches to Ollama are required** — the mainline source already supports
`gfx1201`. The trick is simply building it against ROCm 7 instead of ROCm 6.

---

## Which path is for you?

| Question | Path A (Pre-built) | Path B (Self-build) |
|---|---|---|
| Time | ≈ 10 min | ≈ 60 min |
| Disk space | ≈ 2.5 GB | ≈ 15 GB |
| Tools required | HIP SDK + Ollama only | + VS 2022, CMake, Ninja, Git |
| Customisation possible | No | Yes — different GPU, newer Ollama, etc. |
| You trust someone else's compile | Yes | No |

If you just want it to work and you have an RX 9070 XT (or any other `gfx1201`
GPU) on Windows 11, **Path A is the right choice.** If you want full control,
need a different GPU target, or just don't run other people's binaries, do
Path B.

---

## Hardware requirements

Both paths need the same hardware:

| Component | Requirement |
|---|---|
| GPU | AMD Radeon RX 9070, RX 9070 XT, or RX 9060 XT (compute capability `gfx1201`) |
| OS  | Windows 11 (Windows 10 may work but is untested) |
| RAM | 16 GB minimum, 32 GB recommended for the 32B-class models |
| Disk | 5 GB free for HIP SDK + Ollama; +15 GB if you build yourself |

> **How do I check my GPU's compute architecture?** After installing the HIP
> SDK (next section), run `"C:\Program Files\AMD\ROCm\7.1\bin\hipinfo.exe"` —
> look for the `gcnArchName` line. It should read `gfx1201`. If it doesn't,
> this repo won't help you (but you might be in luck with a different ROCm
> support repo — search for your `gcnArch` on GitHub).

---

## Path A — Use the pre-built ZIP (≈ 10 min)

### Step 1 — Update your AMD driver

You need a reasonably modern AMD Adrenalin driver. **26.5.1 or newer** is
verified; anything from early 2026 onwards should work.

1. Download from <https://www.amd.com/en/support>
2. Run the installer, choose **Full Install**, reboot when prompted.
3. Verify in *Device Manager → Display adapters* that your GPU is listed
   without a warning triangle.

### Step 2 — Install AMD HIP SDK 7.1.1

This provides the GPU runtime libraries that Ollama needs. **Without this,
Ollama will not see your GPU**, no matter what else you do.

1. Go to <https://www.amd.com/en/developer/resources/rocm-hub/hip-sdk.html>
2. Download **HIP SDK for Windows, version 7.1** (≈ 2 GB).
3. Run the installer. Accept all defaults. Default install path is
   `C:\Program Files\AMD\ROCm\7.1\` — keep that.
4. **Reboot.** The installer sets `HIP_PATH` and adds entries to your `PATH`
   that only get picked up after a restart.
5. After reboot, verify by opening PowerShell and running:
   ```powershell
   & "C:\Program Files\AMD\ROCm\7.1\bin\hipinfo.exe"
   ```
   You should see a wall of text starting with `Name: AMD Radeon RX 9070 XT`
   (or whatever your card is) and `gcnArchName: gfx1201`. If `hipinfo` hangs
   or errors out, the SDK isn't installed correctly — fix that before
   continuing.

### Step 3 — Install Ollama

1. Download the official Windows installer from <https://ollama.com/download>
   (`OllamaSetup.exe`).
2. Run it. Default install path is
   `C:\Users\<YOU>\AppData\Local\Programs\Ollama\` — keep that.
3. Let it start once. The tray icon will appear. **You will see CPU-only
   inference at this point** — that's expected, we fix it next.
4. **Quit Ollama** before continuing: right-click the tray icon → *Quit
   Ollama*. Also stop any background `ollama.exe` processes (open Task
   Manager if unsure). The ROCm files are locked while Ollama runs and you
   can't replace them.

### Step 4 — Drop in the ROCm-7 build

The pre-built ZIP **deliberately does not contain `amdhip64_7.dll`** — that
file is part of AMD's proprietary HIP runtime. You already have it on disk
from Step 2 (inside `C:\Program Files\AMD\ROCm\7.1\bin\`); the bundled
deploy script just copies it from there. This keeps the redistributed
archive limited to MIT-licensed files only.

1. Download `ollama-rocm-gfx1201.zip` (≈ 85 MB) from the **Releases** page
   of this repository.
2. Extract it anywhere (Desktop, Downloads — doesn't matter). You'll get a
   folder containing:
   ```
   ollama-rocm-gfx1201\
   ├─ rocm\
   │  ├─ ggml-hip.dll          (57 MB)
   │  ├─ rocblas.dll           (39 MB)
   │  ├─ libhipblas.dll
   │  ├─ libhipblaslt.dll
   │  └─ rocblas\library\…     (~890 Tensile files)
   ├─ deploy.ps1               ← run this
   ├─ README.txt
   ├─ LICENSE
   └─ THIRD_PARTY_LICENSES.md
   ```
3. Open the extracted folder. **Right-click `deploy.ps1` → Run with
   PowerShell.** (Alternative: open a PowerShell window inside that folder
   and run `.\deploy.ps1`.)
4. The script will:
   - Stop any running Ollama processes
   - Back up the existing `rocm` folder to `rocm.bak.<timestamp>`
   - Copy the MIT-licensed files from the ZIP
   - Copy `amdhip64_7.dll` from your local HIP SDK install
   - Verify the result and tell you it's done

If the script can't find Ollama or the HIP SDK in their default locations,
it will say so with a clear error. You can override the defaults:
```powershell
.\deploy.ps1 -OllamaPath "D:\Ollama" -HipPath "C:\Program Files\AMD\ROCm\7.1"
```

### Step 5 — Start Ollama and verify

1. Start Ollama from the Start Menu (or run `ollama serve` in a terminal).
2. Open a new PowerShell or Command Prompt and run:
   ```powershell
   ollama ps
   ```
   Initially you'll see no models loaded. That's fine.
3. Pull a small model to test (this downloads ≈ 9 GB):
   ```powershell
   ollama pull deepseek-r1:14b
   ```
4. Run it with any prompt:
   ```powershell
   ollama run deepseek-r1:14b "Say hello in one sentence."
   ```
5. **While it's responding**, open another terminal and run `ollama ps`:
   ```
   NAME               PROCESSOR    CONTEXT    UNTIL
   deepseek-r1:14b    100% GPU     4096       4 minutes from now
   ```

   If you see **`100% GPU`** in the PROCESSOR column — congratulations, it
   worked. If you see `100% CPU` or `X%/Y% CPU/GPU`, something went wrong;
   jump to [Troubleshooting](#troubleshooting).

### Optional: also check the server log

For deeper verification, the server log shows GPU discovery details:

```powershell
Get-Content "$env:LOCALAPPDATA\Ollama\server.log" -Tail 30
```

The magic line to look for:

```
inference compute id=0 library=ROCm compute=gfx1201 name=ROCm0
  description="AMD Radeon RX 9070 XT" total="15.9 GiB" available="14.5 GiB"
```

---

## Path B — Build it yourself (≈ 60 min)

This path produces the same files as the ZIP in Path A, but you control the
build. Useful if:

- You have a non-RX-9070-XT `gfx1201` device (e.g. RX 9060 XT)
- You want to target multiple GPUs (e.g. `gfx1200;gfx1201`)
- A newer Ollama or HIP SDK version comes out and you don't want to wait for
  a pre-built release
- You don't run other people's binaries on principle

### Step 1 — Path A's steps 1, 2, 3

You still need the driver (Step 1), HIP SDK (Step 2), and Ollama (Step 3) from
Path A above. Do those first. Don't bother with Step 4 (the ZIP) — you'll
produce its contents yourself.

> If you've already done Path A and now want to switch to a custom build,
> that's fine. Path B's deploy script handles backups properly and won't lose
> your existing setup.

### Step 2 — Install build tools

Open an **administrator PowerShell** (Windows key, type "powershell",
right-click → "Run as administrator") and run these one at a time:

```powershell
winget install Git.Git -e
winget install Kitware.CMake -e
winget install Ninja-build.Ninja -e
winget install Microsoft.VisualStudio.2022.BuildTools -e --override "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
```

The last one is the big one (≈ 3 GB download, the VS 2022 C++ build tools).
This will run for several minutes silently before returning.

> **Important — do NOT install the newer VS Build Tools 18 / "VS 2025"
> generation as your only MSVC.** Its `cmath` headers (MSVC 14.51) conflict
> with HIP 7.1's `__clang_hip_cmath.h` and the build will fail with cryptic
> "cannot overload `__host__ __device__ function`" errors. The script
> deliberately targets MSVC 14.4x from VS 2022 BuildTools.

After all four succeed, close and reopen your PowerShell so new tools land in
`PATH`.

### Step 3 — Clone this repo

```powershell
cd $HOME\Documents       # or wherever you keep code
git clone https://github.com/xnyzer/ollama-rocm.git
cd ollama-rocm
```

### Step 4 — Run the pre-flight check

```powershell
.\scripts\build-rocm.ps1 -Mode Check
```

This inspects every tool and prints what's missing. Each missing item comes
with the exact `winget install …` command to fix it. Re-run until all lines
say `[OK]`.

Typical successful output:

```
=== Pre-flight Check ===
  [OK]   git 2.54.0.windows.1
  [OK]   cmake version 4.3.2
  [OK]   ninja 1.13.2
  [OK]   VS 2022 BuildTools  (C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools)
  [OK]   MSVC 14.44.35207
  [OK]   HIP SDK 7.1.51803
  [OK]   GPU: AMD Radeon RX 9070 XT  (gcnArchName: gfx1201)
  [OK]   Ollama-Source: ...\ollama-rocm\ollama   ← FAIL here, expected at first run

Voraussetzungen unvollstaendig - siehe [FAIL]-Eintraege oben.
```

The Ollama-Source `[FAIL]` is expected at this point — we clone it next.

### Step 5 — Clone the Ollama source

Inside the `ollama-rocm` directory:

```powershell
git clone https://github.com/ollama/ollama.git ollama
git -C ollama checkout v0.24.0
```

This pulls the official Ollama mainline source (≈ 800 MB with history) and
switches to the verified stable tag.

> **Why v0.24.0?** It's the last stable release with `gfx1201` support in
> `CMakePresets.json` and a clean `gfx(120[01])` regex filter in
> `CMakeLists.txt`. Newer release candidates (v0.25.0-rc0, v0.30.0-rcN) work
> too but are less battle-tested. Use `-ExpectedTag` to change the warning
> threshold.

Re-run the check to confirm it's happy:

```powershell
.\scripts\build-rocm.ps1 -Mode Check
```

Every line should now say `[OK]`.

### Step 6 — Build

```powershell
.\scripts\build-rocm.ps1 -Mode All
```

What this does:
1. Loads `vcvars64.bat` from VS 2022 BuildTools (needed for the Windows SDK
   and linker).
2. Sets the ROCm environment variables (`HIPCXX`, `CC`, `CXX`,
   `CMAKE_PREFIX_PATH`, `HIP_PLATFORM`) per Ollama's CI pattern.
3. Runs `cmake --preset "ROCm 7" -G Ninja` with the correct `CMAKE_HIP_COMPILER`
   override.
4. Builds the `ggml-hip` target with `--parallel 4` (deliberately not higher —
   the `topk-moe.cu` translation unit hits a race condition with 8+ parallel
   compile jobs).
5. Runs `cmake --install` to assemble `ggml-hip.dll` plus the ROCm runtime
   DLLs and Tensile kernels into `ollama/dist/lib/ollama/rocm/`.
6. Copies that to `dist/rocm-gfx1201/` and zips it.

Total time: ≈ 25 min on a modern CPU for the first build, < 5 min for
subsequent rebuilds (Ninja is incremental).

> If the build fails with `topk-moe.cu` and no clear error message, you hit
> the race condition. Run again with `-ParallelJobs 2`.

### Step 7 — Deploy

```powershell
.\scripts\rocm-deploy.ps1
```

This stops Ollama, backs up its current `rocm` folder as
`rocm.bak.<timestamp>`, copies your fresh build into place, and verifies the
result. Start Ollama again from the tray icon and verify per [Path A
Step 5](#step-5--start-ollama-and-verify).

### Script reference (Path B)

There are exactly two scripts in `scripts/`:

#### `build-rocm.ps1`

| `-Mode` | What it does |
|---|---|
| `Check` (default) | Inspect tools, GPU, source; report what's missing. **Never modifies anything.** |
| `Configure` | Just run `cmake configure` — useful when tweaking flags. |
| `Build` | Configure + build + install. |
| `All` | Build + snapshot (master copy + ZIP, ready for deploy). |
| `Clean` | Delete `ollama/build/rocm/` and `ollama/dist/`. |

Useful parameters:

- `-AmdGpuTargets "gfx1200;gfx1201"` — build for multiple GPUs.
- `-HipPath "C:\Program Files\AMD\ROCm\8.0"` — when ROCm 8 ships.
- `-ParallelJobs 2` — if your CPU is overloaded or you hit race conditions.
- `-ExpectedTag "v0.25.0"` — silence the version-mismatch warning if you
  intentionally use a different Ollama tag.

#### `rocm-deploy.ps1`

| `-Mode` | What it does |
|---|---|
| `Deploy` (default) | Copy `dist/rocm-gfx1201/` → Ollama's `lib\ollama\rocm\`. Stops Ollama, backs up the old folder, replaces it. **Idempotent** — does nothing if the target already matches the source (SHA-256 check on `ggml-hip.dll`). |
| `Snapshot` | Take the current build output and update `dist/rocm-gfx1201/` + the ZIP. Run this after a successful build before deploying. |
| `Verify` | Read-only sanity check — is the deployed `rocm` folder really our ROCm-7 build? Useful after Ollama updates. |

Useful parameters:

- `-StartAfter` — start `ollama serve` automatically in the background after
  deploy.
- `-NoBackup` — skip the `rocm.bak.<timestamp>` (saves 300 MB per deploy if
  you iterate a lot).

---

## After it works

### Tested Ollama versions

| Ollama | Verified | Notes |
|---|---|---|
| **0.24.0** | ✅ Full GPU | Recommended. All current model formats load (including Gemma 4). |
| **0.16.1** | ✅ Full GPU | Works, but cannot load newer model architectures (e.g. `gemma4`). |

In theory any Ollama version that includes a `"ROCm 7"` preset in its
`CMakePresets.json` and `gfx1201` in the `AMDGPU_TARGETS` regex of its
`CMakeLists.txt` should work with this ROCm-7 build — those landed in
mainline before v0.24.0. If a newer Ollama release ships, install it, then
re-run `.\scripts\rocm-deploy.ps1` to put our ROCm-7 build back over the
official ROCm-6 files.

### Tested models

Verified on Ollama 0.24.0 + our ROCm-7 build on a 16 GB RX 9070 XT:

| Model | Size | PROCESSOR | Notes |
|---|---|---|---|
| `gemma4:e4b` | 9.6 GB | 100 % GPU | Loads on 0.24.0; fails on 0.16.1 (architecture too new) |
| `deepseek-r1:14b` | 9.0 GB | 100 % GPU | Fast reasoning model |
| `deepseek-r1:32b` | 19 GB | Split CPU/GPU | Too large for 16 GB VRAM — partial GPU |
| `qwen2.5-coder:32b` | 19 GB | Split CPU/GPU | Same |

Anything ≤ 14 GB (after Q4 quantisation) fits in 16 GB VRAM and runs
GPU-only. Bigger models work but partly on CPU.

---

## Maintenance: Ollama updates

The Ollama installer (whether via auto-update or manual `OllamaSetup.exe`)
**overwrites** `lib\ollama\rocm\` with the official ROCm-6 files. Every time
Ollama updates, you need one command to put our ROCm-7 build back.

**If you used Path A (the ZIP):** open the extracted folder again and
re-run the bundled script.
```powershell
.\deploy.ps1
```

**If you used Path B (self-build):** run the repo's deploy script.
```powershell
.\scripts\rocm-deploy.ps1
```

Either way, the script auto-stops Ollama, backs up the freshly-installed
ROCm-6 folder, drops your build back in, and you're ready to go.

Status check without changing anything (Path B only — has a verify mode):
```powershell
.\scripts\rocm-deploy.ps1 -Mode Verify
```

---

## Troubleshooting

### `ollama ps` shows `100% CPU`

Most likely the ROCm files aren't where Ollama expects (often after an
Ollama auto-update). Re-run the deploy script you used to install:

- **Path A:** `.\deploy.ps1` from the extracted ZIP folder
- **Path B:** `.\scripts\rocm-deploy.ps1` (or `… -Mode Verify` first to confirm)

If it says `UNSER Self-Build` but you still see `100% CPU`, check the server
log:

```powershell
Get-Content "$env:LOCALAPPDATA\Ollama\server.log" -Tail 80 |
  Select-String -Pattern "ROCm|gfx|library=|inference compute"
```

Look for `library=ROCm compute=gfx1201`. If absent, see next item.

### Server log shows no ROCm line at all, just `library=cpu`

The discovery silently failed. Often a transient issue right after install —
restart Ollama from the tray icon (right-click → *Quit*, then re-launch from
Start Menu). If that doesn't help, run with debug logging:

```powershell
$env:OLLAMA_DEBUG="DEBUG"
Stop-Process -Name "ollama*" -Force
& "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe" serve
```

Then look at `server.log` for `discover` / `runner` / `gfx` lines. The most
common reasons:

- HIP SDK 7.1 missing or not on PATH → fix by re-installing HIP SDK and
  rebooting.
- Driver too old → update to AMD Adrenalin 26.x.
- `amdhip64_7.dll` is missing from `lib\ollama\rocm\` → run the deploy
  script.

### Build fails with `error: __device__ function 'isgreater' cannot overload`

You're using the wrong MSVC version. This is the cmath-conflict mentioned in
Step 2 of Path B. Install **VS 2022** BuildTools (not VS 2025). If both are
installed, `vswhere` should still find VS 2022 — verify by running
`-Mode Check` and reading the `MSVC` line.

### Build fails on `topk-moe.cu` with no clear error

You hit the race condition with high `--parallel` values. Re-run:

```powershell
.\scripts\build-rocm.ps1 -Mode All -ParallelJobs 2
```

### Model fails to load: `unknown model architecture: 'gemma4'`

Your Ollama version is too old for that model format. Run the latest
`OllamaSetup.exe`, then re-run your deploy script (see [Maintenance:
Ollama updates](#maintenance-ollama-updates)) to restore your ROCm build.
The model architecture is unrelated to GPU support.

### `cmake configure` succeeds but `Looking for a HIP compiler - NOTFOUND`

Means the HIP compiler isn't on `PATH` and `CMAKE_HIP_COMPILER` wasn't
overridden. The build script handles this; if you're running CMake by hand,
add:

```
-DCMAKE_HIP_COMPILER="C:/Program Files/AMD/ROCm/7.1/bin/clang++.exe"
```

---

## How this actually works

For the curious, three key insights make this work:

1. **The GPU stack is fine** — `hipinfo.exe` from HIP SDK 7.1.1 detects
   `gfx1201` in 1.5 s on a stock system with no extra config. The HIP
   runtime, AMD driver, and HSA initialisation all work out of the box.
2. **Ollama's source code is fine** — `ml/backend/ggml/ggml/src/ggml-hip/`
   compiles cleanly against ROCm 7's headers, and `CMakePresets.json` ships
   with a `"ROCm 7"` preset that already includes `gfx1201` in
   `AMDGPU_TARGETS`. No source patches are needed.
3. **The official binaries are the problem** — Ollama's CI (see
   `.github/workflows/release.yaml:109-113` in the ollama repo) builds
   exclusively against ROCm 6.2, because that's the LCD that supports the
   widest set of GPUs. Their pre-built `ggml-hip.dll` and bundled
   `amdhip64_6.dll` cannot talk to a ROCm 7 driver stack at runtime.

The build pipeline here is intentionally close to Ollama's own
`scripts/build_windows.ps1`: same compiler (`$HIP_PATH\bin\clang++.exe`),
same env vars (`HIPCXX`, `HIP_PLATFORM`, `CMAKE_PREFIX_PATH`), same flags
(`-parallel-jobs=4 -Wno-ignored-attributes -Wno-deprecated-pragma`). The
only deviations:

- preset `"ROCm 7"` instead of `"ROCm 6"`
- `-DCMAKE_HIP_COMPILER` is set explicitly (CMake's `check_language(HIP)`
  doesn't auto-detect it on Windows reliably)
- `-DAMDGPU_TARGETS="gfx1201"` to skip building kernels for 12 other GPUs we
  don't need (cuts build time by ~75 % and DLL size from 914 MB to 57 MB)

---

## Disclaimer & credits

This is an unofficial community recipe. It is **not endorsed by Ollama, AMD,
or anyone else**. If it breaks your install, your warranty does not get
voided, but you'll have to fix it yourself — the `rocm.bak.<timestamp>`
folders created by `rocm-deploy.ps1` are your fallback.

Builds from this repository contain no modifications to Ollama or HIP — the
sources are pulled fresh from their upstream repositories and built with the
arguments described here.

This project is built using Claude Code (Anthropic) — see
[AI-DISCLOSURE.md](AI-DISCLOSURE.md) for details on the human/AI
collaboration model.

### What is in the release ZIP

The redistributed ZIP **only contains MIT-licensed files**. Everything in
the archive is built from or is a part of:

| File(s) | Upstream | License |
|---|---|---|
| `ggml-hip.dll` | Built from [ollama/ollama](https://github.com/ollama/ollama) source | MIT |
| `rocblas.dll` + `rocblas/library/*` | [ROCm/rocBLAS](https://github.com/ROCm/rocBLAS) | MIT |
| `libhipblas.dll` | [ROCm/hipBLAS](https://github.com/ROCm/hipBLAS) | MIT |
| `libhipblaslt.dll` | [ROCm/hipBLASLt](https://github.com/ROCm/hipBLASLt) | MIT |

### What is NOT in the release ZIP

`amdhip64_7.dll` is **deliberately excluded**. This file is part of AMD's
proprietary HIP runtime and ships with the AMD Adrenalin driver and the HIP
SDK installer under AMD's own EULA. The deploy script copies it at install
time from your own `C:\Program Files\AMD\ROCm\7.1\bin\` — you already have
it because the HIP SDK is a prerequisite (Step 2 of either path).

This keeps the redistribution strictly within MIT-licensed territory and
avoids questions about redistributing AMD's runtime binaries.

### Script license

The scripts (`scripts/build-rocm.ps1`, `scripts/rocm-deploy.ps1`) and the
documentation in this repository are released under the **MIT License**,
same as Ollama upstream.

Inspiration / prior art:

- [doroch.com — AI on AMD Radeon RX 9000](https://www.doroch.com/post/ai-on-amd-radeon-rx-9000-local-llm-ollama-rocm-gpt-oss-qwen3/)
  (the original community workaround using the ROCBLAS_TENSILE_LIBPATH env
  var — worked with Ollama 0.16.1 + Adrenalin 25.1.x, no longer sufficient
  with newer combinations).
- [likelovewant/ollama-for-amd](https://github.com/likelovewant/ollama-for-amd)
  — fork shipping fat binaries with many AMD architectures. Heavyweight
  (≈ 1 GB) but covers more cards.
- [ByronLeeeee/Ollama-For-AMD-Installer](https://github.com/ByronLeeeee/Ollama-For-AMD-Installer)
  — automated installer wrapping the fork above.

Filed bugs (track upstream progress):

- `ollama/ollama#13236` — gfx1201 discovery timeout
- `ollama/ollama#13000` — native gfx1201 support PR
- `ROCm/ROCm#5812` — rocminfo/HSA-init on RDNA 4 Windows

If upstream Ollama eventually ships ROCm-7 binaries by default, this
repository becomes obsolete and that's a good thing. Until then, here we
are.
