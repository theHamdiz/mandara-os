"""Keep app-specific defaults aligned with the OS font preference."""

import configparser
import pathlib
import tomllib
import unittest


FILES = pathlib.Path(__file__).resolve().parents[1] / "system_files"


class TypographyTests(unittest.TestCase):
    def test_gtk_versions_use_the_same_default(self):
        for version in ("3.0", "4.0"):
            with self.subTest(version=version):
                config = configparser.ConfigParser()
                config.read(FILES / f"etc/skel/.config/gtk-{version}/settings.ini")
                self.assertEqual(config["Settings"]["gtk-font-name"], "Alexandria 11")

    def test_shell_and_login_use_alexandria(self):
        shell = tomllib.loads((FILES / "etc/skel/.config/mandara/config.toml").read_text())
        for role in ("ui_font", "display_font", "arabic_font"):
            with self.subTest(role=role):
                self.assertEqual(shell["typography"][role], "Alexandria")
        login = tomllib.loads((FILES / "etc/mandara/greeter.toml").read_text())
        self.assertEqual(login["font"], "Alexandria")


if __name__ == "__main__":
    unittest.main()
