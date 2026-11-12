"""Check ISO labels against the builder's supported architecture expansion."""

import pathlib
import re
import tomllib
import unittest


REPO = pathlib.Path(__file__).resolve().parents[1]


class InstallerTests(unittest.TestCase):
    def test_iso_label_fits_iso9660_on_both_architectures(self):
        config = tomllib.loads((REPO / "disk_config/iso.toml").read_text())
        template = config["customizations"]["iso"]["volume_id"]
        for architecture in ("x86_64", "aarch64"):
            with self.subTest(architecture=architecture):
                label = template.replace("$arch", architecture)
                self.assertLessEqual(len(label.encode("ascii")), 32)
                self.assertTrue(re.fullmatch(r"[A-Za-z0-9_-]+", label), label)
                self.assertTrue(label.startswith("Mandara-OS-"), label)


if __name__ == "__main__":
    unittest.main()
