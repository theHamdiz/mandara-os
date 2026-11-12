"""Build-time identity checks without changing the host's release files."""

import pathlib
import shlex
import subprocess
import tempfile
import unittest


REPO = pathlib.Path(__file__).resolve().parents[1]
BASE_RELEASE = '''NAME="Fedora Linux"
ID=fedora
VERSION_ID=45
PRETTY_NAME="Fedora Linux 45"
VERSION="45 (Forty Five)"
CPE_NAME="cpe:/o:fedoraproject:fedora:45"
SUPPORT_END=2027-12-08
LOGO=fedora-logo-icon
'''


class IdentityTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = pathlib.Path(self.directory.name)
        (self.root / "usr/lib/mandara").mkdir(parents=True)
        (self.root / "etc").mkdir()
        (self.root / "usr/lib/os-release").write_text(BASE_RELEASE)
        (self.root / "usr/lib/mandara/BUILD").write_text(
            "mandara 0.28.1, mango 0.18.5, scenefx 0.5\n"
        )
        # Both bases normally use a symlink; replace a regular override too.
        (self.root / "etc/os-release").write_text(BASE_RELEASE)

    def apply(self):
        return subprocess.run(
            ["bash", str(REPO / "build_files/identity.sh"), str(self.root)],
            capture_output=True, text=True, check=False,
        )

    def test_display_identity_and_base_compatibility(self):
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        values = dict(line.split("=", 1) for line in shlex.split(
            (self.root / "etc/os-release").read_text()
        ))
        self.assertEqual(values["NAME"], "Mandara OS")
        self.assertEqual(values["PRETTY_NAME"], "Mandara OS 0.28.1")
        self.assertEqual(values["IMAGE_ID"], "mandara-os")
        self.assertEqual(values["IMAGE_VERSION"], "0.28.1")
        self.assertEqual(values["OSTREE_VERSION"], "0.28.1")
        self.assertEqual(values["LOGO"], "org.mandara.studio")
        self.assertEqual(values["DEFAULT_HOSTNAME"], "mandara")
        self.assertEqual(values["ID"], "fedora")
        self.assertEqual(values["VERSION_ID"], "45")
        self.assertEqual(values["CPE_NAME"], "cpe:/o:fedoraproject:fedora:45")
        self.assertEqual(values["SUPPORT_END"], "2027-12-08")
        for name in ("system-release", "redhat-release"):
            self.assertEqual((self.root / "etc" / name).read_text(), "Mandara OS release 0.28.1\n")
        self.assertTrue((self.root / "etc/os-release").is_symlink())

    def test_reapplying_does_not_duplicate_keys(self):
        self.assertEqual(self.apply().returncode, 0)
        first = (self.root / "usr/lib/os-release").read_text()
        self.assertEqual(self.apply().returncode, 0)
        self.assertEqual((self.root / "usr/lib/os-release").read_text(), first)
        keys = [line.split("=", 1)[0] for line in first.splitlines()]
        self.assertEqual(len(keys), len(set(keys)))

    def test_invalid_version_leaves_identity_untouched(self):
        (self.root / "usr/lib/mandara/BUILD").write_text("mandara latest, mango 0.18.5\n")
        result = self.apply()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid Mandara version", result.stderr)
        self.assertEqual((self.root / "usr/lib/os-release").read_text(), BASE_RELEASE)

    def test_next_release_replaces_the_old_version(self):
        self.assertEqual(self.apply().returncode, 0)
        (self.root / "usr/lib/mandara/BUILD").write_text("mandara 0.29.0, mango 0.18.5\n")
        self.assertEqual(self.apply().returncode, 0)
        release = (self.root / "etc/os-release").read_text()
        self.assertNotIn("0.28.1", release)
        self.assertIn('PRETTY_NAME="Mandara OS 0.29.0"', release)
        self.assertIn('IMAGE_VERSION="0.29.0"', release)
        self.assertEqual((self.root / "etc/system-release").read_text(), "Mandara OS release 0.29.0\n")


if __name__ == "__main__":
    unittest.main()
