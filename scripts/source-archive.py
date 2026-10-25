#!/usr/bin/env python3
"""Package validated source without Git history, build products, or signing material."""
import argparse
from pathlib import Path
import tarfile
from repository import ROOT, source_files, validate_source


def public_metadata(info):
    info.uid = info.gid = 0
    info.uname = info.gname = ""
    return info


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / ".build/TwoClickShottr-source.tar.gz")
    args = parser.parse_args()
    validate_source()
    files = [path for path in source_files() if path.is_file() and path.resolve() != args.output.resolve()]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(args.output, "w:gz") as archive:
        for path in files:
            archive.add(path, arcname=str(Path("TwoClickShottr") / path.relative_to(ROOT)),
                        recursive=False, filter=public_metadata)
    print(args.output)


if __name__ == "__main__":
    main()
