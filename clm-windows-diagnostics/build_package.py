"""Copy the runnable Windows files into an explicit output folder."""
import argparse
from pathlib import Path
import shutil


def main():
    source = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=source / 'dist')
    destination = parser.parse_args().output.expanduser().resolve()
    destination.mkdir(parents=True, exist_ok=True)
    for name in ('CLM-Windows-Diagnostics.ps1', 'CLM-Audit.ps1', 'Launch-CLM.cmd', 'README.md'):
        original = source / name
        target = destination / name
        if original.resolve() != target:
            shutil.copyfile(original, target)
        print(f'Ready: {target}')


if __name__ == '__main__':
    main()
