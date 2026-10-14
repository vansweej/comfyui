STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/comfyui"
mkdir -p "$STATE_DIR"

LOCAL_PORT="${OLLAMA_TUNNEL_LOCAL_PORT:-11435}"
# Default 11436 is the M5 image-generation instance (standalone Ollama 0.32.5,
# see docs/m5-imagegen-instance.md); the daily Ollama.app stays on 11434.
REMOTE_PORT="${OLLAMA_TUNNEL_REMOTE_PORT:-11436}"
TUNNEL_USER="${OLLAMA_TUNNEL_USER:-janvansweevelt}"
CONTROL_PATH="$STATE_DIR/ollama-tunnel.sock"
TARGET_FILE="$STATE_DIR/ollama-tunnel.target"
PID_FILE="$STATE_DIR/ollama-tunnel-direct.pid"

usage() {
  echo "usage: ollama-tunnel {start [--direct] [host]|stop|status|check [--generate]}" >&2
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
      stop_direct_tunnel
      socat "TCP-LISTEN:${LOCAL_PORT},bind=127.0.0.1,reuseaddr,fork" "TCP:${HOST}:${REMOTE_PORT}" &
      echo "$!" > "$PID_FILE"
    else
      # ollama-tunnel stop (ssh -O exit) stops the master, closes the mux-session
      # channel, exits the remote sshd process, and lets caffeinate -w exit. This
      # teardown is not verifiable offline; see the Phase 3 manual check. Caffeinate
      # cannot prevent lid-closed sleep and may be overridden by MDM. Opt out with
      # OLLAMA_TUNNEL_KEEP_AWAKE=0.
      ssh -f -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o ControlPersist=yes -o "ControlPath=$CONTROL_PATH" -L "127.0.0.1:${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT}" "${TUNNEL_USER}@${HOST}"
      if [ "$KEEP_AWAKE" != "0" ]; then
        # shellcheck disable=SC2016  # single quotes are deliberate: $PPID must expand on M5, not locally
        ssh -f -o "ControlPath=$CONTROL_PATH" "${TUNNEL_USER}@${HOST}" 'caffeinate -i -w $PPID'
      fi
      printf '%s\n' "$HOST" > "$TARGET_FILE"
    fi

    wait_for_ollama
    echo "Ollama tunnel is ready on 127.0.0.1:${LOCAL_PORT}"
    ;;
  stop)
    stop_direct_tunnel
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
        exit 0
      fi
    fi
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
      echo "image route probe failed: Ollama not reachable through the tunnel (M5 asleep? run ollama-tunnel start)" >&2
      exit 1
    fi

    body="$(cat "$tmp")"
    if [ "$status" = 404 ] && [[ "$body" == *"page not found"* ]]; then
      echo "image route missing: the tunnel target runs Ollama $version; it must be the M5 image instance on Ollama 0.32.5 (OLLAMA_TUNNEL_REMOTE_PORT, default 11436; see docs/m5-imagegen-instance.md)" >&2
      exit 1
    fi

    echo "Ollama tunnel has both required image models and the image route (Ollama $version)"

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
