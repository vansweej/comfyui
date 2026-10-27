# shellcheck shell=bash
# Sourced by the flake devShell shellHook. Do not run standalone.

COMFYUI_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
export COMFYUI_ROOT
export COMFYUI_SHELL=1
export COMFYUI_DATA_DIR="${COMFYUI_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/comfyui}"
export COMFY_USER_DIR="$COMFYUI_DATA_DIR"
COMFYUI_STATE_DIR="${COMFYUI_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/comfyui}"
export COMFYUI_STATE_DIR

# Legacy-data notice: a non-empty repo-local data/ means the user has not yet
# migrated to the XDG data dir. Fires before the mkdir/symlink block below so
# the notice is accurate regardless of how much has already been migrated.
if [ -n "$(find "$COMFYUI_ROOT/data" -type f -print -quit 2>/dev/null)" ]; then
  echo "comfyui: found legacy data under $COMFYUI_ROOT/data — run 'comfyui-migrate-data' to move it into $COMFYUI_DATA_DIR" >&2
fi

if [ "$(uname)" = "Linux" ]; then
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
else
  echo "Darwin: using Metal Performance Shaders (MPS) — no NVIDIA setup needed."
fi

mkdir -p "$COMFYUI_DATA_DIR"/{models,output,input,user,custom_nodes,.cache}

if [ -d "$COMFYUI_ROOT/custom_nodes/ollama_imagegen" ]; then
  ln -sfn \
    "$COMFYUI_ROOT/custom_nodes/ollama_imagegen" \
    "$COMFYUI_DATA_DIR/custom_nodes/ollama_imagegen"
fi

# These only-if-unset exports affect tools run in the dev shell outside
# ComfyUI. The upstream comfy-ui launcher already exports its own
# HF_HOME/TORCH_HOME/TORCHINDUCTOR_CACHE_DIR/FACEXLIB_MODELPATH under
# $BASE_DIR/.cache, uses a mutable venv at $BASE_DIR/.venv, and creates
# models/* itself (the spike confirmed zero writes outside ~/.local); the
# only-if-unset guard keeps these exports from overriding ComfyUI's own.
export HF_HOME="${HF_HOME:-$COMFYUI_DATA_DIR/.cache/huggingface}"
export TORCH_HOME="${TORCH_HOME:-$COMFYUI_DATA_DIR/.cache/torch}"

export OLLAMA_IMAGEGEN_URL="${OLLAMA_IMAGEGEN_URL:-http://127.0.0.1:${OLLAMA_TUNNEL_LOCAL_PORT:-11435}}"

cat <<'EOF'
ComfyUI development shell
  comfyui
  comfyui-check (--host --server --tunnel)
  comfyui-smoke
  comfyui-migrate-data
  m5-tunnel (start|stop|status|check)
  ollama-tunnel: deprecated alias for m5-tunnel
Set M5_HOST=<ip> before: m5-tunnel start
EOF
