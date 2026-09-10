#!/usr/bin/env python3
"""Exercise pane selection through a disposable tmux client's terminal protocol."""
import base64
import errno
import fcntl
import json
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
# xterm encodings sent by WezTerm for Command navigation (Ctrl-F1 through F12).
LEFT, DOWN, UP, RIGHT = (b'\x1b[1;5P', b'\x1b[1;5Q', b'\x1b[1;5R', b'\x1b[1;5S')
NEXT_WINDOW, PREV_WINDOW = b'\x1b[15;5~', b'\x1b[17;5~'
NEXT_SESSION, PREV_SESSION = b'\x1b[18;5~', b'\x1b[19;5~'
SCROLL_UP, SCROLL_DOWN = b'\x1b[20;5~', b'\x1b[21;5~'
THIRD_UP, THIRD_DOWN = b'\x1b[23;5~', b'\x1b[24;5~'


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

    def mouse(self, button, x, y, release=False, count=1):
        self.send(f'\x1b[<{button};{x};{y}{"m" if release else "M"}'.encode() * count)

    def value(self, pane, expression):
        return self.tmux('display-message', '-p', '-t', pane, expression)

    def selected(self, pane):
        return self.value(pane, '#{selection_present}') == '1'

    def print_history(self, start=1, count=100):
        # Writing to the fixture's terminal models output without injecting input.
        with open(self.value(self.left, '#{pane_tty}'), 'wb', buffering=0) as terminal:
            terminal.write(''.join(
                f'HISTORY{number:03} alpha bravo charlie delta\r\n'
                for number in range(start, start + count)
            ).encode())
        self.drain()
        self.assertGreater(int(self.value(self.left, '#{history_size}')), 0)

    def scroll_position(self):
        return int(self.value(self.left, '#{scroll_position}') or 0)

    def history_viewport(self):
        # -M captures copy mode's backing history; apply the displayed offset.
        position = self.scroll_position()
        height = int(self.value(self.left, '#{pane_height}'))
        return self.tmux('capture-pane', '-pM', '-t', self.left,
                         '-S', str(-position), '-E', str(height - position - 1))

    def wheel(self, up=True, pane=None, count=1):
        pane = pane or self.left
        x = int(self.value(pane, '#{pane_left}')) + 4
        self.mouse(64 if up else 65, x, 4, count=count)

    def flag(self):
        values = re.findall(rb'\x1b\]1337;SetUserVar=TMUX_SELECTION=([^\x07]*)\x07', self.output)
        self.assertTrue(values, 'tmux did not publish selection state to its client')
        return base64.b64decode(values[-1])

    def drag(self, pane=None, reverse=False, row=1):
        pane = pane or self.left
        x = int(self.value(pane, '#{pane_left}')) + 1
        start, end = ((x+2, row), (x+12, row+2))
        if reverse:
            start, end = end, start
        self.mouse(0, *start)
        self.mouse(32, *end)
        self.mouse(0, *end, release=True)
        self.assertTrue(self.selected(pane))
        self.assertEqual(self.flag(), b'1')

    def copied_text(self):
        before = len(self.output)
        self.send(COPY)
        self.assertEqual(self.flag(), b'1')
        copies = re.findall(rb'\x1b\]52;[^;]*;([^\x07\x1b]*)(?:\x07|\x1b\\)', self.output[before:])
        self.assertEqual(len(copies), 1, 'copy must emit exactly one OSC 52 sequence')
        return base64.b64decode(copies[-1]).decode()

    def assert_copy_ignored(self):
        buffer = self.tmux('show-buffer')
        before = len(self.output)
        logs = [path.read_bytes() for path in (self.left_log, self.right_log)]
        self.send(COPY)
        self.assertEqual(self.tmux('show-buffer'), buffer)
        self.assertNotIn(b'\x1b]52;', self.output[before:])
        self.assertEqual([path.read_bytes() for path in (self.left_log, self.right_log)], logs)

    def start_nvim(self):
        if not shutil.which('nvim'):
            self.skipTest('nvim is required for native mouse tests')
        self.nvim_socket = str(Path(self.temp.name) / 'nvim.socket')
        command = shlex.join([
            'nvim', '--clean', '-i', 'NONE', '-n', '--listen', self.nvim_socket,
            '-c', 'set mouse=a laststatus=3',
            '-c', "call setline(1, repeat(['alpha bravo charlie delta'], 80))",
        ])
        self.tmux('respawn-pane', '-k', '-t', self.right, command)
        deadline = time.monotonic() + 5
        while not Path(self.nvim_socket).exists() or self.value(self.right, '#{mouse_any_flag}') != '1':
            self.assertLess(time.monotonic(), deadline, 'Neovim did not start')
            self.drain(.05)
        self.drain()
        self.assertEqual(self.value(self.right, '#{pane_current_command}'), 'nvim')

    def nvim_expr(self, expression):
        result = subprocess.run(
            ['nvim', '--server', self.nvim_socket, '--remote-expr', f'json_encode({expression})'],
            check=True, capture_output=True, text=True, timeout=5,
        )
        return json.loads(result.stdout)

    def load_nvim_keymaps(self):
        # Supply the LazyVim defaults that keymaps.lua deliberately removes.
        setup = """
          for _, key in ipairs({ '<C-h>', '<C-j>', '<C-k>', '<C-l>' }) do
            vim.keymap.set('n', key, '<Nop>')
          end
          dofile(%s)
        """ % json.dumps(str(ROOT.parent / 'nvim/lua/config/keymaps.lua'))
        self.nvim_expr('luaeval(' + json.dumps('(function() ' + setup + ' end)()') + ')')

    def nvim_mouse(self, button, column, row, release=False):
        left, top = map(int, self.value(self.right, '#{pane_left} #{pane_top}').split())
        self.mouse(button, left + column, top + row, release=release)

    def test_nvim_command_key_decoding(self):
        self.start_nvim()
        plugin = self.nvim_expr('stdpath("data")') + '/lazy/vim-tmux-navigator'
        if not Path(plugin, 'plugin/tmux_navigator.vim').is_file():
            self.skipTest('installed vim-tmux-navigator is required')
        # Load the real mapping spec and navigator, without unrelated editor plugins.
        # The PTY input must survive tmux's terminfo encoding, not just map lookup.
        setup = """
            vim.opt.rtp:prepend(%s)
            vim.opt.rtp:prepend(%s)
            local spec = dofile(%s)
            spec.init()
            vim.cmd('runtime plugin/tmux_navigator.vim')
            for _, key in ipairs(spec.keys) do
                vim.keymap.set(key.mode or 'n', key[1], key[2], {expr=key.expr, silent=true})
            end
            return true
        """ % (json.dumps(str(ROOT.parent / 'nvim')), json.dumps(plugin),
                   json.dumps(str(ROOT.parent / 'nvim/lua/plugins/tmux.lua')))
        self.nvim_expr('luaeval(' + json.dumps('(function() ' + setup + ' end)()') + ')')
        self.tmux('select-pane', '-t', self.right)
        self.nvim_expr('execute("vsplit | wincmd h")')
        left = self.nvim_expr('win_getid()')
        self.send(RIGHT)
        self.assertNotEqual(self.nvim_expr('win_getid()'), left)
        self.send(LEFT)
        self.assertEqual(self.nvim_expr('win_getid()'), left)
        self.nvim_expr('execute("split | wincmd k")')
        upper = self.nvim_expr('win_getid()')
        self.send(DOWN)
        self.assertNotEqual(self.nvim_expr('win_getid()'), upper)
        self.send(UP)
        self.assertEqual(self.nvim_expr('win_getid()'), upper)
        self.send(LEFT)
        self.assertEqual(self.value(self.left, '#{pane_active}'), '1')
        self.send(RIGHT)
        self.nvim_expr('execute("only | terminal | startinsert")')
        self.drain(.3)
        self.send(LEFT)
        self.assertEqual(self.value(self.left, '#{pane_active}'), '1')

    def test_command_scroll_history(self):
        self.print_history()
        for mode in ('emacs', 'vi'):
            with self.subTest(mode=mode):
                self.tmux('set-option', '-w', 'mode-keys', mode)
                before = self.left_log.read_bytes()
                self.send(SCROLL_DOWN)
                self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
                self.send(SCROLL_UP)
                self.assertEqual(self.scroll_position(), 1)
                self.send(SCROLL_UP)
                self.assertEqual(self.scroll_position(), 2)
                self.drag(row=4)
                self.send(SCROLL_DOWN)
                self.assertFalse(self.selected(self.left))
                self.assertEqual(self.scroll_position(), 1)
                self.send(SCROLL_DOWN)
                self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
                self.assertEqual(self.left_log.read_bytes(), before)
                self.assertEqual(self.value(self.right, '#{pane_in_mode}'), '0')
                self.assertEqual(self.value(self.left, '#{pane_active}'), '1')

    def test_nvim_command_scroll(self):
        self.start_nvim()
        self.load_nvim_keymaps()
        self.tmux('select-pane', '-t', self.right)
        for mode_key, mode in ((b'', 'n'), (b'v', 'v'), (b'i', 'i')):
            with self.subTest(mode=mode):
                self.send(b'\x1b')
                self.nvim_expr('execute("normal! 40Gzz")')
                self.send(mode_key)
                position = self.nvim_expr('winsaveview().topline')
                self.send(SCROLL_UP)
                topline, current_mode = self.nvim_expr('[winsaveview().topline, mode()]')
                self.assertEqual(topline, position - 1)
                self.assertEqual(current_mode, mode)
                self.send(SCROLL_DOWN)
                topline, current_mode = self.nvim_expr('[winsaveview().topline, mode()]')
                self.assertEqual(topline, position)
                self.assertEqual(current_mode, mode)
                self.assertEqual(self.value(self.right, '#{pane_in_mode}'), '0')

    def test_command_third_scroll_history(self):
        self.send(THIRD_UP)
        self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
        self.print_history()
        for height in (29, 17, 2, 1):
            self.tmux('resize-window', '-t', self.left, '-y', str(height + 1))
            self.assertEqual(int(self.value(self.left, '#{pane_height}')), height)
            distance = max(1, height // 3)
            for mode in ('emacs', 'vi'):
                with self.subTest(height=height, mode=mode):
                    self.tmux('set-option', '-w', 'mode-keys', mode)
                    before = self.left_log.read_bytes()
                    self.send(THIRD_DOWN)
                    self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
                    self.send(THIRD_UP)
                    self.assertEqual(self.scroll_position(), distance)
                    self.send(THIRD_UP)
                    self.assertEqual(self.scroll_position(), 2 * distance)
                    if height > 6:
                        self.drag(row=4)
                    self.send(THIRD_DOWN)
                    self.assertFalse(self.selected(self.left))
                    self.assertEqual(self.scroll_position(), distance)
                    self.send(THIRD_DOWN)
                    self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
                    self.assertEqual(self.left_log.read_bytes(), before)
                    self.assertEqual(self.value(self.right, '#{pane_in_mode}'), '0')
                    self.assertEqual(self.value(self.left, '#{pane_active}'), '1')
        # Scroll beyond both ends; going down must leave copy mode even when
        # fewer than a full step remains before live output.
        self.tmux('resize-window', '-t', self.left, '-y', '30')
        self.send(THIRD_UP * 30)
        top = self.scroll_position()
        self.send(THIRD_UP)
        self.assertEqual(self.scroll_position(), top)
        self.send(THIRD_DOWN * 30)
        self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')

    def test_nvim_command_third_scroll(self):
        self.start_nvim()
        self.load_nvim_keymaps()
        self.tmux('select-pane', '-t', self.right)
        for height in (29, 17):
            self.tmux('resize-window', '-t', self.right, '-y', str(height + 1))
            self.drain()
            distance = self.nvim_expr('winheight(0)') // 3
            for mouse in ('a', ''):
                self.nvim_expr('execute(' + json.dumps('set mouse=' + mouse) + ')')
                for up, down in ((THIRD_UP, THIRD_DOWN), (b'\x15', b'\x04')):
                    with self.subTest(height=height, mouse=mouse, up=up):
                        self.nvim_expr('execute("normal! 40Gzz")')
                        position = self.nvim_expr('winsaveview().topline')
                        self.send(up)
                        line, topline = self.nvim_expr('[line("."), winsaveview().topline]')
                        self.assertEqual(line, 40 - distance)
                        self.assertEqual(topline, position - distance)
                        self.send(down)
                        self.assertEqual(self.nvim_expr('line(".")'), 40)
                        self.send(b'5' + down)
                        self.assertEqual(self.nvim_expr('line(".")'), 45)
                        self.assertEqual(self.value(self.right, '#{pane_in_mode}'), '0')

    def test_nvim_divider_resize(self):
        self.start_nvim()
        for layout, dimension in [('vsplit', 'width'), ('split', 'height')]:
            with self.subTest(layout=layout):
                self.nvim_expr(f'execute("only | {layout}")')
                self.drain()
                for delta in (5, -3):
                    window = min(self.nvim_expr('getwininfo()'), key=lambda win: (win['winrow'], win['wincol']))
                    column = window['wincol'] + (window['width'] if layout == 'vsplit' else 3)
                    row = window['winrow'] + (window['height'] if layout == 'split' else 2)
                    end_column = column + (delta if layout == 'vsplit' else 0)
                    end_row = row + (delta if layout == 'split' else 0)
                    self.nvim_mouse(0, column, row)
                    self.nvim_mouse(32, end_column, end_row)
                    self.nvim_mouse(0, end_column, end_row, release=True)
                    resized = self.nvim_expr(f"getwininfo({window['winid']})[0]")
                    self.assertEqual(resized[dimension], window[dimension] + delta)
                    self.assertEqual(self.value(self.right, '#{pane_in_mode}'), '0')
                    self.assertEqual(self.nvim_expr('mode()'), 'n')
                    self.assertEqual(self.flag(), b'0')

    def test_nvim_click_selection_and_release(self):
        self.start_nvim()
        self.assertEqual(self.value(self.left, '#{pane_active}'), '1')
        self.nvim_mouse(0, 8, 3)
        self.nvim_mouse(0, 8, 3, release=True)
        self.assertEqual(self.value(self.right, '#{pane_active}'), '1')
        self.assertEqual(self.nvim_expr('[line("."), col(".")]'), [3, 8])
        self.nvim_mouse(0, 2, 4)
        self.nvim_mouse(32, 10, 6)
        self.nvim_mouse(0, 10, 6, release=True)
        self.assertEqual(self.nvim_expr('mode()'), 'v')
        self.assertEqual(self.nvim_expr('[line("v"), col("v"), line("."), col(".")]'), [4, 2, 6, 10])
        self.assertEqual(self.value(self.right, '#{pane_in_mode}'), '0')
        self.assertEqual(self.flag(), b'0')
        self.nvim_mouse(35, 20, 8)  # Moving after release must not extend the selection.
        self.assertEqual(self.nvim_expr('[line("."), col(".")]'), [6, 10])
        self.nvim_mouse(0, 4, 2)
        self.nvim_mouse(0, 4, 2, release=True)
        self.assertEqual(self.nvim_expr('mode()'), 'n')
        self.assertEqual(self.nvim_expr('[line("."), col(".")]'), [2, 4])

    def test_nvim_multiple_clicks(self):
        self.start_nvim()
        for count, mode in [(2, 'v'), (3, 'V')]:
            with self.subTest(count=count):
                self.send(b'\x1b')
                self.drain(.6)
                column = int(self.value(self.right, '#{pane_left}')) + 8
                down = f'\x1b[<0;{column};3M'.encode()
                up = f'\x1b[<0;{column};3m'.encode()
                self.send((down + up) * count)
                self.drain(.4)  # Allow tmux's delayed double-click event to arrive.
                self.assertEqual(self.nvim_expr('mode()'), mode)
                self.assertEqual(self.value(self.right, '#{pane_in_mode}'), '0')
                self.assertEqual(self.flag(), b'0')
                self.send(b'y')
                self.assertEqual(self.nvim_expr('getreg()'), 'bravo' if count == 2 else 'alpha bravo charlie delta\n')

    def test_nvim_click_clears_copy_mode_after_reload(self):
        self.start_nvim()
        for mode in ('emacs', 'vi'):
            with self.subTest(mode=mode):
                self.tmux('set-option', '-w', 'mode-keys', mode)
                self.tmux('select-pane', '-t', self.right)
                self.tmux('copy-mode', '-t', self.right)
                self.tmux('send-keys', '-t', self.right, '-X', 'begin-selection')
                self.tmux('send-keys', '-t', self.right, '-X', 'cursor-right')
                self.assertTrue(self.selected(self.right))
                self.tmux('source-file', str(self.config))
                self.drain()
                self.assertEqual(self.flag(), b'1')
                self.nvim_mouse(0, 9, 5)
                self.nvim_mouse(0, 9, 5, release=True)
                self.assertEqual(self.value(self.right, '#{pane_in_mode}'), '0')
                self.assertEqual(self.nvim_expr('[line("."), col(".")]'), [5, 9])
                self.assertEqual(self.flag(), b'0')

    def test_nvim_click_clears_other_pane_selection(self):
        self.start_nvim()
        self.drag(self.left)
        self.nvim_mouse(0, 7, 4)
        self.nvim_mouse(0, 7, 4, release=True)
        self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
        self.assertEqual(self.value(self.right, '#{pane_active}'), '1')
        self.assertEqual(self.nvim_expr('[line("."), col(".")]'), [4, 7])
        self.assertEqual(self.flag(), b'0')

    def test_nvim_tmux_border_resize(self):
        self.start_nvim()
        before = int(self.value(self.left, '#{pane_width}'))
        self.mouse(0, before + 1, 5)
        self.mouse(32, before + 6, 5)
        self.mouse(0, before + 6, 5, release=True)
        self.assertEqual(int(self.value(self.left, '#{pane_width}')), before + 5)
        self.assertEqual(self.value(self.right, '#{pane_in_mode}'), '0')
        self.assertEqual(self.nvim_expr('mode()'), 'n')

    def test_nvim_without_mouse_uses_terminal_selection(self):
        self.start_nvim()
        self.nvim_expr('execute("set mouse=")')
        self.drain()
        self.assertEqual(self.value(self.right, '#{mouse_any_flag}'), '0')
        self.drag(self.right)
        self.assertEqual(self.nvim_expr('mode()'), 'n')
        self.assertEqual(self.nvim_expr('[line("."), col(".")]'), [1, 1])

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
                    self.assertFalse(self.selected(pane))
                    self.assert_copy_ignored()
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
        self.send(RIGHT)
        self.assertEqual(self.value(self.right, '#{pane_active}'), '1')
        self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
        self.assertEqual(self.flag(), b'0')
        self.send(LEFT)
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

    def test_command_navigation_and_released_keys(self):
        # Reload must retire bindings inherited from the previous configuration.
        for key in ('C-h', 'C-j', 'C-k', 'C-l', 'M-j', 'M-k'):
            self.tmux('bind-key', '-n', key, 'select-pane', '-t', self.right)
        self.tmux('source-file', str(self.config))
        for mode in ('emacs', 'vi'):
            self.tmux('set-option', '-w', 'mode-keys', mode)
            for selected in (False, True):
                for key in (b'\x08', b'\x0a', b'\x0b', b'\x0c', b'\x1bj', b'\x1bk'):
                    if selected:
                        self.drag()
                    before = self.left_log.read_bytes()
                    self.send(key)
                    self.assertEqual(self.value(self.left, '#{pane_active}'), '1')
                    self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
                    self.assertEqual(self.left_log.read_bytes()[len(before):], key)
            self.drag()
            self.send(RIGHT)
            self.assertEqual(self.value(self.right, '#{pane_active}'), '1')
            self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
            self.send(RIGHT)  # Stop at the right edge.
            self.assertEqual(self.value(self.right, '#{pane_active}'), '1')
            self.send(LEFT)
            self.send(LEFT)  # Stop at the left edge.
            self.assertEqual(self.value(self.left, '#{pane_active}'), '1')
        lower = self.tmux('split-window', '-v', '-d', '-t', self.left, '-P', '-F', '#{pane_id}')
        self.send(DOWN)
        self.assertEqual(self.value(lower, '#{pane_active}'), '1')
        self.send(DOWN)
        self.assertEqual(self.value(lower, '#{pane_active}'), '1')
        self.send(UP)
        self.assertEqual(self.value(self.left, '#{pane_active}'), '1')

    def test_command_windows_and_sessions(self):
        following = self.tmux('new-window', '-d', '-t', 'test', '-P', '-F', '#{window_id}')
        original = self.value(self.left, '#{window_id}')
        first = self.tmux('list-windows', '-t', 'test', '-F', '#{window_id}').splitlines()[0]
        for mode in ('emacs', 'vi'):
            self.tmux('set-option', '-w', 'mode-keys', mode)
            self.drag()
            self.send(NEXT_WINDOW)
            self.assertEqual(self.tmux('display-message', '-p', '#{window_id}'), following)
            self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
            self.send(NEXT_WINDOW)  # Window navigation wraps.
            self.assertEqual(self.tmux('display-message', '-p', '#{window_id}'), first)
            self.send(PREV_WINDOW)
            self.assertEqual(self.tmux('display-message', '-p', '#{window_id}'), following)
            self.send(PREV_WINDOW)
            self.assertEqual(self.tmux('display-message', '-p', '#{window_id}'), original)
        self.tmux('new-session', '-d', '-s', 'aaa')
        self.tmux('new-session', '-d', '-s', 'zzz')
        for mode in ('emacs', 'vi'):
            self.tmux('set-option', '-w', 'mode-keys', mode)
            self.drag()
            self.send(NEXT_SESSION)
            self.assertEqual(self.tmux('display-message', '-p', '#{session_name}'), 'zzz')
            self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
            self.send(NEXT_SESSION)  # Session navigation does not wrap.
            self.assertEqual(self.tmux('display-message', '-p', '#{session_name}'), 'zzz')
            self.send(PREV_SESSION)
            self.assertEqual(self.tmux('display-message', '-p', '#{session_name}'), 'test')
            self.send(PREV_SESSION)
            self.send(PREV_SESSION)
            self.assertEqual(self.tmux('display-message', '-p', '#{session_name}'), 'aaa')
            self.send(NEXT_SESSION)
            self.assertEqual(self.tmux('display-message', '-p', '#{session_name}'), 'test')

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
        self.assertFalse(self.selected(self.left))
        self.send(CANCEL)
        down, up = b'\x1b[<0;11;1M', b'\x1b[<0;11;1m'
        self.send((down + up) * 3)
        self.assertEqual(self.copied_text().rstrip(), 'LEFT01 alpha bravo charlie delta')
        self.assertFalse(self.selected(self.left))
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

    def test_history_scrolling_and_boundaries(self):
        for mode in ('emacs', 'vi'):
            with self.subTest(mode=mode):
                self.tmux('set-option', '-w', 'mode-keys', mode)
                self.wheel(up=False)
                self.wheel()
                self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
                self.print_history()
                before = self.left_log.read_bytes()
                self.wheel()
                self.assertEqual(self.scroll_position(), 3)
                self.assertEqual(self.flag(), b'1')
                self.wheel(count=3)
                self.assertEqual(self.scroll_position(), 12)
                self.wheel(up=False, count=2)
                self.assertEqual(self.scroll_position(), 6)
                self.wheel(count=100)
                top = self.scroll_position()
                self.assertEqual(top, int(self.value(self.left, '#{history_size}')))
                self.wheel()
                self.assertEqual(self.scroll_position(), top)
                self.wheel(up=False, count=100)
                self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
                self.assertEqual(self.flag(), b'0')
                self.wheel(up=False)
                self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
                self.assertEqual(self.left_log.read_bytes(), before)
                self.tmux('clear-history', '-t', self.left)

    def test_history_selection_and_copy(self):
        self.print_history()
        for mode in ('emacs', 'vi'):
            with self.subTest(mode=mode):
                self.tmux('set-option', '-w', 'mode-keys', mode)
                for reverse in (False, True):
                    self.wheel(count=5)
                    position = self.scroll_position()
                    viewport = self.history_viewport()
                    self.tmux('set-buffer', 'clipboard-sentinel')
                    self.assert_copy_ignored()
                    self.assertEqual(self.scroll_position(), position)
                    self.drag(reverse=reverse, row=2)
                    self.assertEqual(self.scroll_position(), position)
                    text = self.copied_text()
                    self.assertIn(viewport.splitlines()[2], text)
                    self.assertNotIn('RIGHT', text)
                    self.assertEqual(len(text.splitlines()), 3)
                    self.assertFalse(self.selected(self.left))
                    self.assertEqual(self.scroll_position(), position)
                    self.assertEqual(self.history_viewport(), viewport)
                    self.assert_copy_ignored()
                    self.assertEqual(self.scroll_position(), position)
                    self.wheel()
                    self.assertFalse(self.selected(self.left))
                    self.assertEqual(self.scroll_position(), position + 3)
                    self.assertEqual(self.flag(), b'1')
                    self.send(CANCEL)
                self.wheel(count=5)
                position = self.scroll_position()
                viewport = self.history_viewport()
                down, up = b'\x1b[<0;15;2M', b'\x1b[<0;15;2m'
                self.send((down + up) * 2)
                self.drain(.4)
                self.assertEqual(self.copied_text(), 'alpha')
                self.assertFalse(self.selected(self.left))
                self.assertEqual(self.scroll_position(), position)
                self.drain(.4)
                self.send((down + up) * 3)
                self.assertEqual(self.copied_text().rstrip(), viewport.splitlines()[1])
                self.assertFalse(self.selected(self.left))
                self.assertEqual(self.scroll_position(), position)
                self.send(CANCEL)

    def test_history_click_away_preserves_scroll_position(self):
        self.print_history()
        for mode in ('emacs', 'vi'):
            for select_text in (False, True):
                with self.subTest(mode=mode, select_text=select_text):
                    self.tmux('set-option', '-w', 'mode-keys', mode)
                    self.wheel(count=5)
                    position = self.scroll_position()
                    viewport = self.history_viewport()
                    if select_text:
                        self.drag(row=2)
                    else:
                        self.mouse(0, 10, 3)
                        self.mouse(0, 10, 3, release=True)
                    self.mouse(0, self.rx+5, 4)
                    self.mouse(0, self.rx+5, 4, release=True)
                    self.assertEqual(self.value(self.right, '#{pane_active}'), '1')
                    self.assertEqual(self.scroll_position(), position)
                    self.assertEqual(self.history_viewport(), viewport)
                    self.assertFalse(self.selected(self.left))
                    self.assertEqual(self.flag(), b'0')
                    self.mouse(0, 10, 3)
                    self.mouse(0, 10, 3, release=True)
                    self.assertEqual(self.value(self.left, '#{pane_active}'), '1')
                    self.assertEqual(self.scroll_position(), position)
                    self.assertEqual(self.history_viewport(), viewport)
                    self.assertEqual(self.flag(), b'1')
                    self.send(CANCEL)

    def test_history_inactive_panes_and_mouse_forwarding(self):
        self.print_history()
        for mode in ('emacs', 'vi'):
            with self.subTest(mode=mode):
                self.tmux('set-option', '-w', 'mode-keys', mode)
                self.tmux('select-pane', '-t', self.right)
                right_viewport = self.tmux('capture-pane', '-p', '-t', self.right)
                self.wheel(count=2)
                self.assertEqual(self.value(self.right, '#{pane_active}'), '1')
                self.assertEqual(self.scroll_position(), 6)
                self.assertEqual(self.flag(), b'0')
                self.wheel(up=False)
                self.assertEqual(self.scroll_position(), 3)
                self.assertEqual(self.tmux('capture-pane', '-p', '-t', self.right), right_viewport)
                self.wheel(up=False)
                self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
                self.assertEqual(self.value(self.right, '#{pane_active}'), '1')
                self.assertEqual(self.flag(), b'0')
                self.wheel()
                self.drag()
                self.assertEqual(self.value(self.left, '#{pane_active}'), '1')
                self.assertEqual(self.scroll_position(), 3)
                for up in (True, False):
                    before = self.right_log.read_bytes()
                    self.wheel(up=up, pane=self.right)
                    self.assertIn(f'\x1b[<{64 if up else 65};'.encode(), self.right_log.read_bytes()[len(before):])
                    self.assertEqual(self.value(self.left, '#{pane_active}'), '1')
                    self.assertEqual(self.scroll_position(), 3)
                    self.drag(self.right)
                    before = self.right_log.read_bytes()
                    self.wheel(up=up, pane=self.right)
                    self.assertEqual(self.value(self.right, '#{pane_in_mode}'), '0')
                    self.assertIn(f'\x1b[<{64 if up else 65};'.encode(), self.right_log.read_bytes()[len(before):])
                    self.tmux('select-pane', '-t', self.left)
                    self.drain()
                    self.assertEqual(self.scroll_position(), 3)
                    self.assertEqual(self.flag(), b'1')
                self.send(CANCEL)

    def test_history_input_output_and_navigation(self):
        self.print_history()
        for mode in ('emacs', 'vi'):
            with self.subTest(mode=mode):
                self.tmux('set-option', '-w', 'mode-keys', mode)
                for data in (b'h', b'j', b'k', b'l', b'y', b'\x1b', b'\x1bb', 'é'.encode()):
                    self.wheel(count=3)
                    before = self.left_log.read_bytes()
                    self.send(data)
                    if data == b'\x1b':
                        self.drain(.6)
                    self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
                    self.assertEqual(self.left_log.read_bytes()[len(before):], data)
                    self.assertEqual(self.flag(), b'0')
                self.wheel(count=3)
                before = self.left_log.read_bytes()
                paste = b'\x1b[200~first\nsecond\x1b[201~'
                self.send(CANCEL + paste)
                self.assertEqual(self.left_log.read_bytes()[len(before):], paste)
                self.assertEqual(self.flag(), b'0')
                self.wheel(count=3)
                viewport = self.history_viewport()
                self.print_history(start=101, count=10)
                self.assertEqual(self.history_viewport(), viewport)
                self.send(RIGHT)
                self.assertEqual(self.value(self.right, '#{pane_active}'), '1')
                self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
                self.assertEqual(self.flag(), b'0')
                self.send(LEFT)
                self.wheel(count=3)
                self.send(b'\x01h')
                self.assertEqual(self.scroll_position(), 9)
                self.send(b'\x01l')
                self.assertEqual(self.value(self.right, '#{pane_active}'), '1')
                self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
                self.assertEqual(self.flag(), b'0')
                self.send(b'\x01h')

    def test_history_reload_window_change_and_detach(self):
        self.print_history()
        self.wheel(count=3)
        position = self.scroll_position()
        self.tmux('source-file', str(self.config))
        self.drain()
        self.assertEqual(self.scroll_position(), position)
        self.assertEqual(self.flag(), b'1')
        self.wheel()
        self.assertEqual(self.scroll_position(), position + 3)
        self.send(b'\x01c')
        self.assertEqual(self.value(self.left, '#{pane_in_mode}'), '0')
        self.assertEqual(self.flag(), b'0')
        self.tmux('select-window', '-t', self.left)
        self.drain()
        self.wheel()
        self.send(b'\x01d')
        self.assertEqual(self.flag(), b'0')
        self.client.wait(timeout=5)

    def test_history_edge_drag_stops_on_release(self):
        self.print_history()
        height = int(self.value(self.left, '#{pane_height}'))
        for mode in ('emacs', 'vi'):
            for start, end in ((3, 1), (height - 2, height)):
                with self.subTest(mode=mode, edge=end):
                    self.tmux('set-option', '-w', 'mode-keys', mode)
                    self.wheel(count=10)
                    self.mouse(0, 5, start)
                    self.mouse(32, 13, end)
                    self.mouse(0, 13, end, release=True)
                    position = self.scroll_position()
                    selection = self.value(self.left, '#{selection_start_y}:#{selection_end_y}')
                    self.assertTrue(self.selected(self.left))
                    self.drain(.4)
                    self.assertEqual(self.scroll_position(), position)
                    self.assertEqual(self.value(self.left, '#{selection_start_y}:#{selection_end_y}'), selection)
                    self.assertTrue(self.copied_text())
                    self.send(CANCEL)

    def test_short_pane_edge_release_does_not_reverse_scroll(self):
        self.print_history()
        for height in (1, 2):
            self.tmux('resize-window', '-t', self.left, '-y', str(height + 1))
            self.assertEqual(int(self.value(self.left, '#{pane_height}')), height)
            for mode in ('emacs', 'vi'):
                for edge in range(1, height + 1):
                    with self.subTest(height=height, mode=mode, edge=edge):
                        self.tmux('set-option', '-w', 'mode-keys', mode)
                        self.mouse(64, 4, 1, count=10)
                        self.mouse(0, 5, height if edge == 1 else 1)
                        self.mouse(32, 13, edge)
                        before = self.scroll_position()
                        self.mouse(0, 13, edge, release=True)
                        self.drain(.4)
                        # tmux may keep its native edge timer running in tiny panes.
                        # A release must not move the cursor onto the opposite edge.
                        if edge == 1:
                            self.assertGreaterEqual(self.scroll_position(), before)
                        else:
                            self.assertLessEqual(self.scroll_position(), before)
                        self.assertTrue(self.selected(self.left))
                        self.send(CANCEL)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--fixture':
        fixture(sys.argv[2], sys.argv[3], sys.argv[4] == 'mouse')
    else:
        unittest.main()
