# M5 headless ComfyUI MPS spike

> **Manual procedure:** this runbook is not part of the automated pipeline.

## Intro

This spike builds and runs ComfyUI headless on M5 (aarch64-darwin) on CPU+MPS
using the upstream `comfyui-nix` package `packages.aarch64-darwin.default`,
which ships prebuilt torch 2.5.1 / torchvision 0.20.1 wheels. It deliberately
tests the upstream package first, before any local flake platform-split work.
This repo's `flake.lock` already pins `comfyui-nix` at rev
`58f91b001c99a97df46b7be8d58b08f01cb8f6ff` (the spike rev), so building the
same rev here will not force a rebuild later.

## Prerequisites (step 0)

- M5 on mains power, lid open, at least ~40 GB free disk.
- Verified dry-run figures (indicative only): ~1137 derivations to build,
  ~5.8 GiB download, ~24.0 GiB unpacked, eval ~3m30s.
- Jan must be a trusted user under Determinate Nix.
- `comfyui.cachix.org` has no darwin builds, so this is a full local build.

## Step 1 — Build

```bash
mkdir -p ~/.local/state/comfyui
time nix build --keep-going -L -o ~/.local/state/comfyui/gcroot-spike \
  'github:utensils/comfyui-nix/58f91b001c99a97df46b7be8d58b08f01cb8f6ff#packages.aarch64-darwin.default' \
  2>&1 | tee ~/.local/state/comfyui/spike-build.log
```

Record total build time, any failing derivations, and any `doCheck = false`
(test-only) overrides applied or upstream issue filed.

## Step 2 — Run headless

```bash
COMFY_SKIP_BUNDLED_NODES=1 ~/.local/state/comfyui/gcroot-spike/bin/comfy-ui \
  --base-directory ~/.local/share/comfyui --listen 127.0.0.1 --port 8188
```

Checks to record: the log line `Device: mps`; Manager is off (no
`--enable-manager` passed); the exact paths of any writes outside
`~/.local` — explicitly inspect `~/Library/Application Support/comfy-ui`,
`~/.cache/huggingface`, `~/.cache/torch` (these feed the Plan B cache-env
step); and that `lsof -nP -iTCP:8188 -sTCP:LISTEN` shows a `127.0.0.1`-only
bind.

## Step 3 — Local txt2img

Run a small fp16/bf16 checkpoint (no fp8 on MPS) via `http://127.0.0.1:8188`,
and record s/it and time per image.

## Step 4 — Over the SSH tunnel

No committed M5 address; use placeholders:

```bash
ssh -N -L 127.0.0.1:8189:127.0.0.1:8188 <user>@<m5>
```

Open `http://localhost:8189`, run the same workflow, confirm live
progress/previews over `/ws`, and confirm the existing Ollama tunnel on port
11435 still works alongside this forward.

## Results

| Date | Build time | Failures / overrides | Device (mps?) | s/it | Works via tunnel | Writes outside ~/.local | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-10-26 | 2h53m + -j1 retry + 16m41s | valkey doCheck=false (upstream darwin fix incomplete: 13 tests hard-code :6379); portalocker/python-utils/mirakuru/h5py/openai timeouts passed on -j1 retry | y | 0.25 | y | n | SD1.5 fp16 512² 20 steps: 5.3 s/image warm, 15.5 s cold (1.80 it/s cold, 4.02 it/s warm); live progress/preview over tunnel OK; ollama-tunnel alongside: ok |

## Stop conditions & fallbacks

Stop if the build fails beyond test-only `doCheck = false` overrides, or if
the run logs `Device: cpu`. Fallback option 2: build a slim darwin closure
without bundled-node python deps. Fallback option 3: a `uv` venv under
`~/.local`, darwin-only. Any fallback invalidates the Plan B platform-split
assumption and requires redesigning that split first.

## Gate for Plan B

Plan B (`plan_ref a9d4e715-2c3b-4f80-8b16-5e9f7a2d0c48`) is a separate, parked
plan because an unattended pipeline runs all phases of a stored plan
back-to-back. Unpark Plan B only once the Results table has a row with
`Device = mps` and a successful build (recorded test-only overrides are
acceptable). If the spike fell back to option 2/3, redesign the Plan B
platform split before unparking.

## Cleanup / after the spike

The persistent GC root later becomes
`nix develop --profile ~/.local/state/comfyui/dev-profile`; then
`rm ~/.local/state/comfyui/gcroot-spike` makes the spike closure GC-eligible.
If the spike is abandoned: `rm` the gcroot and run `nix store gc` to recover
~24 GiB.
