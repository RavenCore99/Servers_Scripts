#!/usr/bin/env bash
# Arranque portable: 3 servidores + balanceador FastAPI + UI estática
# No modifica balanceador.py ni servidores.py.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

PY="${ROOT}/venv/bin/python"
PIP="${ROOT}/venv/bin/pip"
UVICORN="${ROOT}/venv/bin/uvicorn"

if [[ ! -x "$PY" ]]; then
  echo "[*] Creando entorno virtual en ./venv ..."
  python3 -m venv venv
  PY="${ROOT}/venv/bin/python"
  PIP="${ROOT}/venv/bin/pip"
  UVICORN="${ROOT}/venv/bin/uvicorn"
fi

echo "[*] Instalando dependencias mínimas (fastapi, uvicorn, httpx) ..."
"$PIP" install -q -r requirements.txt

PIDS=()
cleanup() {
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
trap cleanup EXIT INT TERM

port_busy() {
  # exit 0 si ocupado, 1 si libre
  "$PY" _puertos.py check "$1"
}

ensure_port_free() {
  local port="$1"
  local name="$2"
  if port_busy "$port"; then
    echo "[!] Puerto ${port} ocupado (${name}). Intentando liberarlo..."
    if ! "$PY" _puertos.py free "$port"; then
      echo "    ✗ No se pudo liberar :${port}." >&2
      echo "      Cierra el proceso manualmente: ss -tlnp | grep ${port}" >&2
      exit 1
    fi
    echo "    ✓ Puerto ${port} libre"
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
      echo "    ✓ ${name} listo en :${port}"
      return 0
    fi
    sleep 0.15
    ((i++)) || true
  done
  echo "    ✗ Timeout esperando ${name} (:${port})" >&2
  return 1
}

# Puertos de la API son fijos en balanceador.py
ensure_port_free 8001 "Servidor 1"
ensure_port_free 8002 "Servidor 2"
ensure_port_free 8003 "Servidor 3"
ensure_port_free 8000 "Balanceador"

UI_PORT_PREF="${UI_PORT:-5500}"
if port_busy "$UI_PORT_PREF"; then
  echo "[!] Puerto UI ${UI_PORT_PREF} ocupado. Intentando liberarlo..."
  "$PY" _puertos.py free "$UI_PORT_PREF" || true
fi

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

echo "[*] Iniciando balanceador FastAPI → :8000"
"$UVICORN" balanceador:app --host 127.0.0.1 --port 8000 &
PIDS+=($!)
wait_port 8000 "Balanceador"

UI_LOG="$(mktemp)"
echo "[*] Sirviendo panel web (preferido :${UI_PORT_PREF})..."
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
