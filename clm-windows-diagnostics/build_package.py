"""Build the CLM Windows Toolkit distribution folder and ZIP.

Run build_app.py first if you want the compiled EXE included.
"""
import argparse
from pathlib import Path
import shutil
import zipfile


SOURCE_FILES = (
    "CLM-Windows-Diagnostics.ps1",
    "CLM-Audit.ps1",
    "Launch-CLM.cmd",
    "README.md",
    "Sign-CLM.ps1",
    "version_info.txt",
)
OPTIONAL_BUILT_FILES = (
    "CLM-Windows-Toolkit.exe",
    "clm-toolkit.ico",
)


def main():
    source = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=source / "dist")
    args = parser.parse_args()
    destination = args.output.expanduser().resolve()

    if destination == source:
        raise SystemExit("Choose an output directory different from the source folder.")

    destination.mkdir(parents=True, exist_ok=True)

    packaged = []
    for name in SOURCE_FILES:
        original = source / name
        target = destination / name
        if original.resolve() != target.resolve():
            shutil.copy2(original, target)
        packaged.append(target)

    for name in OPTIONAL_BUILT_FILES:
        target = destination / name
        if target.is_file():
            packaged.append(target)

    archive = destination / "CLM-Windows-Toolkit-Windows.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
        for file_path in packaged:
            bundle.write(file_path, arcname=file_path.name)

    print(f"Created: {archive}")
    for item in packaged:
        print(f"Included: {item.name}")


if __name__ == "__main__":
    main()
