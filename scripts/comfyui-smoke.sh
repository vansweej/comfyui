strict=false

if [ "${1:-}" = "--strict" ]; then
  strict=true
  shift
fi

if [ "$#" -ne 0 ]; then
  echo "usage: comfyui-smoke [--strict]" >&2
  exit 2
fi

if [ "${COMFYUI_SHELL:-}" != "1" ]; then
  echo "comfyui-smoke must be run inside the dev shell ('nix develop')" >&2
  exit 1
fi

if ! comfyui-check --host; then
  echo "SKIP: host GPU prerequisites not met (see output above)"
  if [ "$strict" = true ]; then
    exit 1
  fi
  exit 0
fi

PORT="${COMFYUI_SMOKE_PORT:-18188}"
if curl -fsS "http://127.0.0.1:${PORT}/system_stats" >/dev/null; then
  echo "a service already responds on smoke-test port ${PORT}" >&2
  exit 1
fi

data_dir="$(mktemp -d)"
comfy_pid=""

cleanup() {
  if [ -n "$comfy_pid" ]; then
    kill -- "-$comfy_pid" 2>/dev/null || true
  fi
  rm -rf "$data_dir"
}
trap cleanup EXIT INT TERM

setsid env COMFYUI_DATA_DIR="$data_dir" COMFYUI_PORT="$PORT" comfyui >"$data_dir/comfyui.log" 2>&1 &
comfy_pid="$!"

timeout="${COMFYUI_SMOKE_TIMEOUT:-600}"
deadline=$((SECONDS + timeout))
while [ "$SECONDS" -lt "$deadline" ]; do
  if curl -fsS "http://127.0.0.1:${PORT}/system_stats" >"$data_dir/system_stats.json"; then
    break
  fi
  sleep 3
done

if [ ! -s "$data_dir/system_stats.json" ]; then
  echo "ComfyUI did not start within ${timeout} seconds" >&2
  tail -n 50 "$data_dir/comfyui.log" >&2 || true
  exit 1
fi

if ! cuda_name="$(jq -er '.devices[] | select(.type == "cuda") | .name // "CUDA device"' "$data_dir/system_stats.json" | head -n 1)"; then
  echo "ComfyUI started but reported no CUDA device" >&2
  exit 1
fi

echo "CUDA device: $cuda_name"
echo "smoke: PASS"
