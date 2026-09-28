import plistlib
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


class BackgroundIdentifierTests(unittest.TestCase):
    def test_configures_both_demo_apps_without_changing_other_entries(self):
        for name, suffix in [("CellUseDemo", "probe"), ("PlaylistMove", "move")]:
            with self.subTest(app=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                source, output = root / "input.ipa", root / "output.ipa"
                identifier = root / "bundle.txt"
                identifier.write_text("com.example.signed")
                entry = f"Payload/{name}.app/Info.plist"
                info = {"CFBundleIdentifier": "com.example.original",
                        "BGTaskSchedulerPermittedIdentifiers": [f"com.example.original.{suffix}.*"],
                        "CFBundleVersion": "5"}
                with zipfile.ZipFile(source, "w") as archive:
                    archive.writestr(entry, plistlib.dumps(info))
                    archive.writestr(f"Payload/{name}.app/{name}", b"unchanged executable")
                original = source.read_bytes()
                result = subprocess.run([sys.executable, str(Path(__file__).with_name("configure-background-identifier.py")),
                    "--input", str(source), "--output", str(output), "--bundle-id-file", str(identifier)],
                    capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(source.read_bytes(), original)
                self.assertNotIn("com.example.signed", result.stdout)
                with zipfile.ZipFile(output) as archive:
                    configured = plistlib.loads(archive.read(entry))
                    self.assertEqual(configured["BGTaskSchedulerPermittedIdentifiers"], [f"com.example.signed.{suffix}.*"])
                    self.assertEqual(configured["CFBundleIdentifier"], info["CFBundleIdentifier"])
                    self.assertEqual(archive.read(f"Payload/{name}.app/{name}"), b"unchanged executable")


if __name__ == "__main__":
    unittest.main()
