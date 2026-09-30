#!/usr/bin/env python3
"""Measure a real packaged app while unplugged; sampling runs outside the app."""
import argparse
import ctypes
import json
import pathlib
import subprocess
import time


class TaskInfo(ctypes.Structure):
    _fields_ = [(name, ctypes.c_uint64) for name in (
        "virtual_size", "resident_size", "total_user", "total_system", "threads_user", "threads_system"
    )] + [(name, ctypes.c_int32) for name in (
        "policy", "faults", "pageins", "cow_faults", "messages_sent", "messages_received",
        "syscalls_mach", "syscalls_unix", "context_switches", "thread_count", "running_threads", "priority"
    )]


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=float, default=30)
    parser.add_argument("--app", type=pathlib.Path, default=root / "dist/Keyfinder.app")
    args = parser.parse_args()
    if not 5 <= args.seconds <= 300:
        parser.error("Use a measurement interval between 5 and 300 seconds.")
    binary = args.app.resolve() / "Contents/MacOS/Keyfinder"
    libproc = ctypes.CDLL("/usr/lib/libproc.dylib")
    libproc.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_int]
    libproc.proc_pidinfo.restype = ctypes.c_int
    process = subprocess.Popen([str(binary), "--background"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def sample():
        if process.poll() is not None:
            raise RuntimeError(f"Keyfinder exited before sampling: {process.communicate()}")
        info = TaskInfo()
        size = libproc.proc_pidinfo(process.pid, 4, 0, ctypes.byref(info), ctypes.sizeof(info))
        if size != ctypes.sizeof(info):
            raise RuntimeError(f"Could not read process counters: {size}")
        return info

    try:
        time.sleep(3)  # Exclude process startup; this timer is in the measurement tool.
        before = sample()
        started = time.monotonic()
        time.sleep(args.seconds)
        after = sample()
        elapsed = time.monotonic() - started
        cpu = (after.total_user + after.total_system - before.total_user - before.total_system) / 1e9
        report = {
            "app": str(args.app.resolve()),
            "pid": process.pid,
            "conditions": "Packaged release app, --background, settings closed. Disconnect the keyboard for an idle baseline.",
            "wall_seconds": round(elapsed, 4),
            "cpu_seconds": round(cpu, 6),
            "average_cpu_percent_of_one_core": round(cpu / elapsed * 100, 6),
            "resident_memory_mib": round(after.resident_size / (1024 * 1024), 2),
            "context_switches": after.context_switches - before.context_switches,
            "mach_messages_received": after.messages_received - before.messages_received,
            "threads": after.thread_count,
        }
        destination = root / "artifacts/idle-performance.json"
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()


if __name__ == "__main__":
    main()
