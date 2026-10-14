#!/usr/bin/env python3
"""Exercise managed review cleanup in disposable Git repositories and tmux servers."""

import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parent
NVIM = shutil.which("nvim")
TOOLS = all(shutil.which(name) for name in ("nvim", "git", "tmux", "lsof", "ps"))


@unittest.skipUnless(TOOLS, "nvim, git, tmux, lsof and ps are required")
class ReviewTmuxTests(unittest.TestCase):
    def run_command(self, args, *, cwd=None, env=None, check=True):
        result = subprocess.run(
            args, cwd=cwd or self.temp, env=env or self.env, check=False,
            text=True, capture_output=True, timeout=15,
        )
        if check and result.returncode:
            self.fail(f"{shlex.join(map(str, args))} failed:\n{result.stderr}")
        return result

    def tmux(self, *args):
        result = self.run_command(["tmux", "-f", "/dev/null", "-S", str(self.socket), *args])
        self.assertEqual(result.stderr, "", f"tmux reported an error for {args}")
        return result.stdout.strip()

    def git(self, *args):
        return self.run_command(["git", "-C", str(self.repo), *args]).stdout.strip()

    def wait_for(self, predicate, explanation, timeout=20):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.05)
        panes = self.tmux("list-panes", "-a", "-F", "#{pane_id}")
        output = "\n".join(
            self.tmux("capture-pane", "-p", "-S", "-100", "-t", pane)
            for pane in panes.splitlines()
        )
        record = Path(self.ctx["record"]) if hasattr(self, "ctx") else None
        context = record.read_text() if record and record.exists() else "No session record"
        self.fail(f"Timed out waiting for {explanation}\n{self.notices()}\n{context}\n{output}")

    def pane_exists(self, pane):
        return pane in self.tmux("list-panes", "-a", "-F", "#{pane_id}").splitlines()

    def setUp(self):
        # Keep Unix-domain socket paths below macOS's 104-byte limit.
        directory = tempfile.TemporaryDirectory(prefix="nvim-review-", dir="/tmp")
        self.addCleanup(directory.cleanup)
        self.temp = Path(directory.name).resolve()
        self.socket = self.temp / "tmux.sock"
        self.repo = self.temp / "repo"
        self.bin = self.temp / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=f"{self.bin}{os.pathsep}{os.environ['PATH']}")
        self.env.update(GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null")
        self.env.pop("TMUX", None)
        self.env.pop("TMUX_PANE", None)
        self.env["REVIEW_TEST_DIR"] = str(self.temp)
        self.env["REVIEW_TEST_CONFIG"] = str(ROOT)
        self.env["REVIEW_TEST_REAL_NVIM"] = str(NVIM)

        docker = self.bin / "docker"
        docker.write_text(
            "#!/usr/bin/env python3\n"
            "import os\nfrom pathlib import Path\nimport sys\n"
            "root = Path(os.environ['REVIEW_TEST_DIR'])\n"
            "counter = root / 'docker-count'\n"
            "count = int(counter.read_text()) + 1 if counter.exists() else 1\n"
            "counter.write_text(str(count))\n"
            "if (root / 'fail-cleanup').exists() and count > 1:\n"
            "    print('fixture Docker became unavailable', file=sys.stderr)\n"
            "    sys.exit(1)\n"
            "assert sys.argv[1:] == ['ps', '-aq'], sys.argv\n"
        )
        docker.chmod(0o700)
        self.init = self.temp / "init.lua"
        self.init.write_text(
            "vim.opt.rtp:prepend(vim.env.REVIEW_TEST_CONFIG)\n"
            "vim.opt.swapfile = false\nvim.opt.shadafile = 'NONE'\n"
            "vim.g.mapleader = ' '\n"
            "vim.notify = function(message)\n"
            "  vim.fn.writefile({ message }, vim.env.REVIEW_TEST_DIR .. '/notices', 'a')\n"
            "end\n"
            "package.loaded.diffview = { open = function()\n"
            "  vim.cmd.edit('file.txt')\n"
            "  vim.fn.writefile({ tostring(vim.uv.os_getpid()) }, vim.env.REVIEW_TEST_DIR .. '/ready')\n"
            "end }\n"
            "for _, mapping in ipairs(require('plugins.diffview')[1].keys) do\n"
            "  if mapping[1] == '<leader>gvq' then\n"
            "    vim.keymap.set('n', mapping[1], mapping[2])\n"
            "  end\n"
            "end\n"
        )
        self.shim = self.bin / "review-nvim"
        self.shim.write_text(
            '#!/usr/bin/env bash\n'
            'if [[ ${1:-} == -l ]]; then exec "$REVIEW_TEST_REAL_NVIM" "$@"; fi\n'
            'exec "$REVIEW_TEST_REAL_NVIM" -u "$REVIEW_TEST_DIR/init.lua" -i NONE "$@"\n'
        )
        self.shim.chmod(0o700)
        self.main = self.tmux(
            "new-session", "-d", "-s", "review-test", "-x", "120", "-y", "35",
            "-P", "-F", "#{pane_id}", "-c", str(self.temp), "sleep 300",
        )
        self.addCleanup(self.stop_server)
        self.extra = self.tmux(
            "split-window", "-h", "-t", self.main, "-P", "-F", "#{pane_id}",
            "-c", str(self.temp), "sleep 300",
        )
        server_pid = self.tmux("display-message", "-p", "#{pid}")
        self.env["TMUX"] = f"{self.socket},{server_pid},0"
        self.run_command(["git", "init", "-b", "main", str(self.repo)])
        (self.repo / "file.txt").write_text("original\n")
        self.git("add", "file.txt")
        self.git("-c", "user.name=Test", "-c", "user.email=test@example.com",
                 "-c", "commit.gpgsign=false", "commit", "-m", "base")
        self.git("remote", "add", "origin", "https://github.com/example/api.git")
        self.head = self.git("rev-parse", "HEAD")
        self.git("update-ref", "refs/diffview/preserved", self.head)
        self.pr = {
            "identity": "github.com/example/api", "url": "https://github.com/example/api/pull/42",
            "number": 42, "headRefOid": self.head,
        }
        self.reserve = self.temp / "reserve.lua"
        self.reserve.write_text(
            "vim.opt.rtp:prepend(vim.env.REVIEW_TEST_CONFIG)\n"
            "local expand = vim.fn.expand\n"
            "vim.fn.expand = function(value, ...)\n"
            "  return value == '~/reviews' and vim.env.REVIEW_TEST_DIR .. '/reviews' or expand(value, ...)\n"
            "end\n"
            "local session = require('config.review_session')\n"
            "local pr = vim.json.decode(vim.env.REVIEW_TEST_PR)\n"
            "local ctx = session.reserve(vim.env.REVIEW_TEST_DIR .. '/repo', pr)\n"
            "if not ctx then print('FOCUSED'); return end\n"
            "local result = vim.system({ 'git', '-C', vim.env.REVIEW_TEST_DIR .. '/repo',\n"
            "  'worktree', 'add', '-b', ctx.branch, ctx.path, ctx.head }):wait()\n"
            "assert(result.code == 0, result.stderr)\n"
            "ctx.nvim = vim.env.REVIEW_TEST_DIR .. '/bin/review-nvim'\n"
            "session.prepare(ctx, ctx.head)\n"
            "vim.fn.writefile({ vim.json.encode(ctx) }, vim.env.REVIEW_TEST_DIR .. '/context.json')\n"
        )
        self.env["REVIEW_TEST_PR"] = json.dumps(self.pr)
        self.run_command([NVIM, "-l", str(self.reserve)])
        self.ctx = json.loads((self.temp / "context.json").read_text())
        self.worktree = Path(self.ctx["path"])
        self.git("config", f"branch.{self.ctx['branch']}.diffview-pr", self.pr["url"])
        self.review = self.tmux(
            "new-window", "-t", "review-test", "-n", "managed-review", "-P", "-F", "#{pane_id}",
            "-c", str(self.temp), shlex.join([
                "bash", str(ROOT / "review-session.sh"), str(self.shim), self.ctx["record"],
            ]),
        )
        self.wait_for(lambda: (self.temp / "ready").exists(), "managed Neovim to start")

    def stop_server(self):
        self.run_command(["tmux", "-S", str(self.socket), "kill-server"], check=False)
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if self.run_command(["tmux", "-S", str(self.socket), "has-session"], check=False).returncode:
                return
            time.sleep(0.05)
        self.fail("Isolated test tmux server did not stop")

    def command(self, command):
        self.tmux("send-keys", "-t", self.review, "Escape")
        self.tmux("send-keys", "-t", self.review, "-l", ":" + command)
        self.tmux("send-keys", "-t", self.review, "Enter")

    def close_review(self):
        self.tmux("send-keys", "-t", self.review, "Escape")
        self.tmux("send-keys", "-t", self.review, "-l", " gvq")

    def notices(self):
        path = self.temp / "notices"
        return path.read_text() if path.exists() else ""

    def assert_other_panes_preserved(self):
        self.assertTrue(self.pane_exists(self.main))
        self.assertTrue(self.pane_exists(self.extra))
        self.assertEqual(self.git("rev-parse", "refs/diffview/preserved"), self.head)

    def test_clean_review_removes_worktree_and_branch(self):
        # A non-terminal editor child models a language-server process using the worktree.
        self.command(
            "lua local job = vim.fn.jobstart({'sleep', '300'}); "
            "vim.fn.writefile({tostring(vim.fn.jobpid(job))}, vim.env.REVIEW_TEST_DIR .. '/child.pid')"
        )
        self.wait_for(lambda: (self.temp / "child.pid").exists(), "editor child to start")
        self.close_review()
        self.wait_for(lambda: not self.pane_exists(self.review), "clean review pane to close")
        self.assertFalse(self.worktree.exists())
        self.assertEqual(self.git("branch", "--list", self.ctx["branch"]), "")
        self.assertFalse(Path(self.ctx["state_dir"]).exists())
        self.assert_other_panes_preserved()

    def test_duplicate_open_focuses_existing_pane(self):
        self.tmux("select-window", "-t", self.main)
        before = self.tmux("list-panes", "-a", "-F", "#{pane_id}")
        result = self.run_command([NVIM, "-l", str(self.reserve)])
        self.assertIn("FOCUSED", result.stdout + result.stderr)
        self.assertEqual(self.tmux("display-message", "-p", "#{pane_id}"), self.review)
        self.assertEqual(self.tmux("list-panes", "-a", "-F", "#{pane_id}"), before)
        self.assertTrue(self.worktree.exists())

    def test_manual_exit_retains_worktree(self):
        self.command("qa")
        self.wait_for(lambda: not self.pane_exists(self.review), "manual editor exit")
        self.assertTrue(self.worktree.exists())
        self.assertNotEqual(self.git("branch", "--list", self.ctx["branch"]), "")
        self.assertFalse(Path(self.ctx["state_dir"]).exists())
        self.assert_other_panes_preserved()

    def test_modified_buffer_blocks_exit(self):
        self.command("lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'unsaved'})")
        self.close_review()
        self.wait_for(lambda: "Unsaved buffer" in self.notices(), "buffer blocker")
        self.assertTrue(self.pane_exists(self.review))
        self.assertEqual((self.worktree / "file.txt").read_text(), "original\n")
        self.assertFalse((Path(self.ctx["state_dir"]) / "request.json").exists())

    def test_disk_changes_block_exit(self):
        (self.worktree / "file.txt").write_text("keep this change\n")
        self.close_review()
        self.wait_for(lambda: "tracked changes" in self.notices(), "Git changes blocker")
        self.assertTrue(self.pane_exists(self.review))
        self.assertEqual((self.worktree / "file.txt").read_text(), "keep this change\n")
        self.assertFalse((Path(self.ctx["state_dir"]) / "request.json").exists())

    def test_post_exit_failure_retains_worktree_and_visible_pane(self):
        (self.temp / "fail-cleanup").touch()
        self.close_review()
        self.wait_for(
            lambda: "Press Enter to close this pane" in self.tmux("capture-pane", "-p", "-t", self.review),
            "visible post-exit cleanup failure",
        )
        output = self.tmux("capture-pane", "-p", "-S", "-100", "-t", self.review)
        self.assertIn("fixture Docker became unavailable", output)
        self.assertTrue(self.worktree.exists())
        self.assertNotEqual(self.git("branch", "--list", self.ctx["branch"]), "")
        self.assert_other_panes_preserved()


if __name__ == "__main__":
    unittest.main(verbosity=2)
