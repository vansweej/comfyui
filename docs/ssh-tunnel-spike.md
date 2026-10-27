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

3. On M5, first start the image instance with `ollama-imagegen start` (provided
   by home-manager; see [docs/m5-imagegen-instance.md](m5-imagegen-instance.md)),
   then pull the required image models (Ollama 0.32.5 on `127.0.0.1:11436`):

   ```bash
   ollama-imagegen pull x/z-image-turbo
   ollama-imagegen pull x/flux2-klein
   ```

## Exercise the tunnel from oryp6

```bash
cd ~/Work/comfyui
nix develop
M5_HOST=<m5-ip> m5-tunnel start
m5-tunnel check
m5-tunnel status
m5-tunnel stop
```

`m5-tunnel` is the canonical command (`ollama-tunnel` is kept as a deprecated
alias). The SSH tunnel is the supported path. The `m5-tunnel start --direct`
(socat) fallback cannot reach the image instance because the home-manager
`ollama-imagegen` module hard-codes `127.0.0.1:11436`; LAN mode was never
deployed. Using `--direct` would require changing the home-manager module.

## Keep-awake

For the life of the tunnel, a separate multiplexed SSH session runs
`caffeinate -i -w $PPID`. Set `OLLAMA_TUNNEL_KEEP_AWAKE=0` to opt out.
Caffeinate prevents idle sleep, but does not survive a closed lid or
MDM-forced sleep and does not keep the tunnel alive through sleep.

On M5, `pgrep -fl caffeinate` shows `caffeinate -i -w <pid>` while the tunnel
is up. It is gone a few seconds after `m5-tunnel stop`.

| Date | Mode | Latency | z-image-turbo | flux2-klein | Notes |
| --- | --- | --- | --- | --- | --- |
| 2026-10-14 | ssh | | y | not yet verified | requires Ollama 0.32.5 image instance; breaks on M5 sleep |
