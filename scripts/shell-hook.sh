# shellcheck shell=bash
# Sourced by the flake devShell shellHook. Do not run standalone.

COMFYUI_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
export COMFYUI_ROOT
export COMFYUI_SHELL=1
export COMFYUI_DATA_DIR="${COMFYUI_DATA_DIR:-$COMFYUI_ROOT/data}"
export COMFY_USER_DIR="$COMFYUI_DATA_DIR"

nvidia_lib_dir="$COMFYUI_ROOT/.nvidia-libs"
mkdir -p "$nvidia_lib_dir"

for library in \
  libcuda.so.1 \
  libnvidia-ptxjitcompiler.so.1 \
  libnvidia-nvvm.so.4 \
  libnvidia-ml.so.1; do
  host_library="/usr/lib/x86_64-linux-gnu/$library"
  if [ -f "$host_library" ]; then
    ln -sf "$host_library" "$nvidia_lib_dir/$library"
  fi
done

for host_library in /usr/lib/x86_64-linux-gnu/libnvidia-gpucomp.so.*; do
  if [ -e "$host_library" ]; then
    ln -sf "$host_library" "$nvidia_lib_dir/$(basename "$host_library")"
  fi
done

if [ ! -e "$nvidia_lib_dir/libcuda.so.1" ]; then
  echo "GPU will not work. Run 'comfyui-check --host'" >&2
fi

export LD_LIBRARY_PATH="$nvidia_lib_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
mkdir -p "$COMFYUI_DATA_DIR"/{models,output,input,user,custom_nodes}

if [ -d "$COMFYUI_ROOT/custom_nodes/ollama_imagegen" ]; then
  ln -sfn \
    "$COMFYUI_ROOT/custom_nodes/ollama_imagegen" \
    "$COMFYUI_DATA_DIR/custom_nodes/ollama_imagegen"
fi

export OLLAMA_IMAGEGEN_URL="${OLLAMA_IMAGEGEN_URL:-http://127.0.0.1:${OLLAMA_TUNNEL_LOCAL_PORT:-11435}}"

cat <<'EOF'
ComfyUI development shell
  comfyui
  comfyui-check (--host --server --tunnel)
  comfyui-smoke
  ollama-tunnel (start|stop|status|check)
Set M5_HOST=<ip> before: ollama-tunnel start
EOF
