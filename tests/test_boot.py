"""Keep successful boots quiet without hiding failure diagnostics."""

import configparser
import pathlib
import shlex
import tomllib
import unittest


FILES = pathlib.Path(__file__).resolve().parents[1] / "system_files"


def greeter_command(files=FILES):
    config = tomllib.loads((files / "etc/greetd/config.toml").read_text())
    return shlex.split(config["default_session"]["command"])


def session_command(files=FILES):
    config = configparser.ConfigParser(interpolation=None)
    config.read(files / "usr/share/wayland-sessions/mango.desktop")
    return shlex.split(config["Desktop Entry"]["Exec"])


class BootTests(unittest.TestCase):
    def test_boot_status_only_shows_failures(self):
        arguments = []
        for path in (FILES / "usr/lib/bootc/kargs.d").glob("*.toml"):
            arguments.extend(tomllib.loads(path.read_text())["kargs"])
        status = [arg for arg in arguments if arg.startswith("systemd.show_status=")]
        self.assertEqual(status, ["systemd.show_status=error"])
        self.assertIn("quiet", arguments)
        self.assertIn("splash", arguments)
        # printk displays messages strictly below console_loglevel. Errors
        # must remain visible, with warning and informational chatter hidden.
        levels = [int(arg.split("=", 1)[1]) for arg in arguments if arg.startswith("loglevel=")]
        self.assertEqual(levels, [4])

    def test_greeter_logs_to_journal_and_keeps_its_kiosk_flags(self):
        self.assertEqual(greeter_command(), [
            "/usr/bin/systemd-cat", "--identifier=mandara-greeter",
            "/usr/bin/cage", "-s", "-m", "last", "--",
            "/usr/lib/mandara/mandara-bin", "greeter",
        ])

    def test_desktop_session_logs_to_journal(self):
        self.assertEqual(session_command(), [
            "/usr/bin/systemd-cat", "--identifier=mandara-session", "/usr/bin/mango",
        ])
        config = configparser.ConfigParser(interpolation=None)
        config.read(FILES / "usr/share/wayland-sessions/mango.desktop")
        self.assertEqual(config["Desktop Entry"]["DesktopNames"], "mango;wlroots")

    def test_plymouth_handoff_retains_the_splash(self):
        dropin = FILES / "usr/lib/systemd/system/plymouth-quit.service.d/10-mandara-retain-splash.conf"
        self.assertIn("ExecStart=-/usr/bin/plymouth quit --retain-splash", dropin.read_text())
        for path in (FILES / "usr/lib/systemd/system/greetd.service.d").glob("*.conf"):
            self.assertNotIn("Conflicts=plymouth-quit", path.read_text())


if __name__ == "__main__":
    unittest.main()
