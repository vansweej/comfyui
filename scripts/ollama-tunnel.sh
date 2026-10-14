STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/comfyui"
mkdir -p "$STATE_DIR"

LOCAL_PORT="${OLLAMA_TUNNEL_LOCAL_PORT:-11435}"
TUNNEL_USER="${OLLAMA_TUNNEL_USER:-janvansweevelt}"
CONTROL_PATH="$STATE_DIR/ollama-tunnel.sock"
TARGET_FILE="$STATE_DIR/ollama-tunnel.target"
PID_FILE="$STATE_DIR/ollama-tunnel-direct.pid"

usage() {
  echo "usage: ollama-tunnel {start [--direct] [host]|stop|status|check}" >&2
}

wait_for_ollama() {
  local retries=5

  while [ "$retries" -gt 0 ]; do
    if curl -fsS "http://127.0.0.1:${LOCAL_PORT}/api/version" >/dev/null; then
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

command="${1:-}"
if [ "$#" -gt 0 ]; then
  shift
fi

mode="${OLLAMA_TUNNEL_MODE:-ssh}"
host=""
for argument in "$@"; do
  if [ "$argument" = "--direct" ]; then
    mode="direct"
  elif [ -z "$host" ]; then
    host="$argument"
  else
    usage
    exit 2
  fi
done

case "$command" in
  start)
    HOST="${host:-${M5_HOST:-}}"
    if [ -z "$HOST" ]; then
      echo "set M5_HOST or pass host" >&2
      exit 1
    fi

    if [ "$mode" = "direct" ]; then
      stop_direct_tunnel
      socat "TCP-LISTEN:${LOCAL_PORT},bind=127.0.0.1,reuseaddr,fork" "TCP:${HOST}:11434" &
      echo "$!" > "$PID_FILE"
    else
      ssh -f -N \
        -o ExitOnForwardFailure=yes \
        -o ServerAliveInterval=30 \
        -o ControlMaster=auto \
        -o ControlPersist=yes \
        -o "ControlPath=$CONTROL_PATH" \
        -L "127.0.0.1:${LOCAL_PORT}:127.0.0.1:11434" \
        "${TUNNEL_USER}@${HOST}"
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
    if curl -fsS "http://127.0.0.1:${LOCAL_PORT}/api/tags" | jq -e \
      '[.models[].name | sub(":[^:/]*$"; "")] | index("x/z-image-turbo") != null and index("x/flux2-klein") != null' \
      >/dev/null; then
      echo "Ollama tunnel has both required image models"
    else
      echo "Ollama tunnel is unavailable or missing required image models" >&2
      exit 1
    fi
    ;;
  *)
    usage
    exit 2
    ;;
esac
