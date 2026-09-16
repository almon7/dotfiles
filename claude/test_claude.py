#!/usr/bin/env python3
"""Offline regression tests for the Claude Code profile component."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


DIR = Path(__file__).resolve().parent


class ClaudeProfileTests(unittest.TestCase):
    def make_home(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        home = Path(temporary.name)
        bin_dir = home / "mock-bin"
        bin_dir.mkdir()

        brew = bin_dir / "brew"
        brew.write_text(
            "#!/usr/bin/env bash\n"
            "printf '%s\\n' \"$*\" >> \"$BREW_LOG\"\n"
            "case \"${1:-}\" in\n"
            "  list|outdated) exit 0 ;;\n"
            "  *) exit 0 ;;\n"
            "esac\n"
        )
        brew.chmod(0o755)

        uname = bin_dir / "uname"
        uname.write_text("#!/usr/bin/env bash\nprintf '%s\\n' \"${MOCK_UNAME:-Linux}\"\n")
        uname.chmod(0o755)

        env_command = bin_dir / "env"
        env_command.write_text("#!/usr/bin/env bash\nprintf 'unexpected env command\\n' >&2\nexit 99\n")
        env_command.chmod(0o755)

        claude = bin_dir / "claude"
        claude.write_text(
            "#!/usr/bin/env bash\n"
            "printf 'base=%s\\n' \"${ANTHROPIC_BASE_URL-}\"\n"
            "printf 'token=%s\\n' \"${ANTHROPIC_AUTH_TOKEN-}\"\n"
            "printf 'api-key=%s\\n' \"${ANTHROPIC_API_KEY-unset}\"\n"
            "printf 'model=%s\\n' \"${ANTHROPIC_MODEL-}\"\n"
            "printf 'opus=%s\\n' \"${ANTHROPIC_DEFAULT_OPUS_MODEL-}\"\n"
            "printf 'sonnet=%s\\n' \"${ANTHROPIC_DEFAULT_SONNET_MODEL-}\"\n"
            "printf 'haiku=%s\\n' \"${ANTHROPIC_DEFAULT_HAIKU_MODEL-}\"\n"
            "printf 'subagent=%s\\n' \"${CLAUDE_CODE_SUBAGENT_MODEL-}\"\n"
            "printf 'effort=%s\\n' \"${CLAUDE_CODE_EFFORT_LEVEL-}\"\n"
            "printf 'compact=%s\\n' \"${CLAUDE_CODE_AUTO_COMPACT_WINDOW-}\"\n"
            "printf 'args='; printf '<%s>' \"$@\"; printf '\\n'\n"
            "exit 23\n"
        )
        claude.chmod(0o755)

        environment = os.environ.copy()
        environment.update(
            HOME=str(home),
            PATH=f"{bin_dir}:{environment['PATH']}",
            SHELL="/bin/bash",
            BREW_LOG=str(home / "brew.log"),
        )
        return home, environment

    def run_installer(self, environment, *, check=True):
        return subprocess.run([DIR / "install.sh"], env=environment, text=True, capture_output=True, check=check)

    def test_deepseek_wrapper_scopes_configuration_and_forwards_arguments(self):
        home, environment = self.make_home()
        key_file = home / ".config/claude/deepseek-api-key"
        key_file.parent.mkdir(parents=True)
        key_file.write_text("test-secret")
        key_file.chmod(0o600)
        environment["ANTHROPIC_API_KEY"] = "stale-key"

        result = subprocess.run(
            [DIR / "claude-ds", "--continue", "two words"],
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(result.returncode, 23)
        self.assertEqual(
            result.stdout.splitlines(),
            [
                "base=https://api.deepseek.com/anthropic",
                "token=test-secret",
                "api-key=unset",
                "model=deepseek-flash[1m]",
                "opus=deepseek-flash[1m]",
                "sonnet=deepseek-flash[1m]",
                "haiku=deepseek-flash",
                "subagent=deepseek-flash",
                "effort=max",
                "compact=786432",
                "args=<--continue><two words>",
            ],
        )

    def test_deepseek_wrapper_rejects_missing_and_empty_keys(self):
        home, environment = self.make_home()

        missing = subprocess.run([DIR / "claude-ds"], env=environment, text=True, capture_output=True, check=False)
        self.assertEqual(missing.returncode, 1)
        self.assertIn("API key not found", missing.stderr)

        key_file = home / ".config/claude/deepseek-api-key"
        key_file.parent.mkdir(parents=True)
        key_file.touch()
        empty = subprocess.run([DIR / "claude-ds"], env=environment, text=True, capture_output=True, check=False)
        self.assertEqual(empty.returncode, 1)
        self.assertIn("API key file is empty", empty.stderr)

    def test_status_line_displays_model_and_context(self):
        status_input = json.dumps(
            {
                "model": {"display_name": "deepseek-flash[1m]"},
                "context_window": {"used_percentage": 12.9},
            }
        )
        result = subprocess.run(
            [DIR / "statusline.sh"],
            input=status_input,
            text=True,
            capture_output=True,
            check=True,
        )
        self.assertEqual(result.stdout, "[deepseek-flash[1m]] 12% context\n")

    def test_installer_merges_settings_and_is_idempotent(self):
        home, environment = self.make_home()
        settings = home / ".claude/settings.json"
        settings.parent.mkdir(parents=True)
        settings.write_text('{"theme":"dark"}\n')

        first = self.run_installer(environment)
        installed = json.loads(settings.read_text())
        self.assertEqual(installed["theme"], "dark")
        self.assertEqual(installed["statusLine"], json.loads((DIR / "settings.json").read_text())["statusLine"])
        self.assertIn("Added statusLine", first.stdout)
        self.assertEqual((home / ".local/bin/claude-ds").resolve(), (DIR / "claude-ds").resolve())
        self.assertEqual((home / ".claude/statusline.sh").resolve(), (DIR / "statusline.sh").resolve())
        self.assertIn("list --formula jq", (home / "brew.log").read_text().splitlines())

        second = self.run_installer(environment)
        self.assertIn("statusLine is already configured", second.stdout)

    def test_installer_creates_settings_on_a_fresh_home(self):
        home, environment = self.make_home()
        settings = home / ".claude/settings.json"

        first = self.run_installer(environment)
        created = settings.read_text()
        self.assertEqual(json.loads(created), json.loads((DIR / "settings.json").read_text()))
        self.assertIn("Creating", first.stdout)

        second = self.run_installer(environment)
        self.assertEqual(settings.read_text(), created)
        self.assertIn("statusLine is already configured", second.stdout)

    def test_installer_rejects_unsupported_operating_system(self):
        home, environment = self.make_home()
        environment["MOCK_UNAME"] = "Plan9"

        result = self.run_installer(environment, check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Only macOS and Linux are supported", result.stdout)
        self.assertFalse((home / ".claude/settings.json").exists())

    def test_installer_preserves_conflicting_settings(self):
        home, environment = self.make_home()
        settings = home / ".claude/settings.json"
        settings.parent.mkdir(parents=True)
        original = '{"statusLine":{"type":"command","command":"custom"}}\n'
        settings.write_text(original)

        result = self.run_installer(environment)
        self.assertIn("already set differently", result.stdout)
        self.assertEqual(settings.read_text(), original)

    def test_installer_preserves_malformed_settings(self):
        for original in ("not json\n", "", "{}\n{}\n", "[]\n"):
            with self.subTest(original=original):
                home, environment = self.make_home()
                settings = home / ".claude/settings.json"
                settings.parent.mkdir(parents=True)
                settings.write_text(original)

                result = self.run_installer(environment, check=False)
                self.assertEqual(result.returncode, 1)
                self.assertIn("does not contain exactly one JSON object", result.stdout)
                self.assertEqual(settings.read_text(), original)


if __name__ == "__main__":
    unittest.main()
