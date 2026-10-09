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


EVERYINC = 'EveryInc/compound-engineering-plugin'
MATTPOCOCK = 'mattpocock/skills'
ENGINEERING_SKILLS = (
    'ask-matt', 'diagnosing-bugs', 'grill-with-docs', 'triage',
    'improve-codebase-architecture', 'setup-matt-pocock-skills', 'tdd',
    'to-spec', 'to-tickets', 'wayfinder', 'implement', 'implement-spec',
    'prototype', 'research', 'domain-modeling', 'codebase-design',
    'code-review', 'pr', 'retro', 'wizard',
)
PRODUCTIVITY_SKILLS = (
    'grill-me', 'grilling', 'handoff', 'teach', 'to-questionnaire',
    'wait-what', 'writing-for-agents',
)


def mock_tool(tool, args):
    """Replace downloads and inject failures; delegate local work to real tools."""
    with open(os.environ['TEST_CALLS'], 'a') as log:
        log.write(json.dumps([tool, *args]) + '\n')
    scenario = os.environ.get('TEST_SCENARIO', '')
    local = Path(os.environ['TEST_ROOT']) / 'agents/skills'
    if tool == 'git':
        command = list(args)
        working = Path.cwd()
        while command and command[0] in ('-c', '-C'):
            if command[0] == '-C':
                working = Path(command[1])
            command = command[2:]
        if command[0] == 'clone':
            second_source = args[-2] == f'https://github.com/{MATTPOCOCK}.git'
            if scenario == 'offline' or (scenario == 'second-offline' and second_source):
                return 1
            remote = json.loads(os.environ['TEST_REMOTES'])[args[-2]]
            shutil.copytree(remote, args[-1])
            if scenario == 'missing' and not second_source:
                (Path(args[-1]) / 'skills/ce-code-review/SKILL.md').unlink()
            if scenario == 'second-missing' and second_source:
                (Path(args[-1]) / 'skills/engineering/tdd/SKILL.md').unlink()
            return 0
        if command[0] == 'sparse-checkout':
            second_source = (working / '.fixture-repository').read_text() == MATTPOCOCK
            if scenario == 'sparse-fail' or (scenario == 'second-sparse-fail' and second_source):
                return 1
            if scenario == 'edit-during-fetch':
                (local / 'ce-code-review/local.md').write_text('keep me\n')
            if scenario == 'edit-during-second-fetch' and second_source:
                (local / 'tdd/local.md').write_text('keep me\n')
            return 0
        if command[0] == 'rev-parse':
            print((working / '.fixture-revision').read_text())
            return 0
    elif scenario in ('copy-fail', 'copy-noop'):
        return 23 if scenario == 'copy-fail' else 0
    result = subprocess.run([os.environ['TEST_' + tool.upper()], *args])
    if tool == 'rsync' and scenario == 'edit-during-first-copy':
        (local / 'ce-code-review/local.md').write_text('keep me\n')
    if tool == 'rsync' and scenario == 'edit-second-during-first-copy':
        (local / 'tdd/local.md').write_text('keep me\n')
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
        self.source_paths = {
            EVERYINC: ['skills/ce-simplify-code', 'skills/ce-code-review'],
            MATTPOCOCK: [f'skills/engineering/{name}' for name in ENGINEERING_SKILLS]
                       + [f'skills/productivity/{name}' for name in PRODUCTIVITY_SKILLS],
        }
        self.remote = self.root / 'remote'
        self.matt_remote = self.root / 'matt-remote'
        remotes = {}
        for repository, remote, revision in ((EVERYINC, self.remote, 'abcdef0'),
                                              (MATTPOCOCK, self.matt_remote, '1234567')):
            remote.mkdir()
            (remote / '.fixture-repository').write_text(repository)
            (remote / '.fixture-revision').write_text(revision)
            remotes[f'https://github.com/{repository}.git'] = str(remote)
            for source_path in self.source_paths[repository]:
                folder = self.skills / Path(source_path).name
                folder.mkdir(parents=True)
                (folder / 'SKILL.md').write_text(f'fixture {source_path}\n')
                (folder / 'reference.md').write_text('old\n')
                if folder.name in ('ce-code-review', 'tdd'):
                    (folder / 'obsolete.md').write_text('obsolete\n')
                shutil.copytree(folder, remote / source_path)
        self.calls = self.root / 'calls.jsonl'
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_CONFIG_SYSTEM=os.devnull, GIT_CONFIG_NOSYSTEM='1',
                        GIT_CONFIG_COUNT='0', TEST_ROOT=str(self.root),
                        TEST_REMOTES=json.dumps(remotes), TEST_CALLS=str(self.calls),
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

    def recorded_calls(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()]

    def test_check_equal_and_changed_never_writes(self):
        before = self.snapshot()
        result = self.run_updater('--check-updates', installer=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count('up to date'), 29)
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
        self.assertEqual(result.stdout.count('up to date'), 29)

    def test_refresh_same_size_and_timestamp(self):
        local = self.skills / 'ce-code-review/reference.md'
        remote = self.remote / 'skills/ce-code-review/reference.md'
        remote.write_text('new\n')
        for path in (local, remote):
            os.utime(path, (1700000000, 1700000000))
        result = self.run_updater('--refresh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(local.read_text(), 'new\n')

    def test_nested_sources_refresh_flat_destinations_and_report_their_revisions(self):
        self.change_remote()
        tdd = self.matt_remote / 'skills/engineering/tdd'
        (tdd / 'reference.md').write_text('new\n')
        (tdd / 'obsolete.md').unlink()
        (tdd / 'scripts').mkdir()
        (tdd / 'scripts/check.sh').write_text('new script\n')
        (self.matt_remote / 'skills/productivity/grill-me/reference.md').write_text('new\n')
        # Upstream additions outside the explicit mapping are not installed.
        unselected = self.matt_remote / 'skills/engineering/unselected'
        unselected.mkdir()
        (unselected / 'SKILL.md').write_text('do not install\n')
        before = self.snapshot()
        check = self.run_updater()
        self.assertEqual(check.returncode, 0, check.stderr)
        self.assertEqual(self.snapshot(), before)
        result = self.run_updater('--refresh')
        self.assertEqual(result.returncode, 0, result.stderr)
        for output in (check.stdout, result.stdout):
            self.assertIn(f'https://github.com/{EVERYINC}/tree/abcdef0/skills/ce-code-review', output)
            self.assertIn(f'https://github.com/{MATTPOCOCK}/tree/1234567/skills/engineering/tdd', output)
            self.assertIn(f'https://github.com/{MATTPOCOCK}/tree/1234567/skills/productivity/grill-me', output)
        self.assertEqual((self.skills / 'tdd/reference.md').read_text(), 'new\n')
        self.assertFalse((self.skills / 'tdd/obsolete.md').exists())
        self.assertEqual((self.skills / 'tdd/scripts/check.sh').read_text(), 'new script\n')
        self.assertEqual((self.skills / 'grill-me/reference.md').read_text(), 'new\n')
        self.assertFalse((self.skills / 'engineering').exists())
        self.assertFalse((self.skills / 'productivity').exists())
        self.assertFalse((self.skills / 'unselected').exists())

    def test_local_changes_are_preserved(self):
        for skill in ('ce-code-review', 'tdd'):
            for kind in ('unstaged', 'staged', 'untracked', 'ignored'):
                with self.subTest(skill=skill, kind=kind):
                    path = self.skills / skill / 'reference.md'
                    if kind in ('untracked', 'ignored'):
                        path = self.skills / skill / 'local.md'
                    if kind == 'ignored':
                        (self.root / '.git/info/exclude').write_text('local.md\n')
                    path.write_text('keep me\n')
                    if kind == 'staged':
                        self.git('add', 'agents')
                    before = self.snapshot()
                    result = self.run_updater('--refresh')
                    self.assertEqual(result.returncode, 2, result.stdout)
                    self.assertEqual(self.snapshot(), before)
                    self.assertFalse(any('clone' in call for call in self.recorded_calls()))
                    # Restore only this disposable test repository between scenarios.
                    if kind in ('untracked', 'ignored'):
                        path.unlink()
                    self.git('restore', '--source=HEAD', '--staged', '--worktree', 'agents')
                    (self.root / '.git/info/exclude').write_text('')

    def test_fetch_failures_and_missing_source_do_not_write(self):
        self.change_remote()
        before = self.snapshot()
        for scenario in ('offline', 'sparse-fail', 'missing',
                         'second-offline', 'second-sparse-fail', 'second-missing'):
            with self.subTest(scenario=scenario):
                result = self.run_updater('--refresh', scenario=scenario)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(self.snapshot(), before)
                self.assertFalse(any(call[0] == 'rsync' for call in self.recorded_calls()))

    def test_edits_during_download_are_preserved(self):
        self.change_remote()
        before = self.snapshot()
        result = self.run_updater('--refresh', scenario='edit-during-fetch')
        self.assertEqual(result.returncode, 2)
        before['ce-code-review/local.md'] = b'keep me\n'
        self.assertEqual(self.snapshot(), before)
        self.assertNotIn('refreshed', result.stdout)

    def test_edits_during_second_download_prevent_all_copies(self):
        self.change_remote()
        before = self.snapshot()
        result = self.run_updater('--refresh', scenario='edit-during-second-fetch')
        self.assertEqual(result.returncode, 2)
        before['tdd/local.md'] = b'keep me\n'
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(any(call[0] == 'rsync' for call in self.recorded_calls()))

    def test_recheck_each_destination_before_copying(self):
        self.change_remote()
        (self.remote / 'skills/ce-simplify-code/new.md').write_text('added\n')
        result = self.run_updater('--refresh', scenario='edit-during-first-copy')
        self.assertEqual(result.returncode, 2)
        self.assertIn('ce-simplify-code: refreshed', result.stdout)
        self.assertNotIn('ce-code-review: refreshed', result.stdout)
        self.assertEqual((self.skills / 'ce-code-review/local.md').read_text(), 'keep me\n')
        self.assertEqual((self.skills / 'ce-code-review/reference.md').read_text(), 'old\n')

    def test_recheck_second_repository_destination_before_copying(self):
        self.change_remote()
        (self.matt_remote / 'skills/engineering/tdd/reference.md').write_text('new\n')
        result = self.run_updater('--refresh', scenario='edit-second-during-first-copy')
        self.assertEqual(result.returncode, 2)
        self.assertIn('ce-code-review: refreshed', result.stdout)
        self.assertNotIn('tdd: refreshed', result.stdout)
        self.assertEqual((self.skills / 'tdd/local.md').read_text(), 'keep me\n')
        self.assertEqual((self.skills / 'tdd/reference.md').read_text(), 'old\n')

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

    def test_each_repository_is_fetched_once_with_mapped_paths_and_stall_limits(self):
        result = self.run_updater()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.recorded_calls()
        downloads = [call for call in calls if 'clone' in call or 'sparse-checkout' in call]
        self.assertEqual(len(downloads), 4)
        for call in downloads:
            self.assertIn('http.lowSpeedLimit=1', call)
            self.assertIn('http.lowSpeedTime=60', call)
        clones = [call for call in downloads if 'clone' in call]
        self.assertCountEqual([call[-2] for call in clones],
                              [f'https://github.com/{repository}.git' for repository in self.source_paths])
        for repository, source_paths in self.source_paths.items():
            clone = next(call for call in clones if call[-2] == f'https://github.com/{repository}.git')
            sparse = [call for call in downloads if 'sparse-checkout' in call
                      and call[call.index('-C') + 1] == clone[-1]]
            self.assertEqual(len(sparse), 1)
            self.assertCountEqual(sparse[0][sparse[0].index('set') + 1:], source_paths)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1].startswith('--mock-'):
        sys.exit(mock_tool(sys.argv[1][7:], sys.argv[2:]))
    unittest.main()
