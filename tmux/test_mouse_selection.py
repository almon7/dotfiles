#!/usr/bin/env python3
"""Exercise pane selection through a disposable tmux client's terminal protocol."""
import base64
import errno
import fcntl
import os
from pathlib import Path
import pty
import re
import select
import shlex
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time
import tty
import unittest

ROOT = Path(__file__).resolve().parent
COPY = b'\x1b[99;13~'
CANCEL = b'\x1b[99;14~'


def fixture(log_path, name, mouse):
    tty.setraw(0)
    os.write(1, b'\x1b[?2004h')
    if mouse:
        os.write(1, b'\x1b[?1003h\x1b[?1006h')
    for number in range(1, 9):
        os.write(1, f'{name}{number:02} alpha bravo charlie delta\r\n'.encode())
    with open(log_path, 'ab', buffering=0) as log:
        while data := os.read(0, 4096):
            log.write(data)


@unittest.skipUnless(shutil.which('tmux'), 'tmux is required')
class MouseSelectionTests(unittest.TestCase):
    def tmux(self, *args):
        process = subprocess.Popen(
            ['tmux', '-f', '/dev/null', '-S', self.socket, *args],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        deadline = time.monotonic() + 10
        while True:
            try:
                output, error = process.communicate(timeout=.02)
                if process.returncode:
                    raise subprocess.CalledProcessError(process.returncode, process.args, output, error)
                self.assertEqual(error, '', f'tmux reported an error for {args}: {error}')
                return output.rstrip('\n')
            except subprocess.TimeoutExpired:
                # Real terminals keep reading during reloads. Otherwise OSC writes
                # to a full test PTY can block the synchronous reload command.
                if hasattr(self, 'master'):
                    self.drain(.01)
                if time.monotonic() >= deadline:
                    process.kill()
                    process.communicate()
                    raise


    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='tmux-selection-')
        self.addCleanup(self.temp.cleanup)
        self.socket = str(Path(self.temp.name) / 'socket')
        config = (ROOT / 'tmux.conf').read_text()
        config = config.replace("run-shell '~/.tmux/plugins/tpm/tpm'", '# No plugins in tests.')
        config = config.replace('~/.tmux/selection-state.sh', shlex.quote(str(ROOT / 'selection-state.sh')))
        self.config = Path(self.temp.name) / 'tmux.conf'
        self.config.write_text(config)
        self.tmux('new-session', '-d', '-s', 'test', '-x', '120', '-y', '30')
        self.addCleanup(lambda: subprocess.run(
            ['tmux', '-S', self.socket, 'kill-server'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        ))
        # A clean server avoids loading personal configuration and its plugins.
        self.tmux('source-file', str(self.config))
        self.tmux('set-option', '-g', 'assume-paste-time', '0')
        self.tmux('set-option', '-s', 'terminal-features[102]', 'xterm*:clipboard')
        self.left_log = Path(self.temp.name) / 'left.log'
        self.right_log = Path(self.temp.name) / 'right.log'
        def command(log, name, mouse):
            return shlex.join([sys.executable, str(Path(__file__).resolve()), '--fixture', str(log), name, mouse])
        self.left = self.tmux('new-window', '-d', '-t', 'test', '-n', 'selection', '-P', '-F', '#{pane_id}',
                              command(self.left_log, 'LEFT', 'plain'))
        self.right = self.tmux('split-window', '-h', '-t', self.left, '-P', '-F', '#{pane_id}',
                               command(self.right_log, 'RIGHT', 'mouse'))
        self.tmux('select-window', '-t', self.left)
        self.tmux('select-pane', '-t', self.left)
        self.master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 30, 120, 0, 0))
        env = dict(os.environ, TERM='xterm-256color')
        env.pop('TMUX', None)
        self.client = subprocess.Popen(['tmux', '-S', self.socket, 'attach-session', '-t', 'test'],
                                       stdin=slave, stdout=slave, stderr=slave, env=env, start_new_session=True)
        self.slave = slave  # Keep the parent shell’s terminal open across detach.
        self.addCleanup(self.close_client)
        self.output = bytearray()
        self.drain(.3)
        self.assertEqual(self.value(self.right, '#{mouse_any_flag}'), '1')
        self.rx = int(self.value(self.right, '#{pane_left}')) + 1

    def close_client(self):
        if self.client.poll() is None:
            self.client.kill()
        self.client.wait(timeout=5)
        os.close(self.master)
        os.close(self.slave)

    def drain(self, duration=.2):
        end = time.monotonic() + duration
        while time.monotonic() < end:
            ready, _, _ = select.select([self.master], [], [], max(0, end-time.monotonic()))
            if ready:
                try:
                    data = os.read(self.master, 65536)
                except OSError as error:
                    if error.errno == errno.EIO:
                        break
                    raise
                if not data:
                    break
                self.output.extend(data)

    def send(self, data):
        os.write(self.master, data)
        self.drain()

    def mouse(self, button, x, y, release=False):
        self.send(f'\x1b[<{button};{x};{y}{"m" if release else "M"}'.encode())

    def value(self, pane, expression):
        return self.tmux('display-message', '-p', '-t', pane, expression)

    def selected(self, pane):
        return self.value(pane, '#{selection_present}') == '1'

    def flag(self):
        values = re.findall(rb'\x1b\]1337;SetUserVar=TMUX_SELECTION=([^\x07]*)\x07', self.output)
        self.assertTrue(values, 'tmux did not publish selection state to its client')
        return base64.b64decode(values[-1])

    def drag(self, pane=None, reverse=False):
        pane = pane or self.left
        x = int(self.value(pane, '#{pane_left}')) + 1
        start, end = ((x+2, 1), (x+12, 3))
        if reverse:
            start, end = end, start
        self.mouse(0, *start)
        self.mouse(32, *end)
        self.mouse(0, *end, release=True)
        self.assertTrue(self.selected(pane))
        self.assertEqual(self.flag(), b'1')

    def copied_text(self):
        self.send(COPY)
        self.assertEqual(self.flag(), b'1')
        copies = re.findall(rb'\x1b\]52;[^;]*;([^\x07\x1b]*)(?:\x07|\x1b\\)', self.output)
        self.assertTrue(copies, 'copy did not emit OSC 52')
        return base64.b64decode(copies[-1]).decode()

    def test_selection_clipboard_and_boundaries(self):
        for pane, name, neighbor in [(self.left, 'LEFT', 'RIGHT'), (self.right, 'RIGHT', 'LEFT')]:
            for reverse in (False, True):
                with self.subTest(pane=name, reverse=reverse):
                    self.tmux('set-buffer', 'clipboard-sentinel')
                    before = len(re.findall(rb'\x1b\]52;', self.output))
                    self.drag(pane, reverse)
                    self.assertEqual(self.tmux('show-buffer'), 'clipboard-sentinel')
                    self.assertEqual(len(re.findall(rb'\x1b\]52;', self.output)), before)
                    text = self.copied_text()
                    self.assertIn(f'{name}02 alpha bravo charlie delta', text)
                    self.assertNotIn(neighbor, text)
                    self.assertEqual(len(text.splitlines()), 3)
                    self.assertTrue(self.selected(pane))
                    self.send(CANCEL)
                    self.assertEqual(self.flag(), b'0')

    def test_first_key_and_paste(self):
        for data in (b'h', b'j', b'k', b'l', b'y', b' hjkl y', b'\r', b'\x1b', b'\x1bb', 'é'.encode()):
            with self.subTest(data=data):
                self.drag()
                before = self.left_log.read_bytes()
                self.send(data)
                if data == b'\x1b':
                    self.drain(.6)  # A bare Escape waits for the terminal's key-sequence timeout.
                self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
                self.assertEqual(self.left_log.read_bytes()[len(before):], data)
                self.assertEqual(self.flag(), b'0')
        self.drag()
        before = self.left_log.read_bytes()
        paste = b'\x1b[200~first\nsecond\x1b[201~'
        self.send(CANCEL + paste)
        self.assertEqual(self.left_log.read_bytes()[len(before):], paste)
        self.assertEqual(self.flag(), b'0')
        before = self.left_log.read_bytes()
        self.send(COPY + CANCEL)
        self.assertEqual(self.left_log.read_bytes(), before)

    def test_navigation_click_away_and_wheel(self):
        self.drag()
        self.send(b'\x0c')
        self.assertEqual(self.value(self.right, '#{pane_active}'), '1')
        self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
        self.assertEqual(self.flag(), b'0')
        self.send(b'\x08')
        self.assertEqual(self.value(self.left, '#{pane_active}'), '1')
        self.drag()
        self.mouse(0, self.rx+5, 4)
        self.mouse(0, self.rx+5, 4, release=True)
        self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
        self.assertEqual(self.flag(), b'0')
        self.drag(self.right)
        before = self.right_log.read_bytes()
        self.mouse(64, self.rx+3, 3)
        self.assertEqual(self.value(self.right, '#{pane_in_mode}'), '0')
        self.assertIn(b'\x1b[<64;', self.right_log.read_bytes()[len(before):])
        self.drag()
        before = self.left_log.read_bytes()
        self.mouse(64, 3, 3)
        self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
        self.assertEqual(self.left_log.read_bytes(), before)

    def test_backed_up_client_does_not_block_healthy_client(self):
        master, slave = pty.openpty()
        try:
            tty.setraw(slave)
            os.set_blocking(slave, False)
            while True:
                try:
                    os.write(slave, b'x' * 4096)
                except BlockingIOError:
                    break
            # Publish to the full detached terminal first, then the healthy
            # attached client. Neither terminal's OS clipboard is involved.
            self.output.clear()
            result = subprocess.run(
                ['bash', str(ROOT / 'selection-state.sh'), self.socket, os.ttyname(slave)],
                capture_output=True, timeout=2,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.drain()
            self.assertEqual(self.flag(), b'0')
        finally:
            os.close(slave)
            os.close(master)

    def test_repeated_clicks_and_prefix_input(self):
        down, up = b'\x1b[<0;10;1M', b'\x1b[<0;10;1m'
        self.send(down + up + down + up)
        self.drain(.4)  # tmux waits for a possible third click before emitting DoubleClick.
        self.assertEqual(self.copied_text(), 'alpha')
        self.assertTrue(self.selected(self.left))
        self.send(CANCEL)
        down, up = b'\x1b[<0;11;1M', b'\x1b[<0;11;1m'
        self.send((down + up) * 3)
        self.assertEqual(self.copied_text().rstrip(), 'LEFT01 alpha bravo charlie delta')
        self.send(CANCEL)
        for encoded, expected in [(b'\x01\x0c', b'\x0c'), (b'\x01\x01', b'\x01')]:
            self.drag()
            before = self.left_log.read_bytes()
            self.send(encoded)
            self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
            self.assertEqual(self.left_log.read_bytes()[len(before):], expected)
        self.drag(self.right)
        before = self.right_log.read_bytes()
        self.mouse(35, self.rx+8, 4)  # Move without pressing a button.
        self.assertTrue(self.selected(self.right))
        self.assertEqual(self.right_log.read_bytes(), before)

    def test_focus_reload_and_detach(self):
        self.drag()
        self.tmux('source-file', str(self.config))
        self.drain()
        self.assertEqual(self.flag(), b'1')
        self.send(b'y')
        self.assertEqual(self.flag(), b'0')
        self.drag()
        self.send(b'\x01c')
        self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
        self.assertEqual(self.flag(), b'0')
        self.tmux('select-window', '-t', self.left)
        self.drain()
        self.drag()
        self.send(b'\x01d')
        self.assertEqual(self.flag(), b'0')
        self.client.wait(timeout=5)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--fixture':
        fixture(sys.argv[2], sys.argv[3], sys.argv[4] == 'mouse')
    else:
        unittest.main()
