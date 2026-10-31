"""Contract checks for launcher safeguards and documentation."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

if os.name == "posix":
    import pty

ROOT = Path(__file__).resolve().parents[1]


class LauncherContracts(unittest.TestCase):
    def test_windows_never_kills_unowned_port_listeners(self):
        script = (ROOT / "windows/iniciar.ps1").read_text(encoding="utf-8")
        self.assertNotIn("Get-NetTCPConnection", script)
        self.assertNotIn("Free-Port", script)
        self.assertIn("Ensure-PortFree", script)

    def test_windows_checks_writable_workspace_and_architecture(self):
        script = (ROOT / "windows/iniciar.ps1").read_text(encoding="utf-8")
        self.assertIn("function Test-Workspace", script)
        self.assertIn("Is64BitOperatingSystem", script)
        self.assertIn("$CheckOnly", script)

    def test_both_launchers_report_real_stages(self):
        windows = (ROOT / "windows/iniciar.ps1").read_text(encoding="utf-8")
        linux = (ROOT / "iniciar.sh").read_text(encoding="utf-8")
        self.assertIn("function Show-Stage", windows)
        self.assertIn("show_stage()", linux)

    def test_linux_uses_venv_python_for_pip_and_uvicorn(self):
        linux = (ROOT / "iniciar.sh").read_text(encoding="utf-8")
        self.assertIn('"$PY" -m pip install', linux)
        self.assertIn('"$PY" -m uvicorn balanceador:app', linux)

    def test_portable_python_native_extensions_are_tracked(self):
        tracked = subprocess.check_output(
            ["git", "ls-files", "windows/runtime/python/*.pyd"],
            cwd=ROOT, text=True,
        ).splitlines()
        self.assertIn("windows/runtime/python/_socket.pyd", tracked)
        self.assertIn("windows/runtime/python/_ssl.pyd", tracked)

    @unittest.skipUnless(os.name == "posix", "PTY disponible en Linux")
    def test_linux_animates_during_dependency_install_and_reports_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "iniciar.sh").write_bytes((ROOT / "iniciar.sh").read_bytes())
            (root / "requirements.txt").write_text("fastapi\n")
            python = root / "venv/bin/python"
            python.parent.mkdir(parents=True)
            python.write_text("#!/bin/sh\nsleep 0.7\necho 'pip failed deliberately' >&2\nexit 17\n")
            python.chmod(0o755)
            master, slave = pty.openpty()
            try:
                env = {**os.environ, "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8"}
                proc = subprocess.Popen(
                    ["bash", str(root / "iniciar.sh")], cwd=root,
                    stdin=subprocess.DEVNULL, stdout=slave, stderr=slave, env=env,
                )
                os.close(slave)
                slave = -1
                proc.wait(timeout=10)
                chunks = []
                while True:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError:
                        break
                    if not chunk:
                        break
                    chunks.append(chunk)
                output = b"".join(chunks).decode("utf-8", errors="replace")
                self.assertEqual(proc.returncode, 17, output)
                self.assertIn("Instalando dependencias", output)
                self.assertIn("⠋", output)
                self.assertIn("⠙", output)
                self.assertIn("pip failed deliberately", output)
                self.assertNotIn("Servicios listos", output)
            finally:
                os.close(master)
                if slave != -1:
                    os.close(slave)

    def test_windows_installer_runs_with_spinner_instead_of_blocking(self):
        script = (ROOT / "windows/iniciar.ps1").read_text(encoding="utf-8")
        self.assertIn("function Invoke-PythonTask", script)
        self.assertIn("Invoke-PythonTask -Arguments @($GetPip", script)
        self.assertIn("Invoke-PythonTask -Arguments @('-m', 'pip', 'install'", script)
        task = script.split("function Invoke-PythonTask {", 1)[1].split("function Wait-Port", 1)[0]
        self.assertIn("$exitCode = $script:SetupProcess.ExitCode", task)
        self.assertLess(task.index("} finally {"), task.index("return $exitCode"))


if __name__ == "__main__":
    unittest.main()
