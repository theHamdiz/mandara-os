"""Create package state in a disposable root using systemd's own parser."""

import os
import pathlib
import stat
import subprocess
import tempfile
import unittest


FILES = pathlib.Path(__file__).resolve().parents[1] / "system_files/usr/lib/tmpfiles.d"


class RuntimeStateTests(unittest.TestCase):
    def test_tmpfiles_creates_state_and_keeps_existing_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / "etc").mkdir()
            # Map fixture accounts to the caller so the test also runs rootless.
            names = ("fixture-root", "greetd", "openvpn", "geoclue")
            (root / "etc/passwd").write_text("".join(
                f"{name}:x:{os.getuid()}:{os.getgid()}::/:/bin/false\n" for name in names
            ))
            (root / "etc/group").write_text("".join(
                f"{name}:x:{os.getgid()}:\n" for name in names
            ))
            configs = root / "usr/lib/tmpfiles.d"
            configs.mkdir(parents=True)
            for name in ("mandara-package-state.conf", "mandara-fedora-state.conf"):
                # systemd treats the literal root account as UID 0 even with
                # an offline passwd file. Substitute only that ownership.
                text = (FILES / name).read_text().replace(" root root ", " fixture-root fixture-root ")
                (configs / name).write_text(text)

            saved = root / "var/lib/openvpn/saved-state"
            saved.parent.mkdir(parents=True)
            saved.write_text("keep existing state\n")
            result = subprocess.run(
                ["systemd-tmpfiles", f"--root={root}", "--create"],
                capture_output=True, text=True, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, "")
            self.assertEqual(saved.read_text(), "keep existing state\n")
            for path, mode in (
                ("var/lib/AccountsService/users", 0o700),
                ("var/lib/bluetooth", 0o700),
                ("var/lib/geoclue", 0o755),
                ("var/lib/openvpn", 0o770),
                ("var/lib/power-profiles-daemon", 0o755),
                ("var/lib/plymouth", 0o755),
                ("var/spool/plymouth", 0o755),
            ):
                with self.subTest(path=path):
                    self.assertEqual(stat.S_IMODE((root / path).stat().st_mode), mode)
            portal = root / "var/lib/greetd/.config/systemd/user/xdg-desktop-portal.service"
            self.assertTrue(portal.is_symlink())
            self.assertEqual(portal.readlink(), pathlib.Path("/dev/null"))


if __name__ == "__main__":
    unittest.main()
