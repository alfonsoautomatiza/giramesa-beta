from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "scripts" / "validate_public_repo.py"
SPEC = importlib.util.spec_from_file_location("validate_public_repo", MODULE_PATH)
validator = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
sys.modules[SPEC.name] = validator
SPEC.loader.exec_module(validator)


class PublicRepositoryValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_directory.name)
        self._write_minimum_safe_repository()

    def tearDown(self):
        self.temp_directory.cleanup()

    def _write(self, relative: str, content: str = "") -> None:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def _write_minimum_safe_repository(self) -> None:
        for relative in validator.REQUIRED_FILES:
            self._write(relative)
        self._write("README.md", "# Safe repository\n")
        self._write("docs/index.html", "<!doctype html><html lang=\"es\"><title>Giramesa</title><link rel=\"stylesheet\" href=\"styles.css\"><main><h1>Giramesa</h1></main></html>")
        self._write("docs/config.js", "window.GIRAMESA_CONFIG={githubRepository:'wertyMSD/giramesa-beta',testFlightUrl:''};")
        self._write("docs/assets/mark.svg", '<svg xmlns="http://www.w3.org/2000/svg"/>')
        manifest = {
            "version": "1.2.3",
            "android": {"asset": "giramesa-1.2.3.apk", "sha256": "a" * 64},
            "ios": {"testFlightUrl": "", "version": ""},
            "releaseNotes": ["Safe change"],
        }
        self._write("release/release-manifest.example.json", json.dumps(manifest))
        self._write("release/release-manifest.schema.json", "{}")

    def error_codes(self):
        return {issue.code for issue in validator.validate_repository(self.root) if issue.severity == "error"}

    def test_safe_repository_has_no_errors_and_keeps_disabled_testflight_visible(self):
        issues = validator.validate_repository(self.root)
        self.assertFalse([issue for issue in issues if issue.severity == "error"])
        self.assertIn("testflight-disabled", {issue.code for issue in issues})

    def test_release_binary_in_tree_is_rejected(self):
        self._write("release/giramesa-1.2.3.apk", "not a real binary")
        self.assertIn("forbidden-file", self.error_codes())

    def test_ipa_is_rejected_even_when_named_as_a_test_asset(self):
        self._write("release/test-build.ipa", "not a real binary")
        self.assertIn("forbidden-file", self.error_codes())

    def test_secret_match_is_reported_without_exposing_the_value(self):
        secret = "gh" + "p_" + "A" * 36
        self._write("docs/unsafe.js", f"const credential = '{secret}';")
        issues = validator.validate_repository(self.root)
        report = "\n".join(issue.detail for issue in issues)
        self.assertIn("potential-secret", {issue.code for issue in issues})
        self.assertNotIn(secret, report)

    def test_broken_markdown_link_is_rejected(self):
        self._write("README.md", "[Missing](docs/not-here.html)")
        self.assertIn("broken-local-reference", self.error_codes())

    def test_image_without_alt_text_is_rejected(self):
        self._write("docs/index.html", "<!doctype html><html lang=\"es\"><main><h1>Giramesa</h1><img src=\"assets/mark.svg\"></main></html>")
        self.assertIn("image-alt", self.error_codes())

    def test_manifest_rejects_nonconforming_apk_name(self):
        data = json.loads((self.root / "release/release-manifest.example.json").read_text())
        data["android"]["asset"] = "app-release.apk"
        self._write("release/release-manifest.example.json", json.dumps(data))
        self.assertIn("apk-name", self.error_codes())

    def test_official_testflight_link_is_accepted(self):
        self._write("docs/config.js", "window.GIRAMESA_CONFIG={githubRepository:'wertyMSD/giramesa-beta',testFlightUrl:'https://testflight.apple.com/join/Ab12Cd34'};")
        issues = validator.validate_repository(self.root)
        config_codes = {issue.code for issue in issues if "testflight" in issue.code}
        self.assertFalse(config_codes)


if __name__ == "__main__":
    unittest.main()
