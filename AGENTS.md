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
| `scripts/m5-tunnel.sh` | Canonical tunnel: Ollama + ComfyUI forwards to M5. |
| `scripts/comfyui-migrate-data.sh` | Merge-migrates legacy `./data` into the XDG data dir. |
| `nix/comfyui-darwin.nix` | Darwin `comfy-ui` package expression carrying the test-only valkey override. |
| `custom_nodes/ollama_imagegen/` | Ollama image-generation ComfyUI node. |
| `tests/` | Unit tests for custom nodes. |
| `docs/` | Host, SSH-tunnel, M5 image-instance (Ollama 0.32.5), and M5 ComfyUI MPS spike runbooks. |

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
  `m5-tunnel start <host>`.
- `comfyui` runs only inside the development shell, guarded by
  `COMFYUI_SHELL=1`.
- The `comfy-ui` launcher prepends its own libraries to `LD_LIBRARY_PATH`.
  `comfyui-check --server` and `comfyui-smoke` are the runtime checks that
  `.nvidia-libs` still takes effect.
- M5's daily Ollama.app stays on the latest release (127.0.0.1:11434); the
  home-manager `ollama-imagegen` module provides the separate frozen Ollama
  0.32.5 image instance on 127.0.0.1:11436, with models in
  `~/.local/share/ollama-imagegen/models` (see docs/m5-imagegen-instance.md),
  which m5-tunnel targets by default via OLLAMA_TUNNEL_REMOTE_PORT. Ollama
  0.32.6+ removed image generation.
- The model list `x/z-image-turbo`, `x/flux2-klein` is duplicated in the node
  `INPUT_TYPES`, the `m5-tunnel check` jq filter, and the docs — keep all
  three in sync.
- Use Conventional Commits for commit messages.
- **Platform split.** The pipeline/dev machine is the **M5**. On the M5,
  `nix flake check` checks only aarch64-darwin outputs (x86_64-linux is
  eval-gated with explicit `nix eval` and built manually on oryp6); never run
  it with `--all-systems` (it would try to build the x86_64-linux checks with
  no linux builder available). `checks` must stay `comfyPkg`-free on both
  systems — `checks` build on the M5, so they must never pull in `comfyPkg`.
- **Darwin valkey override.** `nix/comfyui-darwin.nix`'s test-only
  `doCheck = false` valkey override must keep the darwin `comfy-ui` outPath
  identical to the verified build: source nixpkgs from
  `comfyui-nix.inputs.nixpkgs` (never this flake's top-level `nixpkgs`) and
  leave the `config`/`overlays` order unchanged. Remove the override entirely
  once upstream fixes valkey on darwin.
- New flake code that branches on platform uses
  `pkgs.stdenv.hostPlatform.isLinux` / `isDarwin`, never the deprecated
  `stdenv.isLinux` / `stdenv.isDarwin`.
- The darwin `comfyui` wrapper refuses any `COMFYUI_LISTEN` other than
  `127.0.0.1`, exports `COMFY_SKIP_BUNDLED_NODES=1`, never passes
  `--enable-manager`, and execs `/usr/bin/caffeinate -i comfy-ui` (called by
  absolute path — it is an Apple system binary, no Nix package).
- `M5_HOST` stays unset in the repo. `m5-tunnel` is canonical;
  `ollama-tunnel` is a deprecation shim that execs it.
- `.nvidia-libs` / `LD_LIBRARY_PATH` handling in `scripts/shell-hook.sh` stays
  Linux-only (guarded by `uname`); Darwin prints an MPS banner instead.
- The model-list sync triplet (see above) now names the `m5-tunnel check` jq
  filter as the third site.
- The `comfyui.cachix.org-1:` key in `flake.nix`'s `nixConfig` stays in sync
  with `docs/host-prerequisites.md`.
- The `scripts/comfyui.sh` and `scripts/shell-hook.sh` data-dir fallback
  strings (`${XDG_DATA_HOME:-$HOME/.local/share}/comfyui`) stay byte-identical.
- `scripts/comfyui-smoke.sh`'s darwin path avoids `setsid` (absent on macOS);
  it backgrounds plainly and reaps via `pkill -P`/`kill`.
