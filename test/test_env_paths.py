"""Environment setup must work after relocation, without a developer's home path."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class EnvironmentPaths(unittest.TestCase):
    def test_hello_uses_checkout_venv_even_when_suite_changes_python(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / "fpga"
            (repo / "script").mkdir(parents=True)
            for name in ("env.sh", "run_hello.sh"):
                shutil.copy(ROOT / "script" / name, repo / "script" / name)
            suite = Path(tmp) / "suite"
            suite.mkdir()
            (suite / "environment").write_text('export PATH="' + str(suite) + ':$PATH"\n')
            # Hardware and build processes are replaced at the process boundary.
            for name, text in {"make": "exit 0", "timeout": "exit 0", "sleep": "exit 0", "python3": "echo WRONG_PYTHON"}.items():
                executable = suite / name
                executable.write_text("#!/bin/sh\n" + text + "\n")
                executable.chmod(0o755)
            interpreter = repo / ".venv/bin/python"
            interpreter.parent.mkdir(parents=True)
            interpreter.write_text("#!/bin/sh\necho REPO_VENV\n")
            interpreter.chmod(0o755)
            env = dict(os.environ, OSS_CAD_SUITE=str(suite))
            env.pop("PYTHON", None)
            result = subprocess.run(["bash", str(repo / "script/run_hello.sh"), "unused", "19200", "1"], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "REPO_VENV")

    def test_source_from_another_directory_and_honor_tool_overrides(self):
        for shell in ("bash", "zsh"):
            if not shutil.which(shell):
                continue
            for override in (False, True):
                with self.subTest(shell=shell, override=override), tempfile.TemporaryDirectory() as tmp:
                    base = Path(tmp)
                    repo = base / "project with spaces" / "fpga"
                    (repo / "script").mkdir(parents=True)
                    shutil.copy(ROOT / "script/env.sh", repo / "script/env.sh")
                    tools = base / "custom tools" if override else repo.parent / ".tools"
                    suite = base / "custom suite" if override else tools / "oss-cad-suite"
                    suite.mkdir(parents=True)
                    (suite / "environment").write_text("export SUITE_WAS_LOADED=yes\n")
                    env = os.environ.copy()
                    for key in ("TANG_TOOLS_DIR", "OSS_CAD_SUITE", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME"):
                        env.pop(key, None)
                    if override:
                        env.update(TANG_TOOLS_DIR=str(tools), OSS_CAD_SUITE=str(suite))
                    result = subprocess.run(
                        [shell, "-c", '. "$1" || exit; printf "%s\\n" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$SUITE_WAS_LOADED" "$PATH"', "test", str(repo / "script/env.sh")],
                        cwd=base, env=env, capture_output=True, text=True,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stderr, "")
                    lines = result.stdout.splitlines()
                    self.assertEqual(lines[:4], [str(tools / "xdg" / part) for part in ("config", "cache", "data")] + ["yes"])
                    self.assertEqual(lines[4].split(":")[0], str(repo / "script/bin"))


if __name__ == "__main__":
    unittest.main()
