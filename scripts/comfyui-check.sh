fail=0
run_host=false
run_nix=false
run_server=false
run_tunnel=false

required() {
  echo "FAIL: $*" >&2
  fail=$((fail + 1))
}

warn() {
  echo "WARN: $*" >&2
}

if [ "$#" -eq 0 ]; then
  run_host=true
  run_nix=true
fi

for argument in "$@"; do
  case "$argument" in
    --host)
      run_host=true
      ;;
    --server)
      run_server=true
      run_nix=true
      ;;
    --tunnel)
      run_tunnel=true
      run_nix=true
      ;;
    *)
      echo "usage: comfyui-check [--host] [--server] [--tunnel]" >&2
      exit 2
      ;;
  esac
done

if [ "$run_host" = true ]; then
  if [ "$(uname)" = "Darwin" ]; then
    echo "== Host GPU (darwin, best-effort) =="
    if command -v sysctl >/dev/null 2>&1 && sysctl -n hw.optional.arm64 2>/dev/null | grep -q '^1$'; then
      echo "PASS: Apple Silicon detected; Metal Performance Shaders (MPS) should be available"
    else
      warn "could not confirm Apple Silicon; MPS availability is best-effort on darwin"
    fi
  else
    echo "== Host GPU =="

    if [ ! -f /proc/driver/nvidia/version ]; then
      required "NVIDIA driver is unavailable; install the Pop!_OS NVIDIA driver"
    fi

    if ! command -v nvidia-smi >/dev/null 2>&1; then
      required "nvidia-smi is unavailable"
    else
      gpu_info="$(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || true)"
      driver_version="$(printf '%s\n' "$gpu_info" | awk -F', ' 'NR == 1 { print $NF }')"
      driver_major="${driver_version%%.*}"
      if [ -z "$gpu_info" ] || ! [ "$driver_major" -ge 580 ] 2>/dev/null; then
        required "NVIDIA driver must be version 580 or newer"
      else
        echo "PASS: $gpu_info"
      fi
    fi

    if command -v dpkg-query >/dev/null 2>&1; then
      nvidia_packages="$(dpkg-query -W -f='${binary:Package}\n' '*nvidia*' 2>/dev/null || true)"
      if ! printf '%s\n' "$nvidia_packages" | grep -Eq 'system76-driver-nvidia|nvidia-driver-[0-9]+(-open)?|libnvidia-compute-[0-9]+'; then
        warn "no recognised NVIDIA driver package was found by dpkg-query"
      fi
    else
      warn "dpkg-query is unavailable; cannot report installed NVIDIA packages"
    fi

    if command -v system76-power >/dev/null 2>&1; then
      graphics_mode="$(system76-power graphics 2>&1 || true)"
      if [ "$graphics_mode" = "integrated" ]; then
        required "system76-power is integrated; run 'sudo system76-power graphics hybrid' (or nvidia) then reboot"
      else
        echo "PASS: system76-power graphics ${graphics_mode:-unknown}"
      fi
    else
      warn "system76-power is unavailable; skipping graphics-mode check"
    fi

    if [ ! -f /usr/lib/x86_64-linux-gnu/libcuda.so.1 ]; then
      required "host libcuda.so.1 is unavailable"
    fi
  fi
fi

if [ "$run_nix" = true ]; then
  echo "== Nix environment =="
  if [ "${COMFYUI_SHELL:-}" != "1" ]; then
    required "COMFYUI_SHELL must be 1; enter the project with nix develop"
  fi

  if [ -z "${COMFYUI_ROOT:-}" ]; then
    required "COMFYUI_ROOT must be set"
  else
    repo_root="${COMFYUI_ROOT:?}"
    if ! readlink -e "${repo_root:?}/.nvidia-libs/libcuda.so.1" >/dev/null; then
      required "${repo_root:?}/.nvidia-libs/libcuda.so.1 does not resolve"
    fi
    case ":${LD_LIBRARY_PATH:-}:" in
      *":${repo_root:?}/.nvidia-libs:"*) ;;
      *) required "LD_LIBRARY_PATH does not contain ${repo_root:?}/.nvidia-libs" ;;
    esac
  fi

  if ! command -v comfy-ui >/dev/null 2>&1; then
    required "comfy-ui is unavailable on PATH"
  fi
fi

if [ "$run_server" = true ]; then
  echo "== ComfyUI server =="
  expected_device="cuda"
  if [ "$(uname)" = "Darwin" ]; then
    expected_device="mps"
  fi
  if ! curl -fsS "http://${COMFYUI_LISTEN:-127.0.0.1}:${COMFYUI_PORT:-8188}/system_stats" | jq -e \
    --arg device "$expected_device" \
    '[.devices[].type] | index($device) != null' >/dev/null; then
    required "ComfyUI server is unavailable or reports no $expected_device device"
  fi
fi

if [ "$run_tunnel" = true ]; then
  echo "== Ollama tunnel =="
  if ! ollama-tunnel check; then
    required "Ollama tunnel check failed"
  fi
fi

if [ "$fail" -eq 0 ]; then
  echo "comfyui-check: PASS"
else
  echo "comfyui-check: FAIL" >&2
fi

exit "$fail"
