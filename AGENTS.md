# Development guide

## Commands

Run project tools through the Nix development shell:

```bash
nix develop --command <command>
```

Use the lightweight test shell for node unit tests:

```bash
nix develop .#test --command pytest -q tests/
```

## Layout

| Path | Purpose |
| --- | --- |
| `flake.nix` | Nix flake, dev shells, and script packages. |
| `scripts/` | Shell hooks and command wrappers. |
| `custom_nodes/ollama_imagegen/` | Ollama image-generation ComfyUI node. |
| `tests/` | Unit tests for custom nodes. |
| `docs/` | Host and SSH-tunnel runbooks. |

## Conventions

- Keep substantial Bash in `scripts/*.sh`, loaded through `builtins.readFile`
  into `writeShellApplication`; do not put large Bash programs in Nix strings.
  Script packages must remain ShellCheck-clean and receive `set -euo pipefail`
  from `writeShellApplication`.
- Never put `/usr/lib/x86_64-linux-gnu` on `LD_LIBRARY_PATH`. Only the selected
  driver-library symlinks in `.nvidia-libs` belong there: host glibc 2.35 and
  Nix glibc 2.42 can otherwise cause segmentation faults.
- Install and update the NVIDIA driver through Pop!_OS apt, never through Nix.
- Do not commit an M5 address. Supply it with `M5_HOST` or
  `ollama-tunnel start <host>`.
- `comfyui` runs only inside the development shell, guarded by
  `COMFYUI_SHELL=1`.
- The `comfy-ui` launcher prepends its own libraries to `LD_LIBRARY_PATH`.
  `comfyui-check --server` and `comfyui-smoke` are the runtime checks that
  `.nvidia-libs` still takes effect.
- Use Conventional Commits for commit messages.
