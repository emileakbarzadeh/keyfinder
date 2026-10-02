"""Fail packaging if the embedded backend needs Nix or lacks the flash command.

Only --help is executed. This check never writes to a keyboard.
"""

import argparse
import os
from pathlib import Path
import re
import subprocess


def check(app: Path, otool: str) -> None:
    helper = app / "Contents/Helpers/zapp"
    if helper.is_symlink() or not helper.is_file() or not os.access(helper, os.X_OK):
        raise RuntimeError("Zapp must be an executable copy inside the app")
    libraries = subprocess.check_output([otool, "-L", str(helper)], text=True)
    for line in libraries.splitlines()[1:]:
        library = line.strip().split(" (compatibility version", 1)[0]
        if not library.startswith(("/usr/lib/", "/System/Library/")):
            raise RuntimeError(f"Zapp has a non-system runtime dependency: {library}")
    commands = subprocess.check_output([otool, "-l", str(helper)], text=True)
    if "/nix/store/" in commands:
        raise RuntimeError("Zapp retains a Nix store path in its Mach-O load commands")
    help_text = subprocess.check_output(
        [str(helper), "--help"],
        text=True,
        stderr=subprocess.STDOUT,
        timeout=15,
        env={"PATH": "/usr/bin:/bin", "NO_COLOR": "1", "TERM": "dumb"},
    )
    if not re.search(r"(?m)^\s+flash(?:\s|$)", help_text):
        raise RuntimeError("The bundled Zapp does not advertise the flash command")
    if not any((app / "Contents/Resources/Licenses/Zapp").glob("LICENSE*")):
        raise RuntimeError("The bundled Zapp is missing its upstream license")
    print("Zapp: bundled executable, system libraries only, flash command available")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--otool", default="otool")
    args = parser.parse_args()
    check(args.app, args.otool)
