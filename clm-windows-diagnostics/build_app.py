"""Build the CLM Windows GUI as a single-file executable with PyInstaller.

Run this on Windows. PyInstaller does not cross-compile Windows executables.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys


def main() -> int:
    source = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=source / "dist")
    args = parser.parse_args()

    if os.name != "nt":
        raise SystemExit("build_app.py must run on Windows.")

    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)

    app = source / "CLM-Windows-App.py"
    engine = source / "CLM-Windows-Diagnostics.ps1"
    work = source / ".pyinstaller-build"
    spec = source / ".pyinstaller-spec"

    for required in (app, engine):
        if not required.is_file():
            raise SystemExit(f"Missing required file: {required}")

    command = [
        sys.executable,
        "-m",
        "PyInstaller",
        "--noconfirm",
        "--clean",
        "--onefile",
        "--windowed",
        "--name",
        "CLM-Windows-Diagnostics",
        "--distpath",
        str(output),
        "--workpath",
        str(work),
        "--specpath",
        str(spec),
        "--add-data",
        f"{engine}{os.pathsep}.",
        str(app),
    ]

    print("Building Windows application:")
    print(" ".join(f'"{part}"' if " " in part else part for part in command))
    completed = subprocess.run(command, check=False)
    if completed.returncode != 0:
        return completed.returncode

    exe = output / "CLM-Windows-Diagnostics.exe"
    if not exe.is_file():
        raise SystemExit(f"PyInstaller completed but the executable is missing: {exe}")

    print(f"Ready: {exe}")
    print("Note: the executable is unsigned, so Windows SmartScreen may display a warning.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
