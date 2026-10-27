if [ "${COMFYUI_SHELL:-}" != "1" ]; then
  echo "'comfyui' must be run inside the dev shell ('nix develop' in the comfyui repo)" >&2
  exit 1
fi

exec comfy-ui \
  --base-directory "${COMFYUI_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/comfyui}" \
  --listen "${COMFYUI_LISTEN:-127.0.0.1}" \
  --port "${COMFYUI_PORT:-8188}" \
  "$@"
