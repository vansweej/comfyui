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

3. On M5, pull the required image models while Ollama remains bound to
   `127.0.0.1:11434`:

   ```bash
   ollama pull x/z-image-turbo
   ollama pull x/flux2-klein
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

| Date | Mode | Latency | z-image-turbo | flux2-klein | Notes |
| --- | --- | --- | --- | --- | --- |
| | | | | | |
