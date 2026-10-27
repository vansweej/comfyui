# M5 Ollama image-generation instance

## Why

Ollama 0.32.6+ removed image generation. The daily Ollama.app stays on the
latest release at `127.0.0.1:11434`. A separate frozen Ollama 0.32.5 instance
serves image generation at `127.0.0.1:11436` with its own models directory.

## How it is provided

The image instance is provided declaratively by the user's home-manager setup:
the `ollama-imagegen` module in `~/Projects/home-manager`
(`modules/ollama-imagegen.nix` and that repository's
`docs/ollama-imagegen.md`). It is imported on M5 (and M1) and is aarch64-darwin
only.

The module fetches the `ollama-darwin.tgz` v0.32.5 release with `fetchurl`,
pins its hash, and unpacks it into the Nix store. Nothing is installed outside
the Nix store and `~/.local`; in particular, nothing goes into `/Applications`
or a system-level directory. It never auto-updates.

It provides an `ollama-imagegen` command on `PATH` through a
`writeShellApplication` wrapper. The wrapper always talks to
`127.0.0.1:11436`, clears every inherited `OLLAMA_*` variable, then sets
`OLLAMA_HOST=127.0.0.1:11436` and
`OLLAMA_MODELS=~/.local/share/ollama-imagegen/models`, isolating it from the
daily Ollama. The wrapper manages the `start`, `stop`, `status`, `logs`, and
`help` subcommands. Anything else (`serve`, `pull`, `list`, `ps`, `rm`, `show`,
`--version`, …) passes straight through to the frozen 0.32.5 binary. There is
no launchd agent: the instance runs on demand via `ollama-imagegen start`.

## Restore the daily Ollama.app to latest

1. Download the latest Ollama for macOS from [ollama.com](https://ollama.com)
   or the GitHub releases page.
2. Quit Ollama.
3. Replace `/Applications/Ollama.app`.
4. Launch it and turn **Auto-download updates** back **ON** in Settings.

## First-time setup on M5

1. Run `home-manager switch`.
2. Confirm that `ollama-imagegen --version` reports 0.32.5.
3. Run `ollama-imagegen start`, then `ollama-imagegen status`.
4. Pull the image models:

   ```bash
   ollama-imagegen pull x/z-image-turbo
   ollama-imagegen pull x/flux2-klein
   ```

   They require roughly 13 GB and 5.7 GB, respectively.
5. Optionally test locally:

   ```bash
   curl -s http://127.0.0.1:11436/api/version
   ```

## Daily use (free-time experiments)

On M5, start the instance:

```bash
ollama-imagegen start
```

On oryp6 in the development shell, start the tunnel (local 11435 → M5 11436 by
default), check it, optionally generate a test image, and launch ComfyUI:

```bash
M5_HOST=<m5-ip> m5-tunnel start
m5-tunnel check
m5-tunnel check --generate
comfyui
```

When finished, run `m5-tunnel stop` on oryp6 and `ollama-imagegen stop` on
M5. Use `ollama-imagegen logs` for troubleshooting.

## Paths

| Path | Purpose |
| --- | --- |
| `~/.local/share/ollama-imagegen/models` | Models directory |
| `~/.local/state/ollama-imagegen` | State directory |
| `~/.local/state/ollama-imagegen/serve.log` | Serve log |
| `~/.local/state/ollama-imagegen/serve.pid` | PID file |

These directories are created at `home-manager switch`; models are not pulled
automatically.

## Fallback if generation fails with an MLX library error

If the tarball ever lacks the MLX runtime, change the module's `sources`
attrset in the home-manager repository to `Ollama-darwin.zip` v0.32.5, then run
`home-manager switch`. This is a home-manager change, not a manual extraction.

## Housekeeping

Free roughly 19 GB in the daily instance with
`ollama rm x/z-image-turbo x/flux2-klein` (use the daily `ollama`, not
`ollama-imagegen`). Running both instances at once is fine on a 64 GB M5. The
image instance is bound to `127.0.0.1` only.

Binding the image instance on the LAN for the `m5-tunnel start --direct`
socat fallback is not supported by the current home-manager module because its
host and port are hard-coded to `127.0.0.1:11436`. The SSH tunnel is the
supported path; reaching the image instance over `--direct` would require
changing the home-manager module.

## Sleep

While the tunnel is up, `m5-tunnel` holds `caffeinate -i -w $PPID` on M5,
preventing idle sleep. It does **not** keep the tunnel alive through sleep: a
closed lid or MDM-forced sleep still breaks it and may stop the background
serve. Recover with `ollama-imagegen status` and `ollama-imagegen start` on M5,
then `m5-tunnel start` on oryp6 (`ollama-tunnel` is a deprecated alias for
`m5-tunnel`).
