#!/usr/bin/env python3
"""Regression check for AppKit deferred quit invoked from a signal callback.

Runs one explicitly owned menu-bar process; never signals an existing app.
"""
from pathlib import Path
import subprocess
import sys

binary = Path(sys.argv[1] if len(sys.argv) > 1 else "Debagr.app/Contents/MacOS/Debagr").resolve()
process = subprocess.Popen([str(binary), "--menu-bar"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    try:
        process.wait(timeout=1)
        raise SystemExit(f"Menu-bar process exited before the shutdown check: {process.returncode}")
    except subprocess.TimeoutExpired:
        pass
    process.terminate()
    try:
        status = process.wait(timeout=8)
    except subprocess.TimeoutExpired:
        raise SystemExit("Menu-bar process did not exit within 8 seconds after SIGTERM")
    assert status == 0, f"Menu-bar process exited abnormally: {status}"
    print("Menu-bar SIGTERM shutdown passed; owned process exited normally.")
finally:
    if process.poll() is None:
        process.kill()
        process.wait(timeout=3)
