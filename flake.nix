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
    in
    {
      packages.${system} = { };
      checks.${system} = { };
      devShells.${system} = { };
    };
}
