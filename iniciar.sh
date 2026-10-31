#!/usr/bin/env bash
# Arranque portable: 3 servidores + balanceador FastAPI + UI estática
# No modifica balanceador.py ni servidores.py.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

STAGE=0
show_stage() {
  STAGE=$((STAGE + 1))
  local filled=$(( STAGE * 14 / 7 ))
  local bar
  printf -v bar '%*s' "$filled" ''
  bar="${bar// /#}"
  if [[ -t 1 ]]; then
    printf '\033[36m[%-14s] %s/7\033[0m %s\n' "$bar" "$STAGE" "$1"
  else
    printf '[%-14s] %s/7 %s\n' "$bar" "$STAGE" "$1"
  fi
}

show_wait() {
  [[ -t 1 ]] || return 0
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local locale="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
  if [[ "$locale" != *UTF-8* && "$locale" != *utf8* ]]; then
    frames=('|' '/' '-' '\')
  fi
  printf '\r\033[33m    Esperando %s %s   \033[0m' "$1" "${frames[$(( $2 % ${#frames[@]} ))]}"
}

clear_wait() {
  [[ -t 1 ]] && printf '\r\033[2K' || true
}

PIDS=()
RUNNING_TASK=""
RUNNING_LOG=""
cleanup() {
  clear_wait
  if [[ -n "$RUNNING_TASK" ]]; then
    kill "$RUNNING_TASK" 2>/dev/null || true
    wait "$RUNNING_TASK" 2>/dev/null || true
  fi
  [[ -z "$RUNNING_LOG" ]] || rm -f "$RUNNING_LOG"
  echo
  echo "[*] Deteniendo procesos..."
  for pid in "${PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
  sleep 0.25
  for pid in "${PIDS[@]:-}"; do
    kill -9 "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

run_with_spinner() {
  local label="$1" status=0 tick=0
  shift
  RUNNING_LOG="$(mktemp)"
  "$@" >"$RUNNING_LOG" 2>&1 &
  RUNNING_TASK=$!
  while kill -0 "$RUNNING_TASK" 2>/dev/null; do
    show_wait "$label" "$tick"
    tick=$((tick + 1))
    sleep 0.12
  done
  if wait "$RUNNING_TASK"; then status=0; else status=$?; fi
  RUNNING_TASK=""
  clear_wait
  cat "$RUNNING_LOG"
  rm -f "$RUNNING_LOG"
  RUNNING_LOG=""
  return "$status"
}

show_stage 'Comprobando Python y entorno'

PY="${ROOT}/venv/bin/python"

if [[ ! -x "$PY" ]]; then
  run_with_spinner 'Creando entorno virtual' python3 -m venv venv
else
  show_wait 'Entorno virtual disponible' 0
  clear_wait
fi

show_stage 'Instalando dependencias Python'
run_with_spinner 'Instalando dependencias' "$PY" -m pip install -r requirements.txt

port_busy() {
  # exit 0 si ocupado, 1 si libre
  "$PY" _puertos.py check "$1"
}

ensure_port_free() {
  local port="$1"
  local name="$2"
  if port_busy "$port"; then
    echo "[!] Puerto ${port} ocupado (${name}). Cierra el proceso que lo utiliza; no se cerrarán procesos ajenos." >&2
    exit 1
  fi
}

wait_port() {
  local port="$1"
  local name="$2"
  local i=0
  while (( i < 50 )); do
    if "$PY" - "$port" <<'PY'
import socket, sys
s = socket.socket()
s.settimeout(0.2)
try:
    s.connect(("127.0.0.1", int(sys.argv[1])))
except OSError:
    sys.exit(1)
finally:
    s.close()
PY
    then
      clear_wait
      echo "    ✓ ${name} listo en :${port}"
      return 0
    fi
    show_wait "$name" "$i"
    sleep 0.15
    ((i++)) || true
  done
  clear_wait
  echo "    ✗ Timeout esperando ${name} (:${port})" >&2
  return 1
}

# Puertos de la API son fijos en balanceador.py
show_stage 'Comprobando puertos de API'
ensure_port_free 8001 "Servidor 1"
ensure_port_free 8002 "Servidor 2"
ensure_port_free 8003 "Servidor 3"
ensure_port_free 8000 "Balanceador"

UI_PORT_PREF="${UI_PORT:-5500}"
if port_busy "$UI_PORT_PREF"; then
  echo "[*] Puerto UI ${UI_PORT_PREF} ocupado; buscando alternativa sin cerrar otros procesos."
fi

show_stage 'Iniciando tres servidores'
echo "[*] Iniciando Servidor 1 → :8001"
"$PY" servidores.py 8001 "Servidor 1" &
PIDS+=($!)

echo "[*] Iniciando Servidor 2 → :8002"
"$PY" servidores.py 8002 "Servidor 2" &
PIDS+=($!)

echo "[*] Iniciando Servidor 3 → :8003"
"$PY" servidores.py 8003 "Servidor 3" &
PIDS+=($!)

wait_port 8001 "Servidor 1"
wait_port 8002 "Servidor 2"
wait_port 8003 "Servidor 3"

show_stage 'Iniciando balanceador FastAPI'
"$PY" -m uvicorn balanceador:app --host 127.0.0.1 --port 8000 &
PIDS+=($!)
wait_port 8000 "Balanceador"

UI_LOG="$(mktemp)"
show_stage 'Iniciando panel web'
"$PY" servir_ui.py "$UI_PORT_PREF" --root "$ROOT" >"$UI_LOG" 2>&1 &
PIDS+=($!)
UI_PID="${PIDS[-1]}"

UI_PORT=""
for _ in $(seq 1 60); do
  if grep -q '^UI_PORT=' "$UI_LOG" 2>/dev/null; then
    UI_PORT="$(grep '^UI_PORT=' "$UI_LOG" | head -1 | cut -d= -f2 | tr -d '[:space:]')"
    break
  fi
  if ! kill -0 "$UI_PID" 2>/dev/null; then
    echo "[!] Falló el servidor de la UI:" >&2
    cat "$UI_LOG" >&2 || true
    rm -f "$UI_LOG"
    exit 1
  fi
  sleep 0.1
done

if [[ -z "${UI_PORT}" ]]; then
  echo "[!] No se pudo determinar el puerto de la UI. Log:" >&2
  cat "$UI_LOG" >&2 || true
  rm -f "$UI_LOG"
  exit 1
fi
rm -f "$UI_LOG"

wait_port "$UI_PORT" "UI estática"
if [[ "$UI_PORT" != "$UI_PORT_PREF" ]]; then
  echo "    ℹ Puerto ${UI_PORT_PREF} no disponible; UI en :${UI_PORT}"
fi

show_stage 'Servicios listos'
echo
echo "=============================================="
echo "  Panel:       http://127.0.0.1:${UI_PORT}/"
echo "  Balanceador: http://127.0.0.1:8000/"
echo "  Docs API:    http://127.0.0.1:8000/docs"
echo "  (API sin cambios: balanceador.py / servidores.py)"
echo "  Ctrl+C para detener todo"
echo "=============================================="
echo

wait
