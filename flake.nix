{
  description = "ComfyUI Nix dev-shell flake for oryp6 with M5 Ollama custom node";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Deliberately NO inputs.nixpkgs.follows — comfyui-nix pins its own nixpkgs and prebuilt PyTorch CUDA wheels; overriding it would break the wheels.
    comfyui-nix.url = "github:utensils/comfyui-nix";
  };

  outputs = { self, nixpkgs, comfyui-nix }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-darwin" ];
      outputsForSystem = system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          # x86_64-linux: CUDA wheels from upstream comfyui-nix (linux drvPath parity required).
          # aarch64-darwin: local expression (not comfyui-nix.packages.aarch64-darwin.default) to
          # carry the test-only valkey override and keep the store path identical to the verified build.
          comfyPkg =
            if system == "x86_64-linux" then
              comfyui-nix.packages.${system}.cuda
            else
              import ./nix/comfyui-darwin.nix { inherit comfyui-nix; };
          # openssh_gssapi on linux, plain openssh on darwin (no gssapi support needed/available there).
          sshPkg = if pkgs.stdenv.hostPlatform.isLinux then pkgs.openssh_gssapi else pkgs.openssh;
          mkScript = name: runtimeInputs: pkgs.writeShellApplication {
            inherit name runtimeInputs;
            text = builtins.readFile (./scripts + "/${name}.sh");
          };
          # No comfyPkg in runtimeInputs — resolves comfy-ui from the dev-shell PATH (ComfyUI only inside the dev shell); errors if comfy-ui is not on PATH.
          comfyui-wrapper = pkgs.writeShellApplication {
            name = "comfyui";
            runtimeInputs = [ ];
            text = builtins.readFile ./scripts/comfyui.sh;
          };
          comfyui-check = mkScript "comfyui-check" (with pkgs; [ curl jq coreutils ]);
          comfyui-smoke = mkScript "comfyui-smoke" (with pkgs; [ curl jq coreutils ]);
          ollama-tunnel = mkScript "ollama-tunnel" (with pkgs; [ sshPkg curl jq socat coreutils ]);
          comfyui-migrate-data = mkScript "comfyui-migrate-data" (with pkgs; [ coreutils findutils ]);
          pythonTest = pkgs.python3.withPackages (ps: [ ps.pytest ps.numpy ps.pillow ]);
        in
        {
          packages =
            {
              inherit comfyui-wrapper comfyui-check comfyui-smoke ollama-tunnel comfyui-migrate-data;
              default = comfyui-check;
            }
            # Evaluable (but not a check) darwin comfy-ui attribute, so the store-path assertion
            # can run eval-only without forcing a build. Deliberately not added on x86_64-linux
            # (that would force cross-eval of the unfree CUDA package for no benefit).
            // nixpkgs.lib.optionalAttrs (system == "aarch64-darwin") {
              comfy-ui = comfyPkg;
            };
          # Only the light script packages on both systems — none reference comfyPkg — so
          # 'nix flake check' stays light and does not realise the darwin/CUDA ComfyUI package.
          checks = {
            inherit comfyui-wrapper comfyui-check comfyui-smoke ollama-tunnel comfyui-migrate-data;
          };
          devShells = {
            default = pkgs.mkShell {
              name = "comfyui";
              packages = [ comfyui-wrapper comfyui-check comfyui-smoke ollama-tunnel comfyui-migrate-data comfyPkg ] ++ (with pkgs; [
                curl
                jq
                socat
              ]) ++ [ sshPkg ] ++ (with pkgs; [
                python3
              ]);
              # Bash lives in real .sh files so there is no Nix ''${} escaping.
              shellHook = "source ${./scripts/shell-hook.sh}";
            };
            test = pkgs.mkShell {
              name = "comfyui-test";
              packages = [ pythonTest ];
            };
          };
        };
      perSystem = forAllSystems outputsForSystem;
    in
    {
      packages = nixpkgs.lib.mapAttrs (_: v: v.packages) perSystem;
      checks = nixpkgs.lib.mapAttrs (_: v: v.checks) perSystem;
      devShells = nixpkgs.lib.mapAttrs (_: v: v.devShells) perSystem;
    };
}
