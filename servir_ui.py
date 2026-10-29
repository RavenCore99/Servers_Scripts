#!/usr/bin/env python3
"""Sirve el panel estático en 127.0.0.1 con reutilización de puerto."""

from __future__ import annotations

import argparse
import functools
import http.server
import socket
import sys
from pathlib import Path


class ReuseHTTPServer(http.server.ThreadingHTTPServer):
    allow_reuse_address = True
    # Evita "Address already in use" tras reinicios rápidos en Linux.
    if hasattr(socket, "SO_REUSEPORT"):
        allow_reuse_port = True


def main() -> None:
    parser = argparse.ArgumentParser(description="Servidor estático del panel")
    parser.add_argument(
        "puerto",
        nargs="?",
        type=int,
        default=5500,
        help="Puerto preferido (si está ocupado se busca el siguiente libre)",
    )
    parser.add_argument(
        "--root",
        default=".",
        help="Directorio a servir (por defecto el actual)",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Falla si el puerto preferido no está libre (no busca alternativa)",
    )
    args = parser.parse_args()

    root = Path(args.root).resolve()
    if not root.is_dir():
        print(f"Directorio inválido: {root}", file=sys.stderr)
        sys.exit(1)

    handler = functools.partial(
        http.server.SimpleHTTPRequestHandler,
        directory=str(root),
    )

    port = args.puerto
    last_err: OSError | None = None
    httpd: ReuseHTTPServer | None = None

    candidates = [port] if args.strict else list(range(port, port + 30))
    for candidate in candidates:
        try:
            httpd = ReuseHTTPServer(("127.0.0.1", candidate), handler)
            port = candidate
            break
        except OSError as err:
            last_err = err
            httpd = None
            continue

    if httpd is None:
        print(
            f"No se pudo abrir un puerto libre desde {args.puerto}: {last_err}",
            file=sys.stderr,
        )
        sys.exit(1)

    print(f"UI_PORT={port}", flush=True)
    print(f"Sirviendo {root} en http://127.0.0.1:{port}/", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()


if __name__ == "__main__":
    main()
