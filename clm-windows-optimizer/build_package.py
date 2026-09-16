"""Package the checked-in utility without duplicating its PowerShell source."""
from pathlib import Path
import argparse
import shutil
import zipfile

FILES = ("CLM-Windows-Optimizer.ps1", "Run-CLM-Optimizer.cmd", "README.md")


def build(output: Path) -> Path:
    source = Path(__file__).resolve().parent
    output = output.expanduser().resolve()
    if output == source:
        raise ValueError("Choose an output directory different from the source folder.")
    output.mkdir(parents=True, exist_ok=True)
    for name in FILES:
        shutil.copy2(source / name, output / name)
    archive = output / "CLM-Windows-Optimizer-v2.0.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
        for name in FILES:
            bundle.write(output / name, arcname=name)
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent / "dist")
    args = parser.parse_args()
    print(f"Created: {build(args.output)}")
