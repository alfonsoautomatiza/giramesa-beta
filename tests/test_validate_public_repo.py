from __future__ import annotations

import importlib.util
import json
import subprocess
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
        repository_root = MODULE_PATH.parents[1]
        for relative in (
            "release-all.ps1",
            "private-repo-template/.github/workflows/release-test-builds.yml",
        ):
            self._write(relative, (repository_root / relative).read_text(encoding="utf-8"))

    def _initialize_git(self) -> None:
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)

    def error_codes(self):
        return {issue.code for issue in validator.validate_repository(self.root) if issue.severity == "error"}

    def test_safe_repository_has_no_errors_and_keeps_disabled_testflight_visible(self):
        issues = validator.validate_repository(self.root)
        self.assertFalse([issue for issue in issues if issue.severity == "error"])
        self.assertIn("testflight-disabled", {issue.code for issue in issues})

    def test_release_binary_in_tree_is_rejected(self):
        self._write("release/giramesa-1.2.3.apk", "not a real binary")
        self.assertIn("forbidden-file", self.error_codes())

    def test_ignored_release_work_apk_is_not_treated_as_repository_content(self):
        self._write(".gitignore", ".release-work/\n*.apk\n")
        self._write(".release-work/1.2.3/giramesa-1.2.3.apk", "local work product")
        self._initialize_git()
        self.assertNotIn("forbidden-file", self.error_codes())

    def test_tracked_apk_is_rejected_even_when_gitignored(self):
        tracked_apk = ".release-work/1.2.3/giramesa-1.2.3.apk"
        self._write(".gitignore", ".release-work/\n*.apk\n")
        self._write(tracked_apk, "tracked forbidden binary")
        self._initialize_git()
        subprocess.run(
            ["git", "-C", str(self.root), "add", "-f", tracked_apk],
            check=True,
        )
        self.assertIn("forbidden-file", self.error_codes())

    def test_android_release_script_declares_safety_contract(self):
        script = (MODULE_PATH.parents[1] / "publish-android-release.ps1").read_text(encoding="utf-8")
        required_markers = (
            "SupportsShouldProcess = $true",
            "flutter build apk",
            "--release",
            "apksigner",
            "Android Debug",
            "scripts\\validate_public_repo.py",
            "gh release create",
            ".release-work",
            "TestFlight requiere un flujo separado",
        )
        for marker in required_markers:
            with self.subTest(marker=marker):
                self.assertIn(marker, script)

    def test_release_controller_declares_dispatch_and_whatif_contract(self):
        script = (MODULE_PATH.parents[1] / "release-all.ps1").read_text(encoding="utf-8")
        for marker in (
            "SupportsShouldProcess = $true",
            "$WhatIfPreference",
            "gh workflow run",
            "release-test-builds.yml",
            "app/pubspec.yaml",
            "refs/remotes/origin/$Branch",
            "expected_commit_sha=$headSha",
            "AppRepositorySlug = 'wertyMSD/donde-comer'",
            "BetaRepositorySlug = 'wertyMSD/giramesa-beta'",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, script)

    def test_release_controller_has_no_version_or_build_number_parameters(self):
        script = (MODULE_PATH.parents[1] / "release-all.ps1").read_text(encoding="utf-8")
        param_block = validator._powershell_param_block(script)
        self.assertTrue(param_block)
        self.assertNotRegex(param_block, r"(?im)^\s*\[[^\]]+\]\$(?:Version|BuildNumber)\b|^\s*\$(?:Version|BuildNumber)\b")
        self.assertIn("[string]$AppRepository", param_block)

    def test_controller_and_workflow_dispatch_inputs_match_exactly(self):
        root = MODULE_PATH.parents[1]
        script = (root / "release-all.ps1").read_text(encoding="utf-8")
        workflow = (root / "private-repo-template/.github/workflows/release-test-builds.yml").read_text(encoding="utf-8")
        expected = {
            "expected_commit_sha", "beta_repository", "release_notes_base64", "api_base_url",
            "run_android", "run_web", "run_windows", "run_ios",
        }
        self.assertEqual(expected, validator._controller_dispatch_inputs(script))
        self.assertEqual(expected, validator._workflow_dispatch_inputs(workflow))
        self.assertNotIn("version", validator._workflow_dispatch_inputs(workflow))
        self.assertNotIn("build_number", validator._workflow_dispatch_inputs(workflow))

    def test_pubspec_is_the_only_release_version_authority(self):
        root = MODULE_PATH.parents[1]
        script = (root / "release-all.ps1").read_text(encoding="utf-8")
        workflow = (root / "private-repo-template/.github/workflows/release-test-builds.yml").read_text(encoding="utf-8")
        metadata = validator._workflow_job(workflow, "metadata")
        self.assertIn("Get-FlutterReleaseMetadata", script)
        self.assertIn("app/pubspec.yaml", script)
        self.assertIn("exactamente una clave top-level 'version:'", script)
        self.assertIn("app/pubspec.yaml", metadata)
        self.assertIn("exactly one top-level 'version:'", metadata)
        self.assertIn("release_version", metadata)
        self.assertIn("build_number", metadata)

    def test_workflow_has_four_isolated_platform_runners(self):
        workflow = (MODULE_PATH.parents[1] / "private-repo-template/.github/workflows/release-test-builds.yml").read_text(encoding="utf-8")
        expected = {
            "android": "runs-on: ubuntu-latest",
            "web": "runs-on: ubuntu-latest",
            "windows": "runs-on: windows-latest",
            "ios": "runs-on: macos-latest",
        }
        for job_name, runner in expected.items():
            with self.subTest(job=job_name):
                self.assertIn(runner, validator._workflow_job(workflow, job_name))

    def test_all_platform_jobs_consume_metadata_outputs(self):
        workflow = (MODULE_PATH.parents[1] / "private-repo-template/.github/workflows/release-test-builds.yml").read_text(encoding="utf-8")
        for job_name in ("android", "web", "windows", "ios"):
            job = validator._workflow_job(workflow, job_name)
            with self.subTest(job=job_name):
                self.assertIn("needs: metadata", job)
                self.assertIn("needs.metadata.outputs.release_version", job)
                self.assertIn("needs.metadata.outputs.build_number", job)

    def test_ios_is_testflight_only_and_publication_rejects_private_material(self):
        workflow = (MODULE_PATH.parents[1] / "private-repo-template/.github/workflows/release-test-builds.yml").read_text(encoding="utf-8")
        ios_job = validator._workflow_job(workflow, "ios")
        self.assertIn("build ipa --release", ios_job)
        self.assertIn("xcrun altool --upload-app", ios_job)
        self.assertNotIn("actions/upload-artifact", ios_job)
        self.assertNotIn("gh release", ios_job)
        publish_job = validator._workflow_job(workflow, "publish-public-release")
        for marker in ("*.ipa", "*.jks", "*.p12", "*.mobileprovision", "BETA_RELEASE_TOKEN"):
            with self.subTest(marker=marker):
                self.assertIn(marker, publish_job)
        self.assertNotIn("-name '*.ipa' -o -name '*.apk'", publish_job)
        self.assertIn("! -name '*.apk' ! -name '*.zip' ! -name '*.sha256'", publish_job)

    def test_github_actions_secret_reference_is_not_a_literal_secret(self):
        self._write("safe.yml", "password: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}\n")
        issues = validator.validate_text_safety(self.root)
        self.assertNotIn("potential-secret", {issue.code for issue in issues})

    def test_literal_assigned_secret_is_rejected(self):
        literal = "this-is-" + "a-literal-secret"
        assignment = "pass" + "word: " + f'"{literal}"\n'
        self._write("unsafe.yml", assignment)
        issues = validator.validate_text_safety(self.root)
        self.assertIn("potential-secret", {issue.code for issue in issues})

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
