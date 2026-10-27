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

if [ "$(uname)" = "Darwin" ]; then
  echo "SKIP: host-GPU precheck is not applicable on darwin; MPS is checked via the running server"
else
  if ! comfyui-check --host; then
    echo "SKIP: host GPU prerequisites not met (see output above)"
    if [ "$strict" = true ]; then
      exit 1
    fi
    exit 0
  fi
fi

PORT="${COMFYUI_SMOKE_PORT:-18188}"
if curl -fs "http://127.0.0.1:${PORT}/system_stats" >/dev/null; then
  echo "a service already responds on smoke-test port ${PORT}" >&2
  exit 1
fi

data_dir="$(mktemp -d)"
comfy_pid=""

cleanup() {
  if [ -n "$comfy_pid" ]; then
    if [ "$(uname)" = "Darwin" ]; then
      # The wrapper execs `caffeinate -i comfy-ui`, so caffeinate runs comfy-ui
      # as its child; pkill -P reaps that child, then we kill caffeinate itself.
      pkill -P "$comfy_pid" 2>/dev/null || true
      kill "$comfy_pid" 2>/dev/null || true
    else
      kill -- "-$comfy_pid" 2>/dev/null || true
    fi
  fi
  rm -rf "$data_dir"
}
trap cleanup EXIT INT TERM

if [ "$(uname)" = "Darwin" ]; then
  env COMFYUI_DATA_DIR="$data_dir" COMFYUI_PORT="$PORT" comfyui >"$data_dir/comfyui.log" 2>&1 &
  comfy_pid="$!"
else
  setsid env COMFYUI_DATA_DIR="$data_dir" COMFYUI_PORT="$PORT" comfyui >"$data_dir/comfyui.log" 2>&1 &
  comfy_pid="$!"
fi

timeout="${COMFYUI_SMOKE_TIMEOUT:-600}"
deadline=$((SECONDS + timeout))
while [ "$SECONDS" -lt "$deadline" ]; do
  if curl -fs "http://127.0.0.1:${PORT}/system_stats" >"$data_dir/system_stats.json"; then
    break
  fi
  sleep 3
done

if [ ! -s "$data_dir/system_stats.json" ]; then
  echo "ComfyUI did not start within ${timeout} seconds" >&2
  tail -n 50 "$data_dir/comfyui.log" >&2 || true
  exit 1
fi

expected_device="cuda"
if [ "$(uname)" = "Darwin" ]; then
  expected_device="mps"
fi

if ! device_name="$(jq -er --arg device "$expected_device" \
  '.devices[] | select(.type == $device) | .name // $device' "$data_dir/system_stats.json" | head -n 1)"; then
  echo "ComfyUI started but reported no $expected_device device" >&2
  exit 1
fi

echo "$expected_device device: $device_name"
echo "smoke: PASS"
