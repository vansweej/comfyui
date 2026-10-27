# Darwin (aarch64-darwin) ComfyUI package expression.
#
# 1. Upstream comfyui-nix 58f91b0 ships `python3.12-valkey-6.1.1`, whose test
#    suite has 13 tests that hard-code `localhost:6379`/sentinel addresses.
#    Those tests fail in the darwin build sandbox (no network, no local
#    redis/valkey server); upstream's own darwin `preCheck` sets a
#    `--valkey-url` but does not cover these tests, and upstream CI never
#    builds darwin, so this has never been caught upstream.
# 2. The override below is test-only (`doCheck = false`) and is applied via
#    a `pythonPackagesExtensions` overlay at nixpkgs-import time. It composes
#    *underneath* upstream's own python overrides because `packages.nix`
#    builds its Python environment via
#    `pkgs.python312.override { packageOverrides = pythonOverrides; }`, and
#    `overridePythonAttrs` stacks: our `doCheck = false` survives whatever
#    upstream's `pythonOverrides` does afterwards.
# 3. nixpkgs MUST be sourced from `comfyui-nix.inputs.nixpkgs` (upstream's own
#    locked nixpkgs) — NEVER this flake's top-level `nixpkgs` input. Mixing
#    the two would change every transitive store path and break
#    byte-equivalence with the verified spike build.
# 4. The `config` block (`allowUnfree` plus the `allowBrokenPredicate` for
#    `open-clip-torch`) and the `overlays` list must not be reordered or
#    extended without re-verifying the resulting `outPath` against
#    `~/.local/state/comfyui/gcroot-spike` — any reordering can perturb the
#    store path.
# 5. This expression must stay byte-equivalent to the verified spike build so
#    the resulting store path equals `~/.local/state/comfyui/gcroot-spike`
#    (no rebuild).
# 6. This override can be dropped entirely — switch `comfyPkg` back to
#    `comfyui-nix.packages.aarch64-darwin.default` — once upstream fixes
#    valkey on darwin.
{ comfyui-nix }:
let
  src = comfyui-nix.outPath;
  versions = import "${src}/nix/versions.nix";
  pkgs = import comfyui-nix.inputs.nixpkgs {
    system = "aarch64-darwin";
    config = {
      allowUnfree = true;
      allowBrokenPredicate = pkg: (pkg.pname or "") == "open-clip-torch";
    };
    overlays = [
      (final: prev: {
        pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
          (pyFinal: pyPrev: {
            valkey = pyPrev.valkey.overridePythonAttrs (_: {
              doCheck = false;
            });
          })
        ];
      })
    ];
  };
in
(import "${src}/nix/packages.nix" {
  inherit pkgs versions;
  lib = pkgs.lib;
  gpuSupport = "none";
  pythonOverrides = import "${src}/nix/python-overrides.nix" {
    inherit pkgs versions;
    gpuSupport = "none";
  };
}).default
