# Host prerequisites

The ComfyUI environment runs on Pop!_OS and depends on host NVIDIA driver
libraries. Nix does not install or manage the driver.

## NVIDIA driver

Install a current NVIDIA driver using apt. Package names vary between Pop!_OS
releases; common examples include `nvidia-driver-580`, `libnvidia-compute-580`,
and Pop!_OS-specific packages. Verify the driver with:

```bash
nvidia-smi
```

The project requires driver major version **580 or later** for CUDA 13 and a
Turing-or-newer GPU.

On systems with `system76-power`, select a graphics mode other than
`integrated`, then reboot. For example:

```bash
sudo system76-power graphics nvidia
```

`hybrid` also works. Check the environment without changing it:

```bash
comfyui-check --host
```

## Optional binary caches

The first `nix develop` can download roughly 2 GiB and may build dependencies
locally. The following optional settings speed it up. They require root and are
currently not configured by this repository:

```text
extra-substituters = https://comfyui.cachix.org https://nix-community.cachix.org https://cache.nixos-cuda.org
extra-trusted-public-keys = comfyui.cachix.org-1:33mf9VzoIjzVbp0zwj+fT51HG0y31ZTK3nzYZAX0rec= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs= cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=
```

With Determinate Nix, first identify the daemon unit before restarting it:

```bash
systemctl list-units | grep -i nix
```

Then add the settings to `/etc/nix/nix.custom.conf` and restart the applicable
daemon unit.
