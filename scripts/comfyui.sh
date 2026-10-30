if [ "${COMFYUI_SHELL:-}" != "1" ]; then
  echo "'comfyui' must be run inside the dev shell ('nix develop' in the comfyui repo)" >&2
  exit 1
fi

if [ "$(uname)" = "Darwin" ]; then
  listen="${COMFYUI_LISTEN:-127.0.0.1}"
  if [ "$listen" != "127.0.0.1" ]; then
    echo "comfyui: refusing to listen on $listen — only 127.0.0.1 is allowed on darwin" >&2
    exit 1
  fi
  export COMFY_SKIP_BUNDLED_NODES=1
  export PYTORCH_ENABLE_MPS_FALLBACK=1
  export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0
  export FORCE_VAE_CPU=1
  exec /usr/bin/caffeinate -i comfy-ui \
    --base-directory "${COMFYUI_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/comfyui}" \
    --listen "$listen" \
    --port "${COMFYUI_PORT:-8188}" \
    --cpu-vae \
    --disable-smart-memory \
    --reserve-vram 4 \
    --force-fp16 \
    "$@"
fi

exec comfy-ui \
  --base-directory "${COMFYUI_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/comfyui}" \
  --listen "${COMFYUI_LISTEN:-127.0.0.1}" \
  --port "${COMFYUI_PORT:-8188}" \
  "$@"
