#!/usr/bin/env bash
# Publish selection ownership to WezTerm clients, including over SSH.
# Python supplies nonblocking device writes, which shell redirection cannot do.
exec python3 - "$@" <<'PY'
import os
import select
import stat
import subprocess
import sys
import time

if not 2 <= len(sys.argv) <= 3:
    sys.exit('Usage: selection-state.sh <tmux-socket> [detached-client-tty]')

# Base64 encodings of 1 and 0 for OSC 1337 SetUserVar; no clipboard data.
SELECTION_ACTIVE = b'MQ=='
SELECTION_INACTIVE = b'MA=='


def publish(client_tty, encoded):
    # Control clients have no terminal; a client can also detach during a write.
    if not client_tty.startswith('/dev/'):
        return
    try:
        fd = os.open(client_tty, os.O_WRONLY | os.O_NONBLOCK | os.O_NOCTTY)
    except OSError:
        return
    try:
        if not stat.S_ISCHR(os.fstat(fd).st_mode):
            return
        pending = b'\x1b]1337;SetUserVar=TMUX_SELECTION=' + encoded + b'\x07'
        deadline = time.monotonic() + 0.05
        first_write = True
        while pending:
            # Skip full terminals immediately; allow a bounded retry only if
            # a partial write needs finishing. Never stall other clients.
            timeout = 0 if first_write else max(0, deadline - time.monotonic())
            if not select.select([], [fd], [], timeout)[1]:
                return
            try:
                written = os.write(fd, pending)
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    return
                continue
            if written == 0 or time.monotonic() >= deadline:
                return
            pending = pending[written:]
            first_write = False
    except OSError:
        pass
    finally:
        os.close(fd)


if len(sys.argv) == 3:
    publish(sys.argv[2], SELECTION_INACTIVE)
try:
    clients = subprocess.check_output(
        ['tmux', '-S', sys.argv[1], 'list-clients', '-F', '#{client_tty} #{pane_mode}'],
        text=True, stderr=subprocess.DEVNULL,
    )
except subprocess.CalledProcessError:
    sys.exit(0)  # The last client may have exited together with its server.
for client in clients.splitlines():
    client_tty, _, pane_mode = client.partition(' ')
    publish(client_tty, SELECTION_ACTIVE if pane_mode == 'copy-mode' else SELECTION_INACTIVE)
PY
