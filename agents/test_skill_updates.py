#!/usr/bin/env python3
"""Offline updater regressions using real Git/diff/rsync in disposable folders."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


def mock_tool(tool, args):
    """Replace downloads and inject failures; delegate local work to real tools."""
    with open(os.environ['TEST_CALLS'], 'a') as log:
        log.write(json.dumps([tool, *args]) + '\n')
    scenario = os.environ.get('TEST_SCENARIO', '')
    local = Path(os.environ['TEST_ROOT']) / 'agents/skills'
    if tool == 'git':
        command = list(args)
        while command and command[0] in ('-c', '-C'):
            command = command[2:]
        if command[0] == 'clone':
            if scenario == 'offline':
                return 1
            shutil.copytree(os.environ['TEST_REMOTE'], args[-1])
            if scenario == 'missing':
                (Path(args[-1]) / 'skills/ce-code-review/SKILL.md').unlink()
            return 0
        if command[0] == 'sparse-checkout':
            if scenario == 'sparse-fail':
                return 1
            if scenario == 'edit-during-fetch':
                (local / 'ce-code-review/local.md').write_text('keep me\n')
            return 0
        if command[0] == 'rev-parse':
            print('abcdef0')
            return 0
    elif scenario in ('copy-fail', 'copy-noop'):
        return 23 if scenario == 'copy-fail' else 0
    result = subprocess.run([os.environ['TEST_' + tool.upper()], *args])
    if tool == 'rsync' and scenario == 'edit-during-first-copy':
        (local / 'ce-code-review/local.md').write_text('keep me\n')
    return result.returncode


class SkillUpdatesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='dotfiles-skills-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.agents = self.root / 'agents'
        self.agents.mkdir()
        source = Path(__file__).resolve().parent
        for name in ('install.sh', 'check-skill-updates.sh'):
            shutil.copy2(source / name, self.agents / name)
        # Normal setup tests exercise its warning handling without creating home links.
        library = (source.parent / 'install-lib.sh').read_text()
        (self.root / 'install-lib.sh').write_text(library + '\nlink_config() { :; }\n')
        self.skills = self.agents / 'skills'
        for name in ('ce-simplify-code', 'ce-code-review'):
            folder = self.skills / name
            folder.mkdir(parents=True)
            (folder / 'SKILL.md').write_text('fixture\n')
            (folder / 'reference.md').write_text('old\n')
        (self.skills / 'ce-code-review/obsolete.md').write_text('obsolete\n')
        self.remote = self.root / 'remote'
        shutil.copytree(self.skills, self.remote / 'skills')
        self.calls = self.root / 'calls.jsonl'
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_CONFIG_SYSTEM=os.devnull, GIT_CONFIG_NOSYSTEM='1',
                        GIT_CONFIG_COUNT='0', TEST_ROOT=str(self.root),
                        TEST_REMOTE=str(self.remote), TEST_CALLS=str(self.calls),
                        TEST_PYTHON=sys.executable, TEST_SCRIPT=str(Path(__file__).resolve()))
        for tool in ('git', 'rsync'):
            executable = shutil.which(tool)
            if not executable:
                self.skipTest(f'{tool} is required')
            self.env['TEST_' + tool.upper()] = executable
            shim = self.bin / tool
            shim.write_text(f'#!/bin/sh\nexec "$TEST_PYTHON" "$TEST_SCRIPT" --mock-{tool} "$@"\n')
            shim.chmod(0o755)
        self.env['PATH'] = str(self.bin) + os.pathsep + os.environ['PATH']
        self.git('init', '-q')
        self.commit()

    def git(self, *args):
        return subprocess.run([self.env['TEST_GIT'], '-C', str(self.root), *args],
                              env=self.env, check=True, capture_output=True, text=True)

    def commit(self):
        self.git('add', 'agents')
        self.git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                 '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null',
                 'commit', '-qm', 'fixture')

    def snapshot(self):
        return {str(p.relative_to(self.skills)): p.read_bytes()
                for p in self.skills.rglob('*') if p.is_file()}

    def run_updater(self, *args, scenario='', installer=False):
        script = 'install.sh' if installer else 'check-skill-updates.sh'
        return subprocess.run(['bash', str(self.agents / script), *args], cwd=self.root,
                              env=dict(self.env, TEST_SCENARIO=scenario),
                              capture_output=True, text=True, timeout=20)

    def change_remote(self):
        (self.remote / 'skills/ce-code-review/reference.md').write_text('new\n')
        (self.remote / 'skills/ce-code-review/obsolete.md').unlink()

    def test_check_equal_and_changed_never_writes(self):
        before = self.snapshot()
        result = self.run_updater('--check-updates', installer=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count('up to date'), 2)
        self.change_remote()
        result = self.run_updater('--check-updates', installer=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('differs from upstream', result.stdout)
        self.assertEqual(self.snapshot(), before)

    def test_invalid_installer_arguments_never_dispatch(self):
        before = self.snapshot()
        for args in (('--check-updates', '--refresh'), ('--check-updates', '--refresh-skills'),
                     ('--refresh-skills', 'extra'), ('--help', 'extra'), ('--unknown',)):
            with self.subTest(args=args):
                self.assertEqual(self.run_updater(*args, installer=True).returncode, 2)
        self.assertFalse(self.calls.exists())
        self.assertEqual(self.snapshot(), before)

    def test_refresh_updates_adds_and_deletes_files(self):
        self.change_remote()
        (self.remote / 'skills/ce-simplify-code/new.md').write_text('added\n')
        (self.root / 'unrelated.txt').write_text('allowed\n')
        result = self.run_updater('--refresh-skills', installer=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.skills / 'ce-code-review/reference.md').read_text(), 'new\n')
        self.assertFalse((self.skills / 'ce-code-review/obsolete.md').exists())
        self.assertTrue((self.skills / 'ce-simplify-code/new.md').exists())
        self.assertEqual(self.run_updater('--refresh').returncode, 2)
        self.commit()
        result = self.run_updater('--refresh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count('up to date'), 2)

    def test_refresh_same_size_and_timestamp(self):
        local = self.skills / 'ce-code-review/reference.md'
        remote = self.remote / 'skills/ce-code-review/reference.md'
        remote.write_text('new\n')
        for path in (local, remote):
            os.utime(path, (1700000000, 1700000000))
        result = self.run_updater('--refresh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(local.read_text(), 'new\n')

    def test_local_changes_are_preserved(self):
        for kind in ('unstaged', 'staged', 'untracked', 'ignored'):
            with self.subTest(kind=kind):
                path = self.skills / 'ce-code-review/reference.md'
                if kind in ('untracked', 'ignored'):
                    path = self.skills / 'ce-code-review/local.md'
                if kind == 'ignored':
                    (self.root / '.git/info/exclude').write_text('local.md\n')
                path.write_text('keep me\n')
                if kind == 'staged':
                    self.git('add', 'agents')
                before = self.snapshot()
                result = self.run_updater('--refresh')
                self.assertEqual(result.returncode, 2, result.stdout)
                self.assertEqual(self.snapshot(), before)
                # Restore only this disposable test repository between scenarios.
                if kind in ('untracked', 'ignored'):
                    path.unlink()
                self.git('restore', '--source=HEAD', '--staged', '--worktree', 'agents')

    def test_fetch_failures_and_missing_source_do_not_write(self):
        self.change_remote()
        before = self.snapshot()
        for scenario in ('offline', 'sparse-fail', 'missing'):
            with self.subTest(scenario=scenario):
                result = self.run_updater('--refresh', scenario=scenario)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(self.snapshot(), before)

    def test_edits_during_download_are_preserved(self):
        self.change_remote()
        before = self.snapshot()
        result = self.run_updater('--refresh', scenario='edit-during-fetch')
        self.assertEqual(result.returncode, 2)
        before['ce-code-review/local.md'] = b'keep me\n'
        self.assertEqual(self.snapshot(), before)
        self.assertNotIn('refreshed', result.stdout)

    def test_recheck_each_destination_before_copying(self):
        self.change_remote()
        (self.remote / 'skills/ce-simplify-code/new.md').write_text('added\n')
        result = self.run_updater('--refresh', scenario='edit-during-first-copy')
        self.assertEqual(result.returncode, 2)
        self.assertIn('ce-simplify-code: refreshed', result.stdout)
        self.assertNotIn('ce-code-review: refreshed', result.stdout)
        self.assertEqual((self.skills / 'ce-code-review/local.md').read_text(), 'keep me\n')
        self.assertEqual((self.skills / 'ce-code-review/reference.md').read_text(), 'old\n')

    def test_copy_failure_or_noop_never_reports_success(self):
        self.change_remote()
        before = self.snapshot()
        for scenario, error in (('copy-fail', 'refresh incomplete'), ('copy-noop', 'verification failed')):
            with self.subTest(scenario=scenario):
                result = self.run_updater('--refresh', scenario=scenario)
                self.assertEqual(result.returncode, 2)
                self.assertIn(error, result.stderr)
                self.assertNotIn('refreshed', result.stdout)
                self.assertEqual(self.snapshot(), before)

    def test_setup_warns_on_network_failure(self):
        before = self.snapshot()
        result = self.run_updater(installer=True, scenario='offline')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Skill update check failed', result.stdout)
        self.assertEqual(self.snapshot(), before)

    def test_both_downloads_have_stall_limits(self):
        result = self.run_updater()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        downloads = [call for call in calls if 'clone' in call or 'sparse-checkout' in call]
        self.assertEqual(len(downloads), 2)
        for call in downloads:
            self.assertIn('http.lowSpeedLimit=1', call)
            self.assertIn('http.lowSpeedTime=60', call)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1].startswith('--mock-'):
        sys.exit(mock_tool(sys.argv[1][7:], sys.argv[2:]))
    unittest.main()
