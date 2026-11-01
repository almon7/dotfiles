"""Check real Diffview rendering in a disposable repository and terminal."""

import fcntl
import json
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import tempfile
import termios
import time


root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="diffview-comments-") as directory:
    fixture = Path(directory)
    env = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1")

    def git(*args):
        subprocess.run(["git", *args], cwd=fixture, env=env, check=True, capture_output=True)

    git("init", "-q")
    git("config", "user.name", "Fixture")
    git("config", "user.email", "fixture@example.invalid")
    for word in ("old", "new"):
        lines = [f'value = "{word}"', f"# {word} standalone", "def f():", f'    """{word} documentation', "    unchanged documentation", '    """', f"    return value # {word} inline", "", "# stable comment"]
        lines += [""] * 40 + [f"# {word} distant", ""]
        (fixture / "sample.py").write_text("\n".join(lines))
        (fixture / "second.py").write_text("header = 1\nheader2 = 2\n" + "\n".join(lines))
        git("add", ".")
        git("-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-qm", word)
    env.update(TERM="xterm-256color", DIFFVIEW_TEST_ROOT=str(root), DIFFVIEW_TEST_DIR=directory, XDG_CACHE_HOME=str(fixture / "cache"), NVIM_LOG_FILE=str(fixture / "nvim.log"))
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 35, 160, 0, 0))
    command = "lua dofile(vim.env.DIFFVIEW_TEST_ROOT .. '/nvim/tests/diffview_comments.lua')"
    process = subprocess.Popen(["nvim", "-n", "-u", "NONE", "-i", "NONE", "-c", command], stdin=slave, stdout=slave, stderr=slave, env=env)
    os.close(slave)
    try:
        deadline = time.monotonic() + 15
        while process.poll() is None and time.monotonic() < deadline:
            if select.select([master], [], [], 0.1)[0]:
                try:
                    os.read(master, 65536)
                except OSError:
                    break
        if process.poll() is None:
            process.kill()
        process.wait()
    finally:
        os.close(master)
    assert process.returncode == 0, f"Neovim exited with status {process.returncode}"
    result = json.loads((fixture / "result.json").read_text())
    assert result["ok"], result["error"]
    print("PASS: Diffview comment colours, reload, scroll, file switch, edits, window isolation, search, references and cleanup")
