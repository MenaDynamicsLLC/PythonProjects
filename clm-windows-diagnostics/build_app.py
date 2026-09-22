"""Build CLM Windows Toolkit as a single-file Windows executable.

Run this on Windows. PyInstaller does not cross-compile Windows executables.
The build also creates a simple CLM application icon if one is not present.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys


APP_NAME = "CLM-Windows-Toolkit"
ICON_NAME = "clm-toolkit.ico"


def create_icon(path: Path) -> None:
    """Create a simple CLM icon using Pillow."""
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError as exc:
        raise SystemExit(
            "Pillow is required to generate the app icon. "
            "Install it with: python -m pip install pillow"
        ) from exc

    size = 256
    image = Image.new("RGBA", (size, size), (24, 49, 83, 255))
    draw = ImageDraw.Draw(image)

    margin = 18
    draw.rounded_rectangle(
        (margin, margin, size - margin, size - margin),
        radius=36,
        outline=(79, 195, 247, 255),
        width=10,
    )

    font_paths = [
        Path(os.environ.get("WINDIR", r"C:\Windows")) / "Fonts" / "segoeuib.ttf",
        Path(os.environ.get("WINDIR", r"C:\Windows")) / "Fonts" / "arialbd.ttf",
    ]
    font = None
    for candidate in font_paths:
        if candidate.is_file():
            font = ImageFont.truetype(str(candidate), 86)
            break
    if font is None:
        font = ImageFont.load_default()

    text = "CLM"
    bbox = draw.textbbox((0, 0), text, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    x = (size - text_w) / 2
    y = (size - text_h) / 2 - 8
    draw.text((x, y), text, font=font, fill=(255, 255, 255, 255))

    draw.rounded_rectangle(
        (58, 190, 198, 204),
        radius=7,
        fill=(79, 195, 247, 255),
    )

    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(
        path,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )


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
    version_info = source / "version_info.txt"
    icon = source / ICON_NAME
    work = source / ".pyinstaller-build"
    spec = source / ".pyinstaller-spec"

    for required in (app, engine, version_info):
        if not required.is_file():
            raise SystemExit(f"Missing required file: {required}")

    create_icon(icon)

    command = [
        sys.executable,
        "-m",
        "PyInstaller",
        "--noconfirm",
        "--clean",
        "--onefile",
        "--windowed",
        "--name",
        APP_NAME,
        "--icon",
        str(icon),
        "--version-file",
        str(version_info),
        "--distpath",
        str(output),
        "--workpath",
        str(work),
        "--specpath",
        str(spec),
        "--add-data",
        f"{engine}{os.pathsep}.",
        "--add-data",
        f"{icon}{os.pathsep}.",
        str(app),
    ]

    print("Building Windows application:")
    print(" ".join(f'"{part}"' if " " in part else part for part in command))
    completed = subprocess.run(command, check=False)
    if completed.returncode != 0:
        return completed.returncode

    exe = output / f"{APP_NAME}.exe"
    if not exe.is_file():
        raise SystemExit(f"PyInstaller completed but the executable is missing: {exe}")

    output_icon = output / ICON_NAME
    if icon.resolve() != output_icon.resolve():
        shutil.copy2(icon, output_icon)

    print(f"Ready: {exe}")
    print("Publisher metadata: Mena Dynamics, LLC")
    print("Version: 1.3.0")
    print("Note: GitHub build artifacts are unsigned until Sign-CLM.ps1 is run with your code-signing certificate.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
