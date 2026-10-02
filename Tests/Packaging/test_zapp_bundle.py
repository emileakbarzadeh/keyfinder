import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "check_zapp_bundle", Path(__file__).resolve().parents[2] / "scripts/check-zapp-bundle.py"
)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class ZappBundleChecks(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.app = Path(self.directory.name) / "Fixture.app"
        self.helper = self.app / "Contents/Helpers/zapp"
        self.helper.parent.mkdir(parents=True)
        self.helper.write_bytes(b"fixture: never executed")
        self.helper.chmod(0o755)
        self.licenses = self.app / "Contents/Resources/Licenses/Zapp"
        self.licenses.mkdir(parents=True)
        (self.licenses / "LICENSE").write_text("Test fixture")

    def run_check(self, library="/usr/lib/libSystem.B.dylib", commands="", help_text="Commands:\n  flash  Flash firmware\n"):
        with patch.object(checker.subprocess, "check_output", side_effect=[
            f"zapp:\n\t{library} (compatibility version 1.0.0, current version 1.0.0)\n",
            commands, help_text,
        ]) as command, patch("builtins.print"):
            checker.check(self.app, "otool")
            return command.call_args_list

    def test_standalone_backend_is_probed_with_help_only(self):
        calls = self.run_check()
        self.assertEqual(calls[-1].args[0], [str(self.helper), "--help"])
        self.assertEqual(calls[-1].kwargs["env"]["PATH"], "/usr/bin:/bin")

    def test_store_dependency_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "non-system runtime dependency"):
            self.run_check(library="/nix/store/example-libusb/lib/libusb.dylib")

    def test_unresolved_rpath_library_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "non-system runtime dependency"):
            self.run_check(library="@rpath/libusb.dylib")

    def test_store_rpath_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "Mach-O load commands"):
            self.run_check(commands="cmd LC_RPATH\npath /nix/store/example/lib (offset 12)")

    def test_backend_without_flash_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "flash command"):
            self.run_check(help_text="Usage: unrelated program")

    def test_description_alone_does_not_establish_flash_subcommand(self):
        with self.assertRaisesRegex(RuntimeError, "flash command"):
            self.run_check(help_text="Use this tool to flash a keyboard.\nUsage: zapp firmware.bin\n")

    def test_missing_license_is_rejected(self):
        (self.licenses / "LICENSE").unlink()
        with self.assertRaisesRegex(RuntimeError, "upstream license"):
            self.run_check()

    def test_backend_symlink_is_rejected(self):
        target = self.helper.with_name("target")
        self.helper.rename(target)
        self.helper.symlink_to(target)
        with self.assertRaisesRegex(RuntimeError, "executable copy"):
            checker.check(self.app, "otool")


if __name__ == "__main__":
    unittest.main()
