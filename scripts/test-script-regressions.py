#!/usr/bin/env python3
"""Isolated script regressions. No app launch, signing, Keychain writes, or Swift build."""
import json
import os
from pathlib import Path
import pty
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parent
MOCK = r'''#!/usr/bin/env python3
import json, os, pathlib, shutil, signal, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
failure = os.environ.get('MOCK_FAIL', '')
with open(os.environ['MOCK_LOG'], 'a') as log:
    log.write(json.dumps([name, args]) + '\n')
if name == 'ditto':
    source, dest = map(pathlib.Path, args)
    dest.mkdir()
    if failure == 'copy':
        (dest / 'partial').touch()
        sys.exit(7)
    shutil.copytree(source, dest, dirs_exist_ok=True)
elif name == 'codesign':
    if '-d' in args:
        print('Executable=diagnostic-only', file=sys.stderr)
        print('designated => ' + os.environ.get('MOCK_REQUIREMENT', 'identifier "local.two-click-shottr" and certificate leaf = H"' + 'A'*40 + '"'))
    elif '--sign' in args:
        if failure == 'sign': sys.exit(7)
    elif '--verify' in args:
        staged = pathlib.Path(args[-1]).name == 'candidate.app'
        if failure == ('stage-verify' if staged else 'final-verify'): sys.exit(7)
elif name == 'mv':
    source, dest = map(pathlib.Path, args)
    old = dest.name == 'previous.app'
    new = source.name == 'candidate.app'
    step = 'old' if old else 'new' if new else 'rollback'
    if failure == 'move-' + step: sys.exit(7)
    os.rename(source, dest)
    if failure == 'signal-' + step:
        os.kill(os.getppid(), signal.SIGTERM)
elif name == 'security':
    if os.environ.get('MOCK_IDENTITY', 'present') == 'present':
        print('  1) ' + 'A'*40 + ' "Two Click Shottr Local" (CSSMERR_TP_NOT_TRUSTED)')
elif name == 'swift':
    if '--show-bin-path' in args: print(os.environ['MOCK_BINARY_DIR'])
elif name == 'open':
    report = pathlib.Path(args[args.index('--stdout') + 1])
    mode = args[-1]
    if failure == 'launch': sys.exit(7)
    if failure == 'timeout': sys.exit(0)
    if mode == '--diagnose':
        report.write_text(json.dumps({'screenCapturePermission': os.environ.get('MOCK_PERMISSION', 'true') == 'true'}))
    elif mode == '--verify-capture':
        report.write_text(json.dumps({'passed': os.environ.get('MOCK_CAPTURE', 'true') == 'true'}))
    else: sys.exit(9)
elif name == 'sleep':
    pass
else:
    sys.exit(9)
'''


class ScriptRegressions(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='two-click-script-tests-')
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.log = self.root / 'commands.jsonl'
        for name in ('codesign', 'ditto', 'mv', 'security', 'swift', 'open', 'sleep'):
            path = self.bin / name
            path.write_text(MOCK)
            path.chmod(0o755)
        self.env = dict(os.environ, PATH=f'{self.bin}:/usr/bin:/bin', MOCK_LOG=str(self.log),
                        HOME=str(self.root), TMPDIR=str(self.root))
        self.env.pop('CODE_SIGN_IDENTITY', None)

    def tearDown(self):
        self.temp.cleanup()

    def shell(self, command, *args, stdin=None, **env):
        return subprocess.run(['/bin/bash', '-c', command, 'regression', *map(str, args)],
                              env=dict(self.env, **env), input=stdin, text=True, capture_output=True)

    def helper(self, command, *args, **env):
        return self.shell('source "$1"; shift; ' + command, SCRIPTS / 'signing-support.sh', *args, **env)

    def commands(self):
        return [json.loads(row) for row in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_identity_suffix_duplicate_and_ambiguity(self):
        a, b = 'A'*40, 'B'*40
        rows = f'  1) {a} "Two Click Shottr Local" (CSSMERR_TP_NOT_TRUSTED)\n  2) {a} "Two Click Shottr Local"\n'
        result = self.helper('resolve_signing_identity "Two Click Shottr Local"', stdin=rows)
        self.assertEqual((result.returncode, result.stdout.strip()), (0, a))
        rows += f'  3) {b} "Two Click Shottr Local" (CSSMERR_TP_CERT_EXPIRED)\n'
        self.assertNotEqual(self.helper('resolve_signing_identity "Two Click Shottr Local"', stdin=rows).returncode, 0)
        self.assertEqual(self.helper('resolve_signing_identity "Two Click Shottr Local" exists', stdin=rows).returncode, 0)
        result = self.helper('resolve_signing_identity "$1"', a.lower(), stdin=rows)
        self.assertEqual(result.stdout.strip(), a)
        for requested in ('Two Click', '', '-'):
            self.assertNotEqual(self.helper('resolve_signing_identity "$1"', requested, stdin=rows).returncode, 0)

    def test_actual_codesign_requirement_stdout(self):
        installed = Path.home() / 'Applications/Two Click Shottr.app'
        if not installed.is_dir():
            self.skipTest('No installed bundle available for read-only codesign extraction')
        result = self.helper('PATH=/usr/bin:/bin; designated_requirement "$1"', installed)
        self.assertEqual(result.returncode, 0, result.stderr)
        direct = subprocess.run(['/usr/bin/codesign', '-d', '-r-', str(installed)], capture_output=True, text=True)
        expected = [row.split('designated => ', 1)[1] for row in direct.stdout.splitlines() if 'designated => ' in row]
        self.assertEqual(result.stdout.strip(), expected[0])
        self.assertNotIn('Executable=', result.stdout)

    def test_stable_requirement_accepts_default_certificate_anchors(self):
        for requirement in ('identifier "local.two-click-shottr" and anchor H"' + 'A'*40 + '"',
                            'identifier "local.two-click-shottr" and certificate leaf = H"' + 'A'*40 + '"'):
            result = self.helper('stable_requirement ignored.app', MOCK_REQUIREMENT=requirement)
            self.assertEqual((result.returncode, result.stdout.strip()), (0, requirement))
        result = self.helper('stable_requirement ignored.app', MOCK_REQUIREMENT='cdhash H"' + 'A'*40 + '"')
        self.assertNotEqual(result.returncode, 0)

    def test_prompt_rejects_nonterminal_and_tty_eof(self):
        for function in ('repair_confirm', 'repair_pause'):
            result = self.shell('source "$1"; ' + function + ' test', SCRIPTS / 'repair-input.sh', stdin='')
            self.assertNotEqual(result.returncode, 0)
            master, slave = pty.openpty()
            try:
                process = subprocess.Popen(['/bin/bash', '-c', 'source "$1"; ' + function + ' test',
                                            'regression', str(SCRIPTS / 'repair-input.sh')],
                                           stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                           env=self.env, text=True)
                os.close(slave)
                slave = None
                os.write(master, b'\x04')
                stdout, stderr = process.communicate(timeout=5)
                self.assertNotEqual(process.returncode, 0, stdout)
                self.assertIn('Input closed', stderr)
            finally:
                os.close(master)
                if slave is not None: os.close(slave)

    def test_json_false_ready_and_timeout(self):
        report = self.root / 'report.json'
        for value in (True, False):
            report.write_text(json.dumps({'passed': value}))
            result = self.shell('source "$1"; wait_for_report "$2" passed 1', SCRIPTS / 'verification-support.sh', report)
            self.assertEqual((result.returncode, result.stdout.strip()), (0, str(value).lower()))
            self.assertFalse(any(name == 'sleep' for name, _ in self.commands()))
        for payload in ('{"passed":', '{"passed":"true"}', '{}'):
            report.write_text(payload)
            result = self.shell('source "$1"; wait_for_report "$2" passed 1', SCRIPTS / 'verification-support.sh', report)
            self.assertEqual(result.returncode, 3)
            self.assertIn('Timed out', result.stderr)

    def replacement(self, failure='', prior=True):
        source = self.root / 'source.app'
        source.mkdir()
        (source / 'new').write_text('new')
        destination = self.root / 'Apps/Installed.app'
        destination.parent.mkdir()
        backup = destination.parent / 'existing-backup.zip'
        backup.write_text('saved backup')
        if prior:
            destination.mkdir()
            (destination / 'old').write_text('original')
        result = self.helper('replace_signed_app "$1" "$2" "certificate leaf = test"', source, destination, MOCK_FAIL=failure)
        self.assertEqual(backup.read_text(), 'saved backup')
        self.assertEqual(list(destination.parent.glob('.two-click-replace.*')), [])
        return result, destination

    def test_replacement_removes_leftovers(self):
        result, destination = self.replacement()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([p.name for p in destination.iterdir()], ['new'])
        staged = [args[1] for name, args in self.commands() if name == 'ditto'][0]
        self.assertEqual(Path(staged).parent.parent, destination.parent)

    def test_replacement_rolls_back_all_failures(self):
        for failure in ('copy', 'stage-verify', 'final-verify', 'move-old', 'move-new', 'signal-old', 'signal-new'):
            with self.subTest(failure=failure):
                with tempfile.TemporaryDirectory(dir=self.root) as case:
                    original_root = self.root
                    self.root = Path(case)
                    try:
                        result, destination = self.replacement(failure)
                        self.assertNotEqual(result.returncode, 0)
                        self.assertEqual([p.name for p in destination.iterdir()], ['old'])
                        self.assertEqual((destination / 'old').read_text(), 'original')
                    finally:
                        self.root = original_root

    def test_replacement_failure_without_prior_install(self):
        for failure in ('copy', 'stage-verify', 'move-new', 'final-verify', 'signal-new'):
            with self.subTest(failure=failure):
                with tempfile.TemporaryDirectory(dir=self.root) as case:
                    original_root = self.root
                    self.root = Path(case)
                    try:
                        result, destination = self.replacement(failure, prior=False)
                        self.assertNotEqual(result.returncode, 0)
                        self.assertFalse(destination.exists())
                    finally:
                        self.root = original_root

    def test_failed_rollback_retains_previous_bundle(self):
        source = self.root / 'source.app'
        source.mkdir()
        (source / 'new').touch()
        destination = self.root / 'Installed.app'
        destination.mkdir()
        (destination / 'old').write_text('original')
        # Fail the final verification and then the restoration rename.
        mock = self.bin / 'mv'
        mock.write_text(MOCK.replace("if failure == 'move-' + step:",
                                     "if failure == 'final-verify' and step == 'rollback': sys.exit(7)\n    if failure == 'move-' + step:"))
        result = self.helper('replace_signed_app "$1" "$2" "certificate leaf = test"',
                             source, destination, MOCK_FAIL='final-verify')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Previous app retained at', result.stderr)
        saved = list(self.root.glob('.two-click-replace.*/previous.app/old'))
        self.assertEqual(len(saved), 1)
        self.assertEqual(saved[0].read_text(), 'original')

    def build_fixture(self):
        repo = self.root / 'repo'
        shutil.copytree(SCRIPTS, repo / 'scripts')
        shutil.copytree(SCRIPTS.parent / 'Resources', repo / 'Resources')
        dist = repo / 'dist/Two Click Shottr.app'
        dist.mkdir(parents=True)
        (dist / 'old').write_text('original')
        binary_dir = self.root / 'binary'
        binary_dir.mkdir()
        (binary_dir / 'TwoClickShottr').write_text('mock executable')
        self.env['MOCK_BINARY_DIR'] = str(binary_dir)
        return repo, dist

    def test_missing_certificate_leaves_dist_and_never_builds(self):
        repo, dist = self.build_fixture()
        result = self.shell('"$1"', repo / 'scripts/build.sh', MOCK_IDENTITY='missing')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((dist / 'old').read_text(), 'original')
        self.assertFalse(any(name in ('swift', 'codesign') for name, _ in self.commands()))

    def test_build_signing_failure_leaves_dist(self):
        repo, dist = self.build_fixture()
        result = self.shell('"$1"', repo / 'scripts/build.sh', MOCK_FAIL='sign')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((dist / 'old').read_text(), 'original')
        self.assertEqual(list(dist.parent.glob('.two-click-*')), [])

    def test_build_success_replaces_dist(self):
        repo, dist = self.build_fixture()
        result = self.shell('"$1"', repo / 'scripts/build.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((dist / 'old').exists())
        self.assertTrue((dist / 'Contents/MacOS/TwoClickShottr').exists())
        self.assertEqual(list(dist.parent.glob('.two-click-*')), [])

    def test_failed_import_marker_refuses_regeneration(self):
        state = self.root / 'Support/signing-setup-pending'
        self.assertEqual(self.helper('reserve_signing_setup "$1"', state).returncode, 0)
        result = self.helper('reserve_signing_setup "$1"', state)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('No new key will be generated', result.stderr)
        self.assertIn('Keychain Access', result.stderr)
        self.assertEqual(self.commands(), [])

    def test_installed_cli_diagnosis_denial_capture_and_timeout(self):
        installed = self.root / 'Applications/Two Click Shottr.app'
        installed.mkdir(parents=True)
        for mode, permission, failure, expected in (
            ('--diagnose', 'false', '', 1), ('--diagnose', 'true', '', 0),
            ('--capture', 'false', '', 1), ('--capture', 'true', '', 0),
            ('--diagnose', 'true', 'timeout', 3), ('--diagnose', 'true', 'launch', 4),
        ):
            with self.subTest(mode=mode, permission=permission, failure=failure):
                self.log.unlink(missing_ok=True)
                result = self.shell('"$1" "$2"', SCRIPTS / 'verify-installed.sh', mode,
                                    MOCK_PERMISSION=permission, MOCK_FAIL=failure)
                self.assertEqual(result.returncode, expected, result.stderr)
                opens = [args for name, args in self.commands() if name == 'open']
                self.assertEqual(len(opens), 2 if mode == '--capture' and permission == 'true' else 1)
                for args in opens:
                    self.assertIn(str(installed), args)
                    self.assertEqual(args[0], '-n')
                self.assertEqual(opens[0][-1], '--diagnose')
                if len(opens) == 2: self.assertEqual(opens[1][-1], '--verify-capture')
                self.assertEqual(list(self.root.glob('two-click-verify.*')), [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
