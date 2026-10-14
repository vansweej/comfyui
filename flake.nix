{
  description = "ComfyUI Nix dev-shell flake for oryp6 with M5 Ollama custom node";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Deliberately NO inputs.nixpkgs.follows — comfyui-nix pins its own nixpkgs and prebuilt PyTorch CUDA wheels; overriding it would break the wheels.
    comfyui-nix.url = "github:utensils/comfyui-nix";
  };

  outputs = { self, nixpkgs, comfyui-nix }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      comfyPkg = comfyui-nix.packages.${system}.cuda;
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
      ollama-tunnel = mkScript "ollama-tunnel" (with pkgs; [ openssh curl jq socat coreutils ]);
      pythonTest = pkgs.python3.withPackages (ps: [ ps.pytest ps.numpy ps.pillow ]);
    in
    {
      packages.${system} = {
        inherit comfyui-wrapper comfyui-check comfyui-smoke ollama-tunnel;
        default = comfyui-check;
      };
      # Only the light script packages — none reference comfyPkg — so 'nix flake check' stays light and does not realise the ~2GB CUDA package.
      checks.${system} = {
        inherit comfyui-wrapper comfyui-check comfyui-smoke ollama-tunnel;
      };
      devShells.${system} = {
        default = pkgs.mkShell {
          name = "comfyui";
          packages = [ comfyui-wrapper comfyui-check comfyui-smoke ollama-tunnel comfyPkg ] ++ (with pkgs; [
            curl
            jq
            socat
            openssh
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
}
