# ComfyUI development environment

This repository provides a standalone Nix development environment for running
[ComfyUI](https://github.com/comfyanonymous/ComfyUI) on two machines:

- **oryp6** (x86_64-linux), a Pop!_OS machine with an NVIDIA GPU. The NVIDIA
  driver is installed by apt; GPU-enabled ComfyUI, PyTorch, and the CUDA
  runtime are available only inside `nix develop`.
- **M5** (aarch64-darwin), an Apple Silicon Mac. ComfyUI runs headless there
  using PyTorch's Metal Performance Shaders (MPS) backend; no NVIDIA tooling
  is involved.

It also contains an optional ComfyUI node that requests images from Ollama image
models running on M5 through an SSH tunnel (`m5-tunnel`).

## Quick start (oryp6, x86_64-linux)

```bash
cd ~/Work/comfyui
nix develop                 # first run downloads/builds roughly 2 GiB
comfyui-check
comfyui-smoke

# On M5, start the image instance with ollama-imagegen start (provided by home-manager; see docs/m5-imagegen-instance.md).
M5_HOST=<m5-ip> m5-tunnel start
comfyui
```

oryp6 users should enable the `comfyui.cachix.org` substituter with
`--accept-flake-config` (or be a trusted user) — see
[Cachix substituter](#cachix-substituter) below.

## Quick start (M5, aarch64-darwin)

```bash
cd ~/Work/comfyui
nix develop                 # first run is ~3h cold (see "Darwin valkey override" below)
comfyui-check
comfyui
```

ComfyUI on M5 runs through `caffeinate -i` (keep-awake while running) and only
binds `127.0.0.1` — the darwin `comfyui` wrapper refuses any other
`COMFYUI_LISTEN` value. Bundled custom nodes are skipped
(`COMFY_SKIP_BUNDLED_NODES=1`) and `--enable-manager` is never passed.
`caffeinate` does **not** prevent lid-closed sleep.

Then open <http://127.0.0.1:8188>. Store models under
`~/.local/share/comfyui/models`. If you have existing content under the
legacy repo-local `./data`, run `comfyui-migrate-data` to move it into place.

## XDG data and state paths

ComfyUI data (models, output, input, user, custom_nodes, caches) defaults to
`${XDG_DATA_HOME:-$HOME/.local/share}/comfyui` on both machines
(`COMFYUI_DATA_DIR` overrides it). The verified build's GC root and future
`dev-profile` live under `${XDG_STATE_HOME:-$HOME/.local/state}/comfyui`.

## NVIDIA guard (Linux only)

The dev-shell hook's NVIDIA/`.nvidia-libs`/`LD_LIBRARY_PATH` setup only runs
on Linux (`uname = Linux`); on Darwin it prints a short MPS banner instead and
does nothing NVIDIA-related.

## Ollama image-generation node

The `Ollama Image Gen (M5)` node appears in ComfyUI under **image/ollama**. It
supports `x/z-image-turbo` and `x/flux2-klein` and calls Ollama's
OpenAI-compatible image-generation endpoint. Its default endpoint is
`OLLAMA_IMAGEGEN_URL=http://127.0.0.1:11435`, which is the local `m5-tunnel`
Ollama forward.

## m5-tunnel

`m5-tunnel` is the canonical tunnel command (run from oryp6); `ollama-tunnel`
is kept as a deprecated alias that prints a notice and execs `m5-tunnel`. A
single `ssh` session carries two forwards:

- Ollama: `127.0.0.1:${OLLAMA_TUNNEL_LOCAL_PORT:-11435}` →
  `127.0.0.1:${OLLAMA_TUNNEL_REMOTE_PORT:-11436}` (the M5 image instance).
- ComfyUI: `127.0.0.1:${COMFYUI_TUNNEL_LOCAL_PORT:-8189}` →
  `127.0.0.1:${COMFYUI_TUNNEL_REMOTE_PORT:-8188}` (ComfyUI running on M5).

```bash
M5_HOST=<m5-ip> m5-tunnel start
m5-tunnel check
m5-tunnel status
m5-tunnel stop
```

`--direct` (the `socat` fallback) stays Ollama-only; it prints that ComfyUI
requires ssh mode. If local port 8189 is already in use, `start` warns and
falls back to an Ollama-only forward.

## Darwin valkey override

Upstream `comfyui-nix` (`58f91b0`) ships `python3.12-valkey-6.1.1`, whose test
suite has 13 tests that hard-code `localhost:6379`/sentinel addresses. These
fail in the darwin build sandbox (no network, no local redis/valkey server);
upstream's own darwin `preCheck` does not cover them, and upstream CI never
builds darwin. `nix/comfyui-darwin.nix` carries a test-only `doCheck = false`
override for `valkey`, composed underneath upstream's own python overrides, and
sources nixpkgs from `comfyui-nix.inputs.nixpkgs` (never this flake's
top-level `nixpkgs`) to keep the darwin `comfy-ui` store path byte-equivalent
to the verified spike build. Remove this override once upstream fixes valkey
on darwin — switch `comfyPkg` back to
`comfyui-nix.packages.aarch64-darwin.default`.

The **first M5 build is roughly 3 hours** and has parallelism-sensitive test
timeouts (`portalocker`, `python-utils`, `mirakuru`, `h5py`, `openai` fail only
under build load). For a cold build, use `--max-jobs 1` (or `2`):

```bash
nix build --max-jobs 1 .#packages.aarch64-darwin.comfy-ui
```

## Torch / MPS notes

Torch 2.5.1 on M5 has no fp8 support on MPS — use fp16 or bf16 workflows
instead.

## Tests

```bash
nix develop .#test --command pytest -q tests/
```

## Cachix substituter

`flake.nix` declares a top-level `nixConfig` pointing at
`https://comfyui.cachix.org` (key `comfyui.cachix.org-1:...`, matching
[docs/host-prerequisites.md](docs/host-prerequisites.md)). This cache has no
darwin builds, so it benefits oryp6 only. An input's own `nixConfig` is
ignored by Nix; only a flake's own top-level `nixConfig` is honoured, and only
for trusted users or with `--accept-flake-config`.

## Documentation

- [Host prerequisites](docs/host-prerequisites.md)
- [Manual SSH-tunnel spike](docs/ssh-tunnel-spike.md)
- [M5 Ollama image-generation instance](docs/m5-imagegen-instance.md)
- [M5 headless ComfyUI MPS spike](docs/m5-comfyui-spike.md)

## Troubleshooting

### M5 image instance must be Ollama 0.32.5

Ollama 0.32.6 removed image generation. Symptoms are `404 page not found` on
the image route or `400 ... not currently supported`. Keep the daily
Ollama.app on the latest release at port 11434; the tunnel forwards to the
separate image instance at port 11436 through `OLLAMA_TUNNEL_REMOTE_PORT`.
Follow the setup in [docs/m5-imagegen-instance.md](docs/m5-imagegen-instance.md).

### ComfyUI-not-running vs tunnel-down

`m5-tunnel check`/`status` report the Ollama forward as fatal (tunnel down is
an error) but ComfyUI reachability on `127.0.0.1:8189` only as a non-fatal
warning — ComfyUI being stopped on M5 does not tear down a healthy tunnel.
`comfyui-check --tunnel` runs `m5-tunnel check` and treats "tunnel down" as
fatal, "ComfyUI not running on M5" as a non-fatal warning.

### M5 sleep

M5 must stay awake while generating. The tunnel's keep-awake is a separate
multiplexed SSH session running `caffeinate -i -w $PPID` for the life of the
tunnel, which handles idle sleep but does **not** keep the tunnel alive through
sleep. Closing the lid or MDM-forced sleep still breaks it; recover by running
`m5-tunnel start`, which is idempotent and stale-safe. Set
`OLLAMA_TUNNEL_KEEP_AWAKE=0` to opt out. The background serve may also need
`ollama-imagegen start` on M5 after sleep.

### Model idle unload

Ollama unloads the model after roughly five minutes idle. `ollama ps` shows the
keep-alive countdown, so the first generation after idle is slower while the
model reloads. This is normal, not a failure.

### Node error messages

- `Ollama request to <url> timed out after <timeout>s` means the request took
  too long.
- `connection to M5 dropped mid-response (M5 asleep or tunnel died?)` means M5
  slept or the tunnel died while a response was in flight.
- `Ollama on M5 unreachable at <url> ...` means the tunnel is down; run
  `m5-tunnel start`.
- `Ollama returned HTTP 404: ...` or `Ollama returned HTTP 400: ...` with the
  0.32.5 hint means the tunnel does not target the required image instance.
- `Ollama returned an empty or non-JSON response: ...` means the image endpoint
  returned no valid JSON payload.

### `m5-tunnel check --generate`

This user-invoked command performs a real 256×256 generation for each model:
`x/z-image-turbo` and `x/flux2-klein`.

### Verify keep-awake on M5 (manual)

On M5, `pgrep -fl caffeinate` shows `caffeinate -i -w <pid>` while the tunnel
is up. After `m5-tunnel stop` on oryp6, it is gone within a few seconds. If
it lingers, run `pkill -f 'caffeinate -i -w'` on M5 and use
`OLLAMA_TUNNEL_KEEP_AWAKE=0`.
