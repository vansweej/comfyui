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

M5_HOST=<m5-ip> ollama-tunnel start
comfyui
```

Then open <http://127.0.0.1:8188>. Store models under `./data/models`.

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
