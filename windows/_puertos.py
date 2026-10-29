#!/usr/bin/env python3
"""Utilidades de puertos para iniciar.sh / iniciar.ps1 (stdlib only)."""

from __future__ import annotations

import argparse
import os
import signal
import socket
import subprocess
import sys
import time


def is_free(host: str, port: int) -> bool:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((host, port))
        return True
    except OSError:
        return False
    finally:
        s.close()


def pids_listening(port: int) -> set[int]:
    pids: set[int] = set()

    # ss -tlnp (Linux)
    try:
        out = subprocess.check_output(
            ["ss", "-tlnp", f"sport = :{port}"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        for line in out.splitlines():
            if "pid=" in line:
                for part in line.split(","):
                    part = part.strip()
                    if part.startswith("pid="):
                        try:
                            pids.add(int(part.split("=", 1)[1]))
                        except ValueError:
                            pass
    except (FileNotFoundError, subprocess.CalledProcessError, OSError):
        pass

    # lsof
    if not pids:
        try:
            out = subprocess.check_output(
                ["lsof", "-t", f"-iTCP:{port}", "-sTCP:LISTEN"],
                text=True,
                stderr=subprocess.DEVNULL,
            )
            for line in out.split():
                try:
                    pids.add(int(line))
                except ValueError:
                    pass
        except (FileNotFoundError, subprocess.CalledProcessError, OSError):
            pass

    # fuser
    if not pids:
        try:
            out = subprocess.check_output(
                ["fuser", f"{port}/tcp"],
                text=True,
                stderr=subprocess.STDOUT,
            )
            for tok in out.replace(":", " ").split():
                if tok.isdigit():
                    pids.add(int(tok))
        except (FileNotFoundError, subprocess.CalledProcessError, OSError):
            pass

    return pids


def free_port(port: int, host: str = "127.0.0.1") -> bool:
    if is_free(host, port):
        return True

    pids = pids_listening(port)
    me = os.getpid()
    for pid in sorted(pids):
        if pid == me:
            continue
        try:
            os.kill(pid, signal.SIGTERM)
            print(f"    liberado puerto {port} (PID {pid})", flush=True)
        except ProcessLookupError:
            pass
        except PermissionError as err:
            print(f"    sin permiso para PID {pid} en :{port}: {err}", file=sys.stderr)

    # Windows / fallback: fuser -k
    try:
        subprocess.run(
            ["fuser", "-k", f"{port}/tcp"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except FileNotFoundError:
        pass

    deadline = time.time() + 2.0
    while time.time() < deadline:
        if is_free(host, port):
            return True
        time.sleep(0.1)
    return is_free(host, port)


def find_free(start: int, count: int = 30, host: str = "127.0.0.1") -> int:
    for port in range(start, start + count):
        if is_free(host, port):
            return port
    raise SystemExit(f"No hay puerto libre desde {start}")


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_check = sub.add_parser("check")
    p_check.add_argument("port", type=int)

    p_free = sub.add_parser("free")
    p_free.add_argument("port", type=int)

    p_find = sub.add_parser("find")
    p_find.add_argument("start", type=int)
    p_find.add_argument("--count", type=int, default=30)

    args = parser.parse_args()
    if args.cmd == "check":
        sys.exit(0 if not is_free("127.0.0.1", args.port) else 1)
    if args.cmd == "free":
        ok = free_port(args.port)
        sys.exit(0 if ok else 1)
    if args.cmd == "find":
        print(find_free(args.start, args.count))


if __name__ == "__main__":
    main()
