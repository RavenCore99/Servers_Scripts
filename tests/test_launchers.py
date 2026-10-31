"""Contract checks for launcher safeguards and documentation."""
from pathlib import Path
import subprocess
import unittest

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


if __name__ == "__main__":
    unittest.main()
