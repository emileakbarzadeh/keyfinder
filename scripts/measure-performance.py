#!/usr/bin/env python3
"""Measure Keyfinder's CPU, wakeups, energy, and memory from a separate process.

By default, launch the packaged app with --background and measure it idle; unplug
the keyboard for the idle baseline. With --attach, sample the Keyfinder that is
already running while you use the keyboard, and split the run into idle, typing,
and overlay intervals. Every HID report wakes the main thread, so the
context-switch rate separates idle from typing. HID reports do not appear in the
Mach-message counter, but each overlay show, relabel, or hide exchanges dozens
of messages with the window server, which catches overlays that appear and hide
between samples. Keep Settings closed, and leave the keyboard alone for part of
the run so typing can be compared with a baseline.

CPU-time counters from proc_pidinfo and proc_pid_rusage are Mach ticks, not
nanoseconds. On Apple Silicon a tick is 125/3 ns, so dividing by 1e9 understates
CPU time by about 42 times. Convert through ticks_to_seconds; every run checks
the result against ps and stops if they disagree.
"""
import argparse
import ctypes
import datetime
import json
import pathlib
import platform
import plistlib
import subprocess
import sys
import time

_libproc = ctypes.CDLL("/usr/lib/libproc.dylib")
_libproc.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_int]
_libproc.proc_pidinfo.restype = ctypes.c_int
_libproc.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
_libproc.proc_pid_rusage.restype = ctypes.c_int
_cf = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
_cg = ctypes.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
_cg.CGWindowListCopyWindowInfo.argtypes = [ctypes.c_uint32, ctypes.c_uint32]
_cg.CGWindowListCopyWindowInfo.restype = ctypes.c_void_p
_cg.CGWindowLevelForKey.argtypes = [ctypes.c_int32]
_cg.CGWindowLevelForKey.restype = ctypes.c_int32
_cf.CFArrayGetCount.argtypes = [ctypes.c_void_p]
_cf.CFArrayGetCount.restype = ctypes.c_long
_cf.CFArrayGetValueAtIndex.argtypes = [ctypes.c_void_p, ctypes.c_long]
_cf.CFArrayGetValueAtIndex.restype = ctypes.c_void_p
_cf.CFDictionaryGetValue.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
_cf.CFDictionaryGetValue.restype = ctypes.c_void_p
_cf.CFNumberGetValue.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
_cf.CFNumberGetValue.restype = ctypes.c_bool
_cf.CFStringCreateWithCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32]
_cf.CFStringCreateWithCString.restype = ctypes.c_void_p
_cf.CFRelease.argtypes = [ctypes.c_void_p]
_KEYS = {name: _cf.CFStringCreateWithCString(None, name.encode(), 0x08000100)
         for name in ("kCGWindowOwnerPID", "kCGWindowLayer", "kCGWindowBounds", "Height")}
_STATUS_LEVEL = _cg.CGWindowLevelForKey(9)  # kCGStatusWindowLevelKey; the overlay panel uses .statusBar
OVERLAY_MESSAGES = 8  # Mach messages in one interval that mark overlay drawing (observed 11–121; typing ≤ 5)
MIB = 1024 * 1024


class TaskInfo(ctypes.Structure):
    """struct proc_taskinfo from <sys/proc_info.h>. Times are Mach ticks."""
    _fields_ = [(name, ctypes.c_uint64) for name in (
        "virtual_size", "resident_size", "total_user", "total_system", "threads_user", "threads_system"
    )] + [(name, ctypes.c_int32) for name in (
        "policy", "faults", "pageins", "cow_faults", "messages_sent", "messages_received",
        "syscalls_mach", "syscalls_unix", "context_switches", "thread_count", "running_threads", "priority"
    )]


class RusageInfoV6(ctypes.Structure):
    """struct rusage_info_v6 from <sys/resource.h>. Times are Mach ticks; energy is nanojoules."""
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [(name, ctypes.c_uint64) for name in (
        "user_time", "system_time", "pkg_idle_wkups", "interrupt_wkups", "pageins", "wired_size",
        "resident_size", "phys_footprint", "proc_start_abstime", "proc_exit_abstime",
        "child_user_time", "child_system_time", "child_pkg_idle_wkups", "child_interrupt_wkups",
        "child_pageins", "child_elapsed_abstime", "diskio_bytesread", "diskio_byteswritten",
        "cpu_time_qos_default", "cpu_time_qos_maintenance", "cpu_time_qos_background",
        "cpu_time_qos_utility", "cpu_time_qos_legacy", "cpu_time_qos_user_initiated",
        "cpu_time_qos_user_interactive", "billed_system_time", "serviced_system_time",
        "logical_writes", "lifetime_max_phys_footprint", "instructions", "cycles", "billed_energy",
        "serviced_energy", "interval_max_phys_footprint", "runnable_time", "flags", "user_ptime",
        "system_ptime", "pinstructions", "pcycles", "energy_nj", "penergy_nj",
        "secure_time_in_system", "secure_ptime_in_system", "neural_footprint",
        "lifetime_max_neural_footprint", "interval_max_neural_footprint",
    )] + [("reserved", ctypes.c_uint64 * 9)]


class _Timebase(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]


_timebase = _Timebase()
ctypes.CDLL("/usr/lib/libSystem.dylib").mach_timebase_info(ctypes.byref(_timebase))


def ticks_to_seconds(ticks):
    return ticks * _timebase.numer / _timebase.denom / 1e9


def task_info(pid):
    info = TaskInfo()
    if _libproc.proc_pidinfo(pid, 4, 0, ctypes.byref(info), ctypes.sizeof(info)) != ctypes.sizeof(info):  # PROC_PIDTASKINFO
        raise RuntimeError(f"Could not read task info for PID {pid}; has it exited?")
    return info


def rusage(pid):
    info = RusageInfoV6()
    if _libproc.proc_pid_rusage(pid, 6, ctypes.byref(info)) != 0:  # RUSAGE_INFO_V6
        raise RuntimeError(f"Could not read resource usage for PID {pid}; has it exited?")
    return info


def cpu_seconds(usage):
    return ticks_to_seconds(usage.user_time + usage.system_time)


def verify_cpu_units(pid):
    """Cross-check converted CPU time against ps, which converts units itself."""
    ours = cpu_seconds(rusage(pid))
    theirs = 0.0
    for part in subprocess.run(["ps", "-o", "time=", "-p", str(pid)], capture_output=True, text=True,
                               check=True).stdout.strip().split(":"):  # [[hh:]mm:]ss.cc
        theirs = theirs * 60 + float(part)
    if abs(ours - theirs) > max(0.05, 0.1 * theirs):
        raise RuntimeError(f"CPU-time units are wrong: counters give {ours:.3f} s but ps reports {theirs:.3f} s")
    return ours


def _number(dictionary, key):
    value = ctypes.c_double()
    ref = _cf.CFDictionaryGetValue(dictionary, _KEYS[key])
    return value.value if ref and _cf.CFNumberGetValue(ref, 13, ctypes.byref(value)) else None  # kCFNumberDoubleType


def overlay_visible(pid):
    """True when the app has an on-screen status-level window taller than a menu bar item."""
    windows = _cg.CGWindowListCopyWindowInfo(1, 0)  # kCGWindowListOptionOnScreenOnly, kCGNullWindowID
    if not windows:
        return None
    try:
        for index in range(_cf.CFArrayGetCount(windows)):
            window = _cf.CFArrayGetValueAtIndex(windows, index)
            if _number(window, "kCGWindowOwnerPID") != pid or _number(window, "kCGWindowLayer") != _STATUS_LEVEL:
                continue
            bounds = _cf.CFDictionaryGetValue(window, _KEYS["kCGWindowBounds"])
            if bounds and (_number(bounds, "Height") or 0) >= 80:
                return True
        return False
    finally:
        _cf.CFRelease(windows)


def snapshot(pid):
    usage, task = rusage(pid), task_info(pid)
    return {
        "time": time.monotonic(),
        "cpu_seconds": cpu_seconds(usage),
        "instructions": usage.instructions,
        "energy_nj": usage.energy_nj,
        "interrupt_wakeups": usage.interrupt_wkups,
        "package_idle_wakeups": usage.pkg_idle_wkups,
        "mach_messages_received": task.messages_received,
        "context_switches": task.context_switches,
        "footprint_bytes": usage.phys_footprint,
        "lifetime_max_footprint_bytes": usage.lifetime_max_phys_footprint,
        "resident_bytes": task.resident_size,
        "threads": task.thread_count,
        "overlay_visible": overlay_visible(pid),
    }


COUNTERS = ("cpu_seconds", "instructions", "energy_nj", "interrupt_wakeups",
            "package_idle_wakeups", "mach_messages_received", "context_switches")


def summarize(deltas):
    seconds = sum(item["seconds"] for item in deltas)
    if not seconds:
        return None
    total = {name: sum(item[name] for item in deltas) for name in COUNTERS}
    return {
        "seconds": round(seconds, 2),
        "cpu_seconds": round(total["cpu_seconds"], 6),
        "cpu_percent_of_one_core": round(total["cpu_seconds"] / seconds * 100, 6),
        "average_power_mw": round(total["energy_nj"] / seconds / 1e6, 4),
        "interrupt_wakeups_per_second": round(total["interrupt_wakeups"] / seconds, 3),
        "package_idle_wakeups_per_second": round(total["package_idle_wakeups"] / seconds, 3),
        "mach_messages_per_second": round(total["mach_messages_received"] / seconds, 3),
        "context_switches_per_second": round(total["context_switches"] / seconds, 3),
        "totals": total,
    }


def find_running_pid():
    found = subprocess.run(["pgrep", "-f", r"Keyfinder\.app/Contents/MacOS/Keyfinder( |$)"],
                           capture_output=True, text=True).stdout.split()
    if len(found) != 1:
        sys.exit(f"Found {len(found)} running Keyfinder processes {found}; pass --pid.")
    return int(found[0])


def conditions(pid):
    executable = subprocess.run(["ps", "-o", "comm=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    plist = pathlib.Path(executable).parent.parent / "Info.plist"
    keyboards = subprocess.run(["hidutil", "list", "--matching", '{"VendorID":12951}'],
                               capture_output=True, text=True).stdout
    return {
        "pid": pid,
        "executable": executable,
        "app_version": plistlib.loads(plist.read_bytes()).get("CFBundleShortVersionString") if plist.exists() else None,
        "process_uptime": subprocess.run(["ps", "-o", "etime=", "-p", str(pid)], capture_output=True, text=True).stdout.strip(),
        "macos": platform.mac_ver()[0],
        "cpu": subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], capture_output=True, text=True).stdout.strip(),
        "zsa_keyboards_connected": [name for name in ("Moonlander", "Voyager", "ErgoDox") if name in keyboards],
    }


def measure_idle(args):
    process = subprocess.Popen([str(args.app.resolve() / "Contents/MacOS/Keyfinder"), "--background"],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        time.sleep(3)  # Exclude process startup; this timer is in the measurement tool.
        if process.poll() is not None:
            raise RuntimeError(f"Keyfinder exited before sampling: {process.communicate()}")
        startup_cpu = verify_cpu_units(process.pid)
        before = snapshot(process.pid)
        time.sleep(args.seconds)
        if process.poll() is not None:
            raise RuntimeError(f"Keyfinder exited during sampling: {process.communicate()}")
        after = snapshot(process.pid)
        delta = {name: after[name] - before[name] for name in COUNTERS}
        delta["seconds"] = after["time"] - before["time"]
        return {
            "app": str(args.app.resolve()),
            "conditions": conditions(process.pid) | {
                "notes": "Packaged release app, --background, settings closed. Disconnect the keyboard for an idle baseline."},
            "startup_cpu_seconds": round(startup_cpu, 4),
            "idle": summarize([delta]),
            "footprint_mib": round(after["footprint_bytes"] / MIB, 2),
            "resident_memory_mib": round(after["resident_bytes"] / MIB, 2),
            "threads": after["threads"],
        }
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()


def measure_attached(args):
    pid = args.pid or find_running_pid()
    verify_cpu_units(pid)
    info = conditions(pid)
    if not info["zsa_keyboards_connected"]:
        print("warning: no ZSA keyboard is connected; typing will not reach Keyfinder", file=sys.stderr)
    print(f"Sampling Keyfinder {info['app_version']} (PID {pid}) for {args.seconds:g} s. "
          "Leave the keyboard alone for part of the run, then type.", file=sys.stderr)
    samples = [snapshot(pid)]
    for tick in range(1, int(args.seconds / args.interval) + 1):
        time.sleep(max(0, samples[0]["time"] + tick * args.interval - time.monotonic()))
        samples.append(snapshot(pid))

    intervals = []
    for before, after in zip(samples, samples[1:]):
        delta = {name: after[name] - before[name] for name in COUNTERS}
        delta["seconds"] = after["time"] - before["time"]
        if before["overlay_visible"] or after["overlay_visible"] or delta["mach_messages_received"] >= OVERLAY_MESSAGES:
            delta["state"] = "overlay"
        elif delta["context_switches"] / delta["seconds"] >= args.typing_threshold:
            delta["state"] = "typing"
        else:
            delta["state"] = "idle"
        intervals.append(delta)
    phases = {state: summarize([row for row in intervals if row["state"] == state]) for state in ("idle", "typing", "overlay")}
    footprints = [sample["footprint_bytes"] for sample in samples]
    return {
        "conditions": info,
        "settings": {"seconds": args.seconds, "interval": args.interval, "typing_threshold": args.typing_threshold},
        "phases": phases,
        "overlay_appearances": sum(1 for a, b in zip(samples, samples[1:]) if b["overlay_visible"] and not a["overlay_visible"]),
        "memory": {
            "footprint_start_mib": round(footprints[0] / MIB, 2),
            "footprint_end_mib": round(footprints[-1] / MIB, 2),
            "footprint_max_mib": round(max(footprints) / MIB, 2),
            "lifetime_max_footprint_mib": round(samples[-1]["lifetime_max_footprint_bytes"] / MIB, 2),
            "threads": samples[-1]["threads"],
        },
        "notes": [
            "Each key press and each release is one HID report, and each report wakes Keyfinder's main thread.",
            "Overlay intervals include any typing in the same interval as an overlay show, relabel, or hide.",
            "CPU and energy are billed to Keyfinder only; kernel USB and WindowServer work is not included.",
        ],
        "intervals": [{k: round(v, 9) if isinstance(v, float) else v for k, v in row.items()} for row in intervals],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--app", type=pathlib.Path, help="Keyfinder.app to launch for the idle measurement")
    parser.add_argument("--attach", action="store_true", help="Sample the running Keyfinder instead of launching one")
    parser.add_argument("--pid", type=int, help="With --attach, the process to sample (default: the one running)")
    parser.add_argument("--seconds", type=float, help="Measurement length (default: 30 idle, 180 attached)")
    parser.add_argument("--interval", type=float, default=1.0, help="With --attach, seconds between samples")
    parser.add_argument("--typing-threshold", type=float, default=5.0,
                        help="With --attach, context switches per second at or above which an interval counts as typing")
    parser.add_argument("--output", type=pathlib.Path)
    args = parser.parse_args()
    args.seconds = args.seconds or (180 if args.attach else 30)
    if not 5 <= args.seconds <= 3600 or not 0.25 <= args.interval <= 10:
        parser.error("Use 5–3600 seconds and a 0.25–10 second interval.")
    if not args.attach and not args.app:
        parser.error("Pass --app to launch and measure idle, or --attach to sample the running app.")

    report = {"recorded_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds")}
    report |= measure_attached(args) if args.attach else measure_idle(args)
    destination = args.output or (pathlib.Path("artifacts/performance") / f"live-{time.strftime('%Y%m%d-%H%M%S')}.json"
                                  if args.attach else pathlib.Path("artifacts/idle-performance.json"))
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(report, indent=2) + "\n")

    phases = report.get("phases") or {"idle": report["idle"]}
    print(f"\n{'phase':<9}{'seconds':>8}{'CPU %':>11}{'mW':>9}{'wakeups/s':>11}{'idle wk/s':>11}{'ctx sw/s':>10}")
    for state, phase in phases.items():
        if phase:
            print(f"{state:<9}{phase['seconds']:>8.0f}{phase['cpu_percent_of_one_core']:>11.5f}{phase['average_power_mw']:>9.3f}"
                  f"{phase['interrupt_wakeups_per_second']:>11.2f}{phase['package_idle_wakeups_per_second']:>11.2f}"
                  f"{phase['context_switches_per_second']:>10.2f}")
    print(f"\nmemory: {json.dumps(report.get('memory') or {'footprint_mib': report['footprint_mib']})}")
    print(f"report: {destination}")


if __name__ == "__main__":
    main()
