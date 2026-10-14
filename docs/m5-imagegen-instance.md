# M5 Ollama image-generation instance

## Why

Ollama 0.32.6+ removed image generation. Keep the daily Ollama.app on the
latest release at `127.0.0.1:11434`, and use a separate standalone Ollama
0.32.5 instance for image generation at `127.0.0.1:11436` with its own models
directory. The standalone tarball has no tray app and no auto-updater, so it
stays pinned.

## Restore the daily Ollama.app to latest

1. Download the latest Ollama for macOS from [ollama.com](https://ollama.com)
   or the GitHub releases page.
2. Quit Ollama.
3. Replace `/Applications/Ollama.app`.
4. Launch it and turn **Auto-download updates** back **ON** in Settings.

## Install the image instance

Run these commands on M5:

```bash
mkdir -p ~/opt/ollama-0.32.5
cd /tmp
curl -fLO https://github.com/ollama/ollama/releases/download/v0.32.5/ollama-darwin.tgz
echo "5789dd037a86adb328c72c11fc45e6c558452d07e5b50814a8bdb7b0fbdbcd81  ollama-darwin.tgz" | shasum -a 256 -c
tar -xzf ollama-darwin.tgz -C ~/opt/ollama-0.32.5
ls -R ~/opt/ollama-0.32.5 | head
```

The tarball layout may put the binary at `~/opt/ollama-0.32.5/ollama` or
`~/opt/ollama-0.32.5/bin/ollama`. Use whichever exists, and set
`OLLAMA_IMAGEGEN_BIN` accordingly in the function below. Downloading with curl
avoids the Gatekeeper quarantine attribute. If macOS still blocks it, run:

```bash
xattr -dr com.apple.quarantine ~/opt/ollama-0.32.5
```

## Shell function

Add this to `~/.zshrc`:

```bash
export OLLAMA_IMAGEGEN_BIN="$HOME/opt/ollama-0.32.5/ollama"
ollama-imagegen() {
  OLLAMA_HOST=127.0.0.1:11436 OLLAMA_MODELS="$HOME/.ollama-imagegen/models" "$OLLAMA_IMAGEGEN_BIN" "$@"
}
```

## Use it (free-time experiments)

1. In an M5 terminal, run `ollama-imagegen serve` in the foreground. Ctrl-C
   stops it.
2. In a second terminal, run these once:

   ```bash
   ollama-imagegen pull x/z-image-turbo
   ollama-imagegen pull x/flux2-klein
   ```

3. `ollama-imagegen --version` should report 0.32.5. Alternatively, use
   `curl -s http://127.0.0.1:11436/api/version`.
4. `ollama-imagegen list` and `ollama-imagegen ps` work as usual.
5. Then on oryp6, run `M5_HOST=<m5-ip> ollama-tunnel start`, which forwards
   local port 11435 to M5 port 11436 by default. Run `ollama-tunnel check`,
   optionally `ollama-tunnel check --generate`, and then `comfyui`.

## Fallback if generation fails with an MLX library error

The standalone tarball may lack the MLX runtime. In that case:

1. Download `Ollama-darwin.zip` v0.32.5.
2. Extract it to `~/opt/ollama-0.32.5-app/`, **not** `/Applications`.
3. Never launch that `.app`, because it would auto-update and fight the daily
   app for port 11434.
4. Set:

   ```bash
   export OLLAMA_IMAGEGEN_BIN="$HOME/opt/ollama-0.32.5-app/Ollama.app/Contents/Resources/ollama"
   ```

## Housekeeping

- The separate models directory avoids cross-version interference.
- After the image instance has its own copies, free roughly 19 GB in the daily
  instance with `ollama rm x/z-image-turbo x/flux2-klein`.
- Running both instances at once is fine on a 64 GB M5.
- Keep the image instance bound to `127.0.0.1` so the SSH tunnel reaches it.
  Bind `0.0.0.0:11436` only for the `ollama-tunnel start --direct` fallback;
  that exposes Ollama without authentication to the LAN.

## Sleep

While the tunnel is up, `ollama-tunnel` holds `caffeinate -i -w $PPID` on M5,
which prevents idle sleep. It does **not** keep the tunnel alive through sleep:
a closed lid or MDM-forced sleep still breaks it. Recover with
`ollama-tunnel start`.
