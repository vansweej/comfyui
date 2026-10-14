# SSH tunnel spike

> **Manual procedure:** this runbook is not part of the automated pipeline.

The preferred M5 integration keeps Ollama bound to M5 loopback and forwards it
over SSH. Confirm that the company policy allows the required access before
continuing.

## Prepare M5

1. Enable **Remote Login** in **System Settings → General → Sharing** if IT
   allows it.
2. From oryp6, install an SSH key:

   ```bash
   ssh-copy-id janvansweevelt@<m5-ip>
   ```

3. On M5, pull the required image models into the image instance with
   `ollama-imagegen pull ...` (Ollama 0.32.5 on `127.0.0.1:11436`; see
   [docs/m5-imagegen-instance.md](m5-imagegen-instance.md)):

   ```bash
   ollama-imagegen pull x/z-image-turbo
   ollama-imagegen pull x/flux2-klein
   ```

## Exercise the tunnel from oryp6

```bash
cd ~/Work/comfyui
nix develop
M5_HOST=<m5-ip> ollama-tunnel start
ollama-tunnel check
ollama-tunnel status
ollama-tunnel stop
```

If SSH is unavailable, the fallback is M5 LAN home mode via `ollama-net` from
the home-manager integration, paired with:

```bash
M5_HOST=<m5-ip> ollama-tunnel start --direct
```

## Keep-awake

For the life of the tunnel, a separate multiplexed SSH session runs
`caffeinate -i -w $PPID`. Set `OLLAMA_TUNNEL_KEEP_AWAKE=0` to opt out.
Caffeinate prevents idle sleep, but does not survive a closed lid or
MDM-forced sleep and does not keep the tunnel alive through sleep.

On M5, `pgrep -fl caffeinate` shows `caffeinate -i -w <pid>` while the tunnel
is up. It is gone a few seconds after `ollama-tunnel stop`.

| Date | Mode | Latency | z-image-turbo | flux2-klein | Notes |
| --- | --- | --- | --- | --- | --- |
| 2026-10-14 | ssh | | y | not yet verified | requires Ollama 0.32.5 image instance; breaks on M5 sleep |
