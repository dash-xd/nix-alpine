import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("release", Path(__file__).with_name("release.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

class ReleaseContractTests(unittest.TestCase):
    def test_calendar_versions(self):
        for value in ("2026.10.21", "2026.10.21.0", "2024.02.29", "2026.10.21.1"):
            self.assertTrue(release.version_valid(value), value)
        for value in ("2026.02.29", "2026.04.31", "2026.1.01", "v2026.10.21", "2026.10.21.01", "2026.10.21.18446744073709551616"):
            self.assertFalse(release.version_valid(value), value)

    def test_atomic_record(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "record.json"
            release.atomic_json(path, {"status": "candidate", "source_sha": "abc"})
            import json
            self.assertEqual(json.loads(path.read_text())["source_sha"], "abc")
            release.atomic_json(path, {"status": "qualified"})
            self.assertEqual(json.loads(path.read_text())["status"], "qualified")

if __name__ == "__main__":
    unittest.main()
