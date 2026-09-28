import copy
import difflib
import hashlib
import tempfile
import unittest
from pathlib import Path

import bootstrap


class ProbePatchTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="phone-probe-patch-test-")
        self.root = Path(self.directory.name)
        self.repo = self.root / "checkout"
        self.repo.mkdir()
        self.original = b"first\nsecond\n"
        self.patched = b"first\ndiagnostic\nsecond\n"
        (self.repo / "source.swift").write_bytes(self.original)
        bootstrap.run("git", "init", "-q", cwd=self.repo)
        bootstrap.run("git", "config", "core.autocrlf", "false", cwd=self.repo)
        bootstrap.run("git", "add", "source.swift", cwd=self.repo)
        bootstrap.run("git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                      "commit", "-qm", "fixture", cwd=self.repo)
        patch = ''.join(difflib.unified_diff(self.original.decode().splitlines(keepends=True),
            self.patched.decode().splitlines(keepends=True),
            fromfile="a/source.swift", tofile="b/source.swift")).encode()
        self.patch_path = self.root / "probe.patch"
        self.patch_path.write_bytes(patch)
        self.dependency = {"probePatch": {"path": str(self.patch_path),
            "sha256": hashlib.sha256(patch).hexdigest(), "files": {
                "source.swift": {"before": hashlib.sha256(self.original).hexdigest(),
                                 "after": hashlib.sha256(self.patched).hexdigest()}}}}

    def tearDown(self):
        self.directory.cleanup()

    def test_apply_and_repeat_preserve_exact_patch(self):
        bootstrap.prepare_probe_patch(self.repo, self.dependency)
        bootstrap.prepare_probe_patch(self.repo, self.dependency)
        self.assertEqual((self.repo / "source.swift").read_bytes(), self.patched)

    def test_unrecognized_edits_are_preserved_and_rejected(self):
        changed = b"a user's edit\n"
        (self.repo / "source.swift").write_bytes(changed)
        with self.assertRaises(RuntimeError):
            bootstrap.prepare_probe_patch(self.repo, self.dependency)
        self.assertEqual((self.repo / "source.swift").read_bytes(), changed)

    def test_edits_after_patching_are_preserved_and_rejected(self):
        bootstrap.prepare_probe_patch(self.repo, self.dependency)
        changed = self.patched + b"another edit\n"
        (self.repo / "source.swift").write_bytes(changed)
        with self.assertRaises(RuntimeError):
            bootstrap.prepare_probe_patch(self.repo, self.dependency)
        self.assertEqual((self.repo / "source.swift").read_bytes(), changed)

    def test_bad_patch_checksum_prevents_any_edit(self):
        dependency = copy.deepcopy(self.dependency)
        dependency["probePatch"]["sha256"] = "0" * 64
        with self.assertRaises(RuntimeError):
            bootstrap.prepare_probe_patch(self.repo, dependency)
        self.assertEqual((self.repo / "source.swift").read_bytes(), self.original)


if __name__ == "__main__":
    unittest.main()
