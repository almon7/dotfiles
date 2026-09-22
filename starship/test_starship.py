#!/usr/bin/env python3
"""Isolated installer and Bash prompt regressions; rendering requires Starship."""

import os
from pathlib import Path
import pty
import select
import shlex
import shutil
import subprocess
import tempfile
import time
import unittest


DIR = Path(__file__).resolve().parent
STARSHIP = shutil.which("starship")
WEZTERM = next((path for path in (
    Path("/Applications/WezTerm.app/Contents/Resources/wezterm.sh"),
    Path("/opt/homebrew/share/wezterm/wezterm.sh"),
    Path("/usr/local/share/wezterm/wezterm.sh"),
    Path("/usr/share/wezterm/wezterm.sh"),
) if path.is_file()), None)


class StarshipTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="starship-test-")
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name).resolve()
        self.environment = os.environ.copy()
        for key in ("TMUX", "NVIM", "SSH_CONNECTION", "SSH_CLIENT", "SSH_TTY", "STARSHIP_SHELL"):
            self.environment.pop(key, None)
        self.environment.update(
            HOME=str(self.home), ZDOTDIR=str(self.home), SHELL="/bin/bash",
            STARSHIP_CONFIG=str(DIR / "starship.toml"),
            STARSHIP_CACHE=str(self.home / "cache"), TERM="xterm-256color",
        )

    def run_command(self, *args):
        return subprocess.run(
            args, env=self.environment, cwd=self.home, text=True,
            capture_output=True, check=True,
        ).stdout

    def mock_install_tools(self):
        tools = self.home / "bin"
        tools.mkdir()
        scripts = {
            "brew": '#!/bin/sh\ncase "$1" in\nshellenv) echo : ;;\n--prefix) dirname "$(dirname "$0")" ;;\nesac\n',
            "uname": "#!/bin/sh\necho Darwin\n",
            "starship": '#!/bin/sh\necho "starship_precmd() { :; }"\n',
        }
        for name, contents in scripts.items():
            path = tools / name
            path.write_text(contents)
            path.chmod(0o755)
        self.environment["PATH"] = f"{tools}:{os.environ['PATH']}"

    def test_install_preserves_login_profiles_and_is_idempotent(self):
        self.mock_install_tools()
        for profile in (".bash_profile", ".bash_login", ".profile"):
            with self.subTest(profile=profile):
                path = self.home / profile
                path.write_text("export USER_PROFILE_SETTING=retained\n")
                self.run_command(str(DIR / "install.sh"))
                self.assertIn("# >>> Starship prompt", path.read_text())
                value = self.run_command("/bin/bash", "-l", "-i", "-c", 'printf "%s" "$USER_PROFILE_SETTING"')
                self.assertEqual(value, "retained")
                before = {p: p.read_bytes() for p in self.home.iterdir() if p.is_file()}
                self.run_command(str(DIR / "install.sh"))
                self.assertEqual(before, {p: p.read_bytes() for p in self.home.iterdir() if p.is_file()})
                self.assertEqual((self.home / ".config/starship.toml").resolve(), DIR / "starship.toml")
                path.unlink()

    def test_bash_hook_preserves_scalar_and_array_callbacks(self):
        for definition in ('PROMPT_COMMAND=existing', 'PROMPT_COMMAND=(existing second)'):
            with self.subTest(definition=definition):
                script = f'''
starship() {{ :; }}
existing() {{ printf 'existing\\n'; }}
second() {{ printf 'second\\n'; }}
__wezterm_semantic_precmd() {{ :; }}
PS1=prompt
{definition}
source {shlex.quote(str(DIR / 'init.bash'))}
for callback in "${{PROMPT_COMMAND[@]}}"; do eval "$callback"; done
printf '%s\\n' "$PS1"
'''
                output = self.run_command("/bin/bash", "-c", script).splitlines()
                self.assertEqual(output[:-1], ["existing", "second"] if "second" in definition else ["existing"])
                self.assertIn("prompt", output[-1])
                self.assertEqual(output[-1].count(r"\[\e]133;B\a\]"), 1)

    @unittest.skipUnless(STARSHIP, "install Starship to run real prompt regressions")
    def test_bash_times_commands_not_idle_and_preserves_wezterm(self):
        orders = ["native"] + (["wezterm-first", "starship-first"] if WEZTERM else [])
        for order in orders:
            with self.subTest(order=order):
                init = f"source {shlex.quote(str(DIR / 'init.bash'))}\n"
                integration = f"source {shlex.quote(str(WEZTERM))}\n" if order != "native" else ""
                rc = self.home / ".bashrc"
                rc.write_text(integration + init if order == "wezterm-first" else init + integration)
                pid, fd = pty.fork()
                if pid == 0:
                    os.chdir(self.home)
                    os.execve("/bin/bash", ["/bin/bash", "--noprofile", "--rcfile", str(rc), "-i"], self.environment)
                try:
                    self.read_prompt(fd)
                    # Idle time exceeds the configured two-second threshold.
                    time.sleep(2.2)
                    os.write(fd, b"true\n")
                    immediate = self.read_prompt(fd)
                    self.assertNotRegex(immediate, rb"\x1b\[1;33m[0-9]")
                    os.write(fd, b"sleep 2.1\n")
                    slow = self.read_prompt(fd)
                    self.assertRegex(slow, rb"\x1b\[1;33m[0-9]")
                    time.sleep(2.2)
                    os.write(fd, b"\n")
                    empty = self.read_prompt(fd)
                    self.assertNotRegex(empty, rb"\x1b\[1;33m[0-9]")
                    os.write(fd, b"false\n")
                    failed = self.read_prompt(fd)
                    self.assertIn(b"\x1b[1;31m" + "❯".encode(), failed)
                    if order != "native":
                        for output in (immediate, slow, empty, failed):
                            self.assertIn(b"\x1b]133;B\x07", output)
                finally:
                    os.close(fd)
                    os.waitpid(pid, 0)

    def read_prompt(self, fd):
        output = b""
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            readable, _, _ = select.select([fd], [], [], 0.1)
            if readable:
                output += os.read(fd, 65536)
            elif "❯".encode() in output:
                return output
        self.fail(f"Shell did not produce a prompt: {output!r}")


if __name__ == "__main__":
    unittest.main()
