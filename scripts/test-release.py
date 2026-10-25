#!/usr/bin/env python3
"""Exercise release decisions without contacting GitHub."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for directory in ("scripts", "Resources", "dist", "bin"):
            (self.root / directory).mkdir()
        shutil.copy(ROOT / "scripts/publish-release.sh", self.root / "scripts")
        shutil.copy(ROOT / "Resources/Info.plist", self.root / "Resources")
        self.version = subprocess.check_output([
            "/usr/libexec/PlistBuddy", "-c", "Print :CFBundleShortVersionString",
            str(self.root / "Resources/Info.plist")], text=True).strip()
        archive = f"TwoClickShottr-{self.version}-universal-experimental.zip"
        (self.root / "dist" / archive).write_bytes(b"fixture")
        digest = hashlib.sha256(b"fixture").hexdigest()
        (self.root / "dist" / (archive + ".sha256")).write_text(f"{digest}  {archive}\n")
        gh = self.root / "bin/gh"
        gh.write_text('''#!/bin/bash
set -eu
if [[ "$1" == api ]]; then
    [[ "${API_FAILURE:-0}" == 0 ]] || exit 17
    printf '%s\n' "${EXISTING_TAG:-}"
else
    printf '%s\n' "$@" > "$CALL_LOG"
    cp "${@: -1}" "$NOTES_LOG"
fi
''')
        gh.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.root / "bin") + ":/usr/bin:/bin:/usr/sbin:/sbin",
                        GITHUB_REPOSITORY="example/app", GITHUB_SHA="fixture-commit",
                        CALL_LOG=str(self.root / "call"), NOTES_LOG=str(self.root / "notes"))

    def run_release(self, **env):
        return subprocess.run([str(self.root / "scripts/publish-release.sh")],
                              env=dict(self.env, **env), capture_output=True, text=True)

    def test_existing_release_is_unchanged(self):
        result = self.run_release(EXISTING_TAG="v" + self.version)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "call").exists())

    def test_api_failure_does_not_publish(self):
        self.assertNotEqual(self.run_release(API_FAILURE="1").returncode, 0)
        self.assertFalse((self.root / "call").exists())

    def test_new_release_targets_built_commit_and_discloses_signing(self):
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        args = (self.root / "call").read_text().splitlines()
        self.assertIn("v" + self.version, args)
        self.assertEqual(args[args.index("--target") + 1], "fixture-commit")
        self.assertIn("not Apple-notarized", (self.root / "notes").read_text())

    def test_corrupt_download_does_not_publish(self):
        next((self.root / "dist").glob("*.zip")).write_bytes(b"corrupt")
        self.assertNotEqual(self.run_release().returncode, 0)
        self.assertFalse((self.root / "call").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
