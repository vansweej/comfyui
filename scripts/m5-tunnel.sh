STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/comfyui"
mkdir -p "$STATE_DIR"

LOCAL_PORT="${OLLAMA_TUNNEL_LOCAL_PORT:-11435}"
# Default 11436 is the M5 image-generation instance (standalone Ollama 0.32.5,
# see docs/m5-imagegen-instance.md); the daily Ollama.app stays on 11434.
REMOTE_PORT="${OLLAMA_TUNNEL_REMOTE_PORT:-11436}"
TUNNEL_USER="${OLLAMA_TUNNEL_USER:-janvansweevelt}"
CONTROL_PATH="$STATE_DIR/m5-tunnel.sock"
TARGET_FILE="$STATE_DIR/m5-tunnel.target"
PID_FILE="$STATE_DIR/m5-tunnel-direct.pid"

# Legacy state files (pre-rename from ollama-tunnel). stop/status clean these
# up too, in addition to the new m5-tunnel.* files above.
LEGACY_CONTROL_PATH="$STATE_DIR/ollama-tunnel.sock"
LEGACY_TARGET_FILE="$STATE_DIR/ollama-tunnel.target"
LEGACY_PID_FILE="$STATE_DIR/ollama-tunnel-direct.pid"

COMFYUI_LOCAL_PORT="${COMFYUI_TUNNEL_LOCAL_PORT:-8189}"
COMFYUI_REMOTE_PORT="${COMFYUI_TUNNEL_REMOTE_PORT:-8188}"

usage() {
  echo "usage: m5-tunnel {start [--direct] [host]|stop|status|check [--generate]}" >&2
}

wait_for_ollama() {
  local retries=5

  while [ "$retries" -gt 0 ]; do
    if curl -fsS --max-time 3 "http://127.0.0.1:${LOCAL_PORT}/api/version" >/dev/null; then
      return 0
    fi
    retries=$((retries - 1))
    sleep 1
  done

  echo "Ollama did not respond through the tunnel on port ${LOCAL_PORT}" >&2
  return 1
}

stop_direct_tunnel() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid="$(cat "$PID_FILE")"
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid"
    fi
    rm -f "$PID_FILE"
  fi
}

stop_legacy_tunnel() {
  if [ -f "$LEGACY_PID_FILE" ]; then
    local legacy_pid
    legacy_pid="$(cat "$LEGACY_PID_FILE")"
    if kill -0 "$legacy_pid" 2>/dev/null; then
      kill "$legacy_pid"
    fi
    rm -f "$LEGACY_PID_FILE"
  fi
  if [ -f "$LEGACY_TARGET_FILE" ] && [ -S "$LEGACY_CONTROL_PATH" ]; then
    local legacy_host
    legacy_host="$(cat "$LEGACY_TARGET_FILE")"
    ssh -O exit -o "ControlPath=$LEGACY_CONTROL_PATH" "${TUNNEL_USER}@${legacy_host}" 2>/dev/null || true
  elif [ -S "$LEGACY_CONTROL_PATH" ]; then
    ssh -O exit -o "ControlPath=$LEGACY_CONTROL_PATH" "${TUNNEL_USER}@localhost" 2>/dev/null || true
  fi
  rm -f "$LEGACY_TARGET_FILE" "$LEGACY_CONTROL_PATH"
}

# Returns 0 (busy) when something already answers on 127.0.0.1:$1, 1 (free)
# when nothing is listening (curl exit 7). set -e-safe: callers must guard.
port_in_use() {
  local port="$1"
  local rc=0
  curl -s -o /dev/null --max-time 1 "http://127.0.0.1:${port}/" || rc="$?"
  [ "$rc" -ne 7 ]
}

if [ "$#" -eq 0 ]; then
  usage
  exit 2
fi

command=$1
shift

mode="${OLLAMA_TUNNEL_MODE:-ssh}"
generate=0
host=""
for argument in "$@"; do
  case "$argument" in
    --direct)
      if [ "$command" = "start" ]; then
        mode="direct"
      else
        usage
        exit 2
      fi
      ;;
    --generate)
      if [ "$command" = "check" ]; then
        generate=1
      else
        usage
        exit 2
      fi
      ;;
    -*)
      usage
      exit 2
      ;;
    *)
      if [ "$command" = "start" ] && [ -z "$host" ]; then
        host="$argument"
      else
        usage
        exit 2
      fi
      ;;
  esac
done

case "$command" in
  start)
    HOST="${host:-${M5_HOST:-}}"
    if [ -z "$HOST" ]; then
      echo "set M5_HOST or pass host" >&2
      exit 1
    fi

    KEEP_AWAKE="${OLLAMA_TUNNEL_KEEP_AWAKE:-1}"
    # tunnel_healthy keeps EXACTLY the pre-Phase-4 semantics (ssh master -O
    # check + target-host match + Ollama /api/version). It MUST NOT probe
    # ComfyUI, otherwise start would tear down a healthy tunnel (and the
    # keep-awake session) whenever ComfyUI is stopped on the M5. ComfyUI
    # reachability is reported only by check/status, non-fatal.
    tunnel_healthy() {
      [ -f "$TARGET_FILE" ] && [ "$(cat "$TARGET_FILE")" = "$HOST" ] && \
        [ -S "$CONTROL_PATH" ] && \
        ssh -O check -o "ControlPath=$CONTROL_PATH" "${TUNNEL_USER}@${HOST}" >/dev/null 2>&1 && \
        curl -fsS --max-time 3 "http://127.0.0.1:${LOCAL_PORT}/api/version" >/dev/null
    }

    if tunnel_healthy; then
      echo "Ollama tunnel already running on 127.0.0.1:${LOCAL_PORT}"
      exit 0
    fi

    if [ -S "$CONTROL_PATH" ]; then
      ssh -O exit -o "ControlPath=$CONTROL_PATH" "${TUNNEL_USER}@${HOST}" 2>/dev/null || true
    fi
    rm -f "$CONTROL_PATH" "$TARGET_FILE"

    if [ "$mode" = "direct" ]; then
      echo "m5-tunnel: --direct forwards Ollama only; ComfyUI requires ssh mode" >&2
      stop_direct_tunnel
      socat "TCP-LISTEN:${LOCAL_PORT},bind=127.0.0.1,reuseaddr,fork" "TCP:${HOST}:${REMOTE_PORT}" &
      echo "$!" > "$PID_FILE"
    else
      # ComfyUI port pre-flight: ExitOnForwardFailure=yes makes ssh exit if
      # any -L bind fails, so a busy local ComfyUI port must be detected and
      # omitted from the ssh invocation before launching it. Run after the
      # tunnel_healthy short-circuit and after tearing down any stale
      # m5-tunnel master above, so a port held by our own stale master is
      # released first. No equivalent pre-flight for the Ollama port
      # (existing behaviour unchanged).
      comfyui_forward=()
      if port_in_use "$COMFYUI_LOCAL_PORT"; then
        echo "warning: local port ${COMFYUI_LOCAL_PORT} in use — starting Ollama-only forward" >&2
      else
        comfyui_forward=(-L "127.0.0.1:${COMFYUI_LOCAL_PORT}:127.0.0.1:${COMFYUI_REMOTE_PORT}")
      fi

      # m5-tunnel stop (ssh -O exit) stops the master, closes the mux-session
      # channel, exits the remote sshd process, and lets caffeinate -w exit. This
      # teardown is not verifiable offline; see the Phase 3 manual check. Caffeinate
      # cannot prevent lid-closed sleep and may be overridden by MDM. Opt out with
      # OLLAMA_TUNNEL_KEEP_AWAKE=0.
      ssh -f -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o ControlPersist=yes -o "ControlPath=$CONTROL_PATH" -L "127.0.0.1:${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT}" "${comfyui_forward[@]}" "${TUNNEL_USER}@${HOST}"
      printf '%s\n' "$HOST" > "$TARGET_FILE"
      if [ "$KEEP_AWAKE" != "0" ]; then
        # shellcheck disable=SC2016  # single quotes are deliberate: $PPID must expand on M5, not locally
        if ! ssh -f -o "ControlPath=$CONTROL_PATH" "${TUNNEL_USER}@${HOST}" 'caffeinate -i -w $PPID'; then
          echo "warning: could not start keep-awake (caffeinate) on M5; tunnel is up but M5 may idle-sleep" >&2
        fi
      fi
    fi

    wait_for_ollama
    echo "Ollama tunnel is ready on 127.0.0.1:${LOCAL_PORT}"
    ;;
  stop)
    stop_direct_tunnel
    stop_legacy_tunnel
    if [ -f "$TARGET_FILE" ] && [ -S "$CONTROL_PATH" ]; then
      HOST="$(cat "$TARGET_FILE")"
      ssh -O exit -o "ControlPath=$CONTROL_PATH" "${TUNNEL_USER}@${HOST}" || true
    fi
    rm -f "$TARGET_FILE" "$CONTROL_PATH"
    echo "Ollama tunnel stopped"
    ;;
  status)
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
      echo "Ollama direct tunnel is running on 127.0.0.1:${LOCAL_PORT}"
      exit 0
    fi
    if [ -f "$TARGET_FILE" ] && [ -S "$CONTROL_PATH" ]; then
      HOST="$(cat "$TARGET_FILE")"
      if ssh -O check -o "ControlPath=$CONTROL_PATH" "${TUNNEL_USER}@${HOST}"; then
        echo "Ollama SSH tunnel is running on 127.0.0.1:${LOCAL_PORT}"
        if port_in_use "$COMFYUI_LOCAL_PORT"; then
          echo "ComfyUI forward appears reachable on 127.0.0.1:${COMFYUI_LOCAL_PORT}"
        else
          echo "ComfyUI not running on M5 (or forward not established)" >&2
        fi
        exit 0
      fi
    fi
    stop_legacy_tunnel
    echo "Ollama tunnel is not running" >&2
    exit 1
    ;;
  check)
    tmp=""
    tmp="$(mktemp)"
    trap 'rm -f "${tmp:-}"' EXIT
    if curl -fsS "http://127.0.0.1:${LOCAL_PORT}/api/tags" | jq -e \
      '[.models[].name | sub(":[^:/]*$"; "")] | index("x/z-image-turbo") != null and index("x/flux2-klein") != null' \
      >/dev/null; then
      :
    else
      echo "Ollama tunnel is unavailable or missing required image models" >&2
      exit 1
    fi

    version="$(curl -fsS --max-time 3 "http://127.0.0.1:${LOCAL_PORT}/api/version" | jq -r '.version' || true)"
    version="${version:-unknown}"
    status="$(curl -sS -o "$tmp" -w '%{http_code}' --max-time 10 -X POST -H 'Content-Type: application/json' -d '{}' "http://127.0.0.1:${LOCAL_PORT}/v1/images/generations" || true)"
    if [ -z "$status" ] || [ "$status" = "000" ]; then
      echo "image route probe failed: Ollama not reachable through the tunnel (M5 asleep? run m5-tunnel start)" >&2
      exit 1
    fi

    body="$(cat "$tmp")"
    if [ "$status" = 404 ] && [[ "$body" == *"page not found"* ]]; then
      echo "image route missing: the tunnel target runs Ollama $version; it must be the M5 image instance on Ollama 0.32.5 (OLLAMA_TUNNEL_REMOTE_PORT, default 11436; see docs/m5-imagegen-instance.md)" >&2
      exit 1
    fi

    echo "Ollama tunnel has both required image models and the image route (Ollama $version)"

    # ComfyUI reachability is reported here, non-fatal (tunnel_healthy never
    # probes ComfyUI; this is the only place it is checked besides status).
    if port_in_use "$COMFYUI_LOCAL_PORT"; then
      echo "ComfyUI forward appears reachable on 127.0.0.1:${COMFYUI_LOCAL_PORT}"
    else
      echo "ComfyUI not running on M5 (or forward not established)" >&2
    fi

    # User-invoked only: this performs a real image generation for each model.
    if [ "$generate" = "1" ]; then
      for model in x/z-image-turbo x/flux2-klein; do
        response="$(curl -sS --max-time 600 -X POST -H 'Content-Type: application/json' -d "{\"model\":\"${model}\",\"prompt\":\"test\",\"size\":\"256x256\",\"response_format\":\"b64_json\"}" "http://127.0.0.1:${LOCAL_PORT}/v1/images/generations" || true)"
        if ! printf '%s' "$response" | jq -e '.data[0].b64_json | type == "string" and length > 0' >/dev/null; then
          echo "generation test failed for ${model}" >&2
          exit 1
        fi
        echo "generation test passed for ${model}"
      done
    fi
    ;;
  *)
    usage
    exit 2
    ;;
esac
