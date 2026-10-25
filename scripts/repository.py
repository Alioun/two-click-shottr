"""Files eligible for a source release, shared by validation and packaging."""
from pathlib import Path
import os
import subprocess

ROOT = Path(__file__).resolve().parent.parent
EXCLUDED = {".git", ".build", "dist", ".audit", "__pycache__", ".DS_Store"}


def source_files():
    if (ROOT / ".git").exists():
        output = subprocess.check_output(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT)
        return sorted({ROOT / os.fsdecode(name) for name in output.split(b"\0") if name})
    result = []
    for directory, folders, names in os.walk(ROOT):
        folders[:] = [name for name in folders if name not in EXCLUDED]
        result.extend(Path(directory) / name for name in names if name not in EXCLUDED)
    return sorted(result)


def validate_source():
    failures = []
    text_types = {".swift", ".md", ".py", ".sh", ".command", ".yml", ".yaml", ".plist"}
    for path in source_files():
        if not path.exists():
            continue
        relative = path.relative_to(ROOT)
        if path.is_symlink() or path.suffix in {".pem", ".key", ".p12", ".pfx", ".mobileprovision"} or path.name.startswith(".env"):
            failures.append(str(relative))
            continue
        if path.suffix not in text_types and path.name not in {"LICENSE", ".gitignore"}:
            continue
        contents = path.read_text()
        private_markers = ["/" + "Users/", "/" + "home/", ".t3/" + "scratch/",
                           "t3-" + "thread://", "node:" + "delegated-task:",
                           "-----BEGIN " + "PRIVATE KEY-----", "-----BEGIN RSA " + "PRIVATE KEY-----"]
        if any(marker in contents for marker in private_markers):
            failures.append(str(relative))
    if failures:
        raise SystemExit("Source release contains local paths or signing material in: " + ", ".join(failures))
