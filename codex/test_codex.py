#!/usr/bin/env python3
"""Offline regression tests for the Codex settings check and DeepSeek launcher."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib
import unittest


DIR = Path(__file__).resolve().parent


class CodexProfileTests(unittest.TestCase):
    def make_home(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        home = Path(temporary.name)
        bin_dir = home / "mock-bin"
        bin_dir.mkdir()

        # The launcher exports its variable, so nothing should reach it via `env`.
        env_command = bin_dir / "env"
        env_command.write_text("#!/usr/bin/env bash\nprintf 'unexpected env command\\n' >&2\nexit 99\n")
        env_command.chmod(0o755)

        codex = bin_dir / "codex"
        codex.write_text(
            "#!/usr/bin/env bash\n"
            "printf 'key=%s\\n' \"${DEEPSEEK_API_KEY-unset}\"\n"
            "printf 'args='; printf '<%s>' \"$@\"; printf '\\n'\n"
            "exit 23\n"
        )
        codex.chmod(0o755)

        environment = os.environ.copy()
        environment.update(HOME=str(home), PATH=f"{bin_dir}:{environment['PATH']}")
        return home, environment

    def install(self, environment):
        """Run the installer, which is what links the profile the launcher needs."""
        return subprocess.run([DIR / "install.sh"], env=environment, text=True, capture_output=True, check=True)

    def run_launcher(self, environment, *arguments):
        return subprocess.run(
            [DIR / "codex-ds", *arguments],
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )

    def write_key(self, home, contents="test-secret"):
        key_file = home / ".config/codex/deepseek-api-key"
        key_file.parent.mkdir(parents=True, exist_ok=True)
        key_file.write_text(contents)
        key_file.chmod(0o600)
        return key_file

    def test_launcher_exports_the_key_and_forwards_arguments(self):
        home, environment = self.make_home()
        self.write_key(home)
        environment["DEEPSEEK_API_KEY"] = "stale-key"
        self.install(environment)

        result = self.run_launcher(environment, "--continue", "two words")

        self.assertEqual(result.returncode, 23)
        self.assertEqual(
            result.stdout.splitlines(),
            ["key=test-secret", "args=<--profile><deepseek><--continue><two words>"],
        )

    def test_launcher_rejects_missing_and_empty_keys(self):
        home, environment = self.make_home()

        missing = self.run_launcher(environment)
        self.assertEqual(missing.returncode, 1)
        self.assertIn("API key not found", missing.stderr)
        self.assertIn(str(home / ".config/codex/deepseek-api-key"), missing.stderr)
        self.assertIn("codex/README.md", missing.stderr)

        self.write_key(home, "")
        empty = self.run_launcher(environment)
        self.assertEqual(empty.returncode, 1)
        self.assertIn("API key file is empty", empty.stderr)

    def test_launcher_refuses_to_run_without_the_profile(self):
        # Codex treats a missing profile as an empty layer, so the launcher has
        # to catch it: the alternative is silently running the default config.
        home, environment = self.make_home()
        self.write_key(home)

        result = self.run_launcher(environment, "exec", "hi")

        self.assertEqual(result.returncode, 1)
        self.assertIn("DeepSeek profile not found", result.stderr)
        self.assertIn(str(home / ".codex/deepseek.config.toml"), result.stderr)
        self.assertEqual(result.stdout, "")  # the mock codex never ran

    def test_installer_links_the_launcher_profile_and_catalog(self):
        home, environment = self.make_home()
        targets = {
            ".local/bin/codex-ds": "codex-ds",
            ".codex/deepseek.config.toml": "deepseek.config.toml",
            ".codex/deepseek-models.json": "deepseek-models.json",
        }

        first = self.install(environment)

        for target, source in targets.items():
            self.assertEqual((home / target).resolve(), (DIR / source).resolve())
            # resolve() is non-strict: it cannot tell a link from one that
            # points at nothing. exists() follows the link and can.
            self.assertTrue((home / target).exists(), f"{target} does not resolve")
        self.assertIn("Linking", first.stdout)

        merged = (home / ".codex/config.toml").read_text()
        second = self.install(environment)
        self.assertIn("Already linked", second.stdout)
        self.assertEqual((home / ".codex/config.toml").read_text(), merged)  # a rerun rewrites nothing
        self.assertIn("is already set to", second.stderr)

    def test_installer_refuses_an_incomplete_checkout(self):
        # link_config does not check its sources, and a link to a missing one
        # reads as already correct on every later run. Run a copy of the
        # component so the real checkout is never the thing being damaged.
        home, environment = self.make_home()
        sandbox = home / "tree"
        (sandbox / "codex").mkdir(parents=True)
        shutil.copy(DIR.parent / "install-lib.sh", sandbox / "install-lib.sh")
        for name in ("codex-ds", "deepseek.config.toml", "deepseek-models.json", "config.toml", "install.sh"):
            shutil.copy(DIR / name, sandbox / "codex" / name)
        (sandbox / "codex" / "install.sh").chmod(0o755)
        (sandbox / "codex" / "deepseek-models.json").unlink()

        result = subprocess.run(
            [sandbox / "codex/install.sh"], env=environment, text=True, capture_output=True, check=False
        )

        self.assertEqual(result.returncode, 1)
        self.assertIn("is missing; this checkout is incomplete", result.stdout)
        self.assertFalse((home / ".codex/deepseek.config.toml").exists())

    def test_installer_backs_up_a_file_already_at_a_link_target(self):
        home, environment = self.make_home()
        target = home / ".codex/deepseek.config.toml"
        target.parent.mkdir(parents=True)
        target.write_text("mine\n")

        self.install(environment)

        backups = list(target.parent.glob("deepseek.config.toml.bak.*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), "mine\n")
        self.assertEqual(target.resolve(), (DIR / "deepseek.config.toml").resolve())

    def test_installer_merges_settings_and_reports_conflicts(self):
        home, environment = self.make_home()
        settings = home / ".codex/config.toml"
        settings.parent.mkdir(parents=True)
        settings.write_text('model = "something-else"\n\n[tui]\nvim_mode_default = true\n')

        result = self.install(environment)
        installed = settings.read_text()

        self.assertIn('model = "something-else"', installed)  # a local change is not ours to undo
        self.assertIn("model_auto_compact_token_limit = 900000", installed)  # absent, so inserted
        self.assertIn("model is \"something-else\" here", result.stderr)  # reported on stderr, not stdout

    def test_installer_notes_a_missing_codex_without_failing(self):
        _, environment = self.make_home()
        environment["PATH"] = "/usr/bin:/bin"  # no codex, and no ~/.local/bin

        result = self.install(environment)

        self.assertEqual(result.returncode, 0)
        self.assertIn("Codex itself is not installed here", result.stdout)
        self.assertIn("is not on PATH", result.stdout)

    def test_profile_points_at_the_linked_catalog_and_a_real_model(self):
        profile = tomllib.loads((DIR / "deepseek.config.toml").read_text())
        catalog = json.loads((DIR / "deepseek-models.json").read_text())
        models = {model["slug"]: model for model in catalog["models"]}

        # This string and the installer's link target are kept in step by
        # nothing else, so assert it literally.
        self.assertEqual(profile["model_catalog_json"], "~/.codex/deepseek-models.json")
        self.assertIn(profile["model"], models)

        efforts = [level["effort"] for level in models[profile["model"]]["supported_reasoning_levels"]]
        self.assertIn(profile["model_reasoning_effort"], efforts)

    def test_catalog_is_complete_and_self_consistent(self):
        catalog = json.loads((DIR / "deepseek-models.json").read_text())

        self.assertEqual([model["slug"] for model in catalog["models"]], ["deepseek-flash", "deepseek-v4-pro"])
        for model in catalog["models"]:
            # Codex accepts either field; shipping both is what DeepSeek's own
            # installer does, and they are byte-identical today.
            self.assertEqual(model["base_instructions"], model["model_messages"]["instructions_template"])

    def test_profile_declares_the_provider_and_its_env_key(self):
        profile = tomllib.loads((DIR / "deepseek.config.toml").read_text())
        provider = profile["model_providers"][profile["model_provider"]]

        self.assertEqual(provider["env_key"], "DEEPSEEK_API_KEY")
        self.assertEqual(provider["wire_api"], "responses")
        self.assertEqual(profile["model_provider"], "deepseek")


if __name__ == "__main__":
    unittest.main()
