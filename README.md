# ComfyUI development environment

This repository provides a standalone Nix development environment for running
[ComfyUI](https://github.com/comfyanonymous/ComfyUI) on **oryp6**, a Pop!_OS
machine with an NVIDIA GPU. The NVIDIA driver is installed by apt; GPU-enabled
ComfyUI, PyTorch, and the CUDA runtime are available only inside `nix develop`.

It also contains an optional ComfyUI node that requests images from Ollama image
models running on M5 through an SSH tunnel.

## Quick start

```bash
cd ~/Work/comfyui
nix develop                 # first run downloads/builds roughly 2 GiB
comfyui-check
comfyui-smoke

# On M5, start the image instance with ollama-imagegen start (provided by home-manager; see docs/m5-imagegen-instance.md).
M5_HOST=<m5-ip> ollama-tunnel start
comfyui
```

Then open <http://127.0.0.1:8188>. Store models under
`~/.local/share/comfyui/models`. If you have existing content under the
legacy repo-local `./data`, run `comfyui-migrate-data` to move it into place.

## Ollama image-generation node

The `Ollama Image Gen (M5)` node appears in ComfyUI under **image/ollama**. It
supports `x/z-image-turbo` and `x/flux2-klein` and calls Ollama's
OpenAI-compatible image-generation endpoint. Its default endpoint is
`OLLAMA_IMAGEGEN_URL=http://127.0.0.1:11435`, which is the local `ollama-tunnel`
forward to M5.

## Tests

```bash
nix develop .#test --command pytest -q tests/
```

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

### M5 sleep

M5 must stay awake while generating. The tunnel's keep-awake is a separate
multiplexed SSH session running `caffeinate -i -w $PPID` for the life of the
tunnel, which handles idle sleep but does **not** keep the tunnel alive through
sleep. Closing the lid or MDM-forced sleep still breaks it; recover by running
`ollama-tunnel start`, which is idempotent and stale-safe. Set
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
  `ollama-tunnel start`.
- `Ollama returned HTTP 404: ...` or `Ollama returned HTTP 400: ...` with the
  0.32.5 hint means the tunnel does not target the required image instance.
- `Ollama returned an empty or non-JSON response: ...` means the image endpoint
  returned no valid JSON payload.

### `ollama-tunnel check --generate`

This user-invoked command performs a real 256×256 generation for each model:
`x/z-image-turbo` and `x/flux2-klein`.

### Verify keep-awake on M5 (manual)

On M5, `pgrep -fl caffeinate` shows `caffeinate -i -w <pid>` while the tunnel
is up. After `ollama-tunnel stop` on oryp6, it is gone within a few seconds. If
it lingers, run `pkill -f 'caffeinate -i -w'` on M5 and use
`OLLAMA_TUNNEL_KEEP_AWAKE=0`.
