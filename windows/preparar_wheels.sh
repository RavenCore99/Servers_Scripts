#!/usr/bin/env bash
# Regenera vendor/wheels para Windows desde Linux (requiere red).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHEELS="$ROOT/vendor/wheels"
REQ="$ROOT/requirements.txt"
mkdir -p "$WHEELS"

PIP="${PIP:-pip3}"
if [[ -x "$(dirname "$ROOT")/venv/bin/pip" ]]; then
  PIP="$(dirname "$ROOT")/venv/bin/pip"
elif [[ -x "$ROOT/../venv/bin/pip" ]]; then
  PIP="$ROOT/../venv/bin/pip"
fi

pkgs=(fastapi uvicorn httpx httptools watchfiles websockets colorama
      starlette pydantic pydantic-core annotated-types typing-extensions
      anyio sniffio idna certifi httpcore h11 click annotated-doc
      importlib-metadata zipp)

echo "[*] Descargando wheels win_amd64 → $WHEELS"
for ver in 310 311 312 313 314; do
  echo "=== cp$ver ==="
  "$PIP" download "${pkgs[@]}" -d "$WHEELS" \
    --platform win_amd64 --python-version "$ver" --implementation cp --abi "cp${ver}" \
    --only-binary=:all: || true
done
"$PIP" download "${pkgs[@]}" -d "$WHEELS" --only-binary=:all: || true
rm -f "$WHEELS"/*manylinux* "$WHEELS"/*linux* 2>/dev/null || true
echo "[*] Listo: $(ls "$WHEELS"/*.whl 2>/dev/null | wc -l) wheels"
