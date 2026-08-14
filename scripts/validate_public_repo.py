#!/usr/bin/env python3
"""Validate that this repository remains safe and coherent for public distribution."""

from __future__ import annotations

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit


REQUIRED_FILES = (
    "README.md",
    "PRODUCT.md",
    "DESIGN.md",
    "RELEASE_PROCESS.md",
    "SECURITY.md",
    "PRIVACY.md",
    "NOTICE.md",
    ".gitignore",
    "docs/index.html",
    "docs/styles.css",
    "docs/app.js",
    "docs/config.js",
    "docs/assets/mark.svg",
    "android/INSTALL.md",
    "ios/TESTFLIGHT.md",
    "release/release-manifest.example.json",
    "release/release-manifest.schema.json",
    ".github/workflows/pages.yml",
    ".github/workflows/validate.yml",
    ".github/ISSUE_TEMPLATE/bug-report.yml",
    "scripts/validate_public_repo.py",
    "tests/test_validate_public_repo.py",
)

FORBIDDEN_SUFFIXES = {
    ".apk", ".aab", ".apks", ".ipa", ".jks", ".keystore", ".p12", ".pfx",
    ".mobileprovision", ".provisionprofile",
}
FORBIDDEN_NAMES = {
    "google-services.json", "googleservice-info.plist", "mapping.txt",
}
TEXT_SUFFIXES = {
    ".css", ".html", ".js", ".json", ".md", ".py", ".svg", ".txt", ".yml", ".yaml",
}
APK_NAME = re.compile(r"^giramesa-[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?\.apk$")
SEMVER = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$")
SHA256 = re.compile(r"^[a-fA-F0-9]{64}$")
TESTFLIGHT_URL = re.compile(r"^https://testflight\.apple\.com/join/[A-Za-z0-9]+$")
REPOSITORY_SLUG = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")

SECRET_PATTERNS = (
    ("private-key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("github-token", re.compile(r"gh" + r"p_[A-Za-z0-9]{30,}")),
    ("github-fine-grained-token", re.compile(r"github_" + r"pat_[A-Za-z0-9_]{30,}")),
    ("aws-access-key", re.compile(r"AK" + r"IA[0-9A-Z]{16}")),
    ("assigned-secret", re.compile(
        r"(?i)(?:api[_-]?key|client[_-]?secret|password|access[_-]?token)\s*[:=]\s*['\"][^'\"\s]{8,}['\"]"
    )),
)
PLACEHOLDER_PATTERNS = (
    re.compile(r"\bOWNER/REPO\b", re.IGNORECASE),
    re.compile(r"\bCHANGEME\b", re.IGNORECASE),
    re.compile(r"\bREPLACE_ME\b", re.IGNORECASE),
)
MARKDOWN_LINK = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)(?:\s+['\"][^'\"]*['\"])?\)")
HTML_REFERENCE = re.compile(r"(?:href|src)\s*=\s*['\"]([^'\"]+)['\"]", re.IGNORECASE)
CSS_REFERENCE = re.compile(r"url\(\s*['\"]?([^)'\"]+)['\"]?\s*\)", re.IGNORECASE)


@dataclass(frozen=True)
class Issue:
    severity: str
    code: str
    path: str
    detail: str


class StaticHtmlAudit(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids: set[str] = set()
        self.duplicate_ids: set[str] = set()
        self.image_without_alt = 0
        self.h1_count = 0
        self.has_main = False
        self.language = ""

    def handle_starttag(self, tag: str, attrs) -> None:
        attributes = dict(attrs)
        element_id = attributes.get("id")
        if element_id:
            if element_id in self.ids:
                self.duplicate_ids.add(element_id)
            self.ids.add(element_id)
        if tag == "html":
            self.language = attributes.get("lang", "")
        elif tag == "main":
            self.has_main = True
        elif tag == "h1":
            self.h1_count += 1
        elif tag == "img" and "alt" not in attributes:
            self.image_without_alt += 1


def _issue(severity: str, code: str, path: Path | str, detail: str) -> Issue:
    return Issue(severity, code, Path(path).as_posix(), detail)


def iter_repository_files(root: Path):
    for path in sorted(root.rglob("*")):
        if path.is_file() and ".git" not in path.relative_to(root).parts:
            yield path


def validate_required_files(root: Path) -> list[Issue]:
    return [
        _issue("error", "required-file-missing", relative, "Required public repository file is missing.")
        for relative in REQUIRED_FILES
        if not (root / relative).is_file()
    ]


def validate_forbidden_files(root: Path) -> list[Issue]:
    issues = []
    for path in iter_repository_files(root):
        relative = path.relative_to(root)
        lower_name = path.name.lower()
        if path.suffix.lower() in FORBIDDEN_SUFFIXES or lower_name in FORBIDDEN_NAMES:
            issues.append(_issue("error", "forbidden-file", relative, "Forbidden binary, signing, mapping, or service file found."))
        if lower_name.startswith("service-account") and path.suffix.lower() == ".json":
            issues.append(_issue("error", "forbidden-file", relative, "Potential service account file found."))
    return issues


def validate_text_safety(root: Path) -> list[Issue]:
    issues = []
    for path in iter_repository_files(root):
        if path.suffix.lower() not in TEXT_SUFFIXES and path.name != ".gitignore":
            continue
        try:
            content = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            issues.append(_issue("error", "invalid-text-encoding", path.relative_to(root), "Text file is not valid UTF-8."))
            continue
        for label, pattern in SECRET_PATTERNS:
            if pattern.search(content):
                issues.append(_issue("error", "potential-secret", path.relative_to(root), f"Potential {label} pattern found; matched value suppressed."))
        for pattern in PLACEHOLDER_PATTERNS:
            if pattern.search(content):
                issues.append(_issue("error", "unresolved-placeholder", path.relative_to(root), "Unapproved placeholder marker found."))
    return issues


def _is_external_or_special(reference: str) -> bool:
    parsed = urlsplit(reference)
    return bool(parsed.scheme or parsed.netloc) or reference.startswith(("#", "mailto:", "tel:", "data:"))


def _references_for(path: Path, content: str):
    if path.suffix.lower() == ".md":
        yield from MARKDOWN_LINK.findall(content)
    elif path.suffix.lower() == ".html":
        yield from HTML_REFERENCE.findall(content)
    elif path.suffix.lower() == ".css":
        yield from CSS_REFERENCE.findall(content)


def validate_local_references(root: Path) -> list[Issue]:
    issues = []
    for path in iter_repository_files(root):
        if path.suffix.lower() not in {".css", ".html", ".md"}:
            continue
        content = path.read_text(encoding="utf-8")
        for raw_reference in _references_for(path, content):
            reference = raw_reference.strip()
            if not reference or _is_external_or_special(reference):
                continue
            clean_path = unquote(urlsplit(reference).path)
            if not clean_path:
                continue
            target = (path.parent / clean_path).resolve()
            try:
                target.relative_to(root.resolve())
            except ValueError:
                issues.append(_issue("error", "reference-outside-repository", path.relative_to(root), "Local reference escapes the repository."))
                continue
            if not target.exists():
                issues.append(_issue("error", "broken-local-reference", path.relative_to(root), f"Missing local target: {clean_path}"))
    return issues


def validate_xml_and_json(root: Path) -> list[Issue]:
    issues = []
    for path in iter_repository_files(root):
        relative = path.relative_to(root)
        try:
            if path.suffix.lower() == ".svg":
                ET.parse(path)
            elif path.suffix.lower() == ".json":
                json.loads(path.read_text(encoding="utf-8"))
        except (ET.ParseError, json.JSONDecodeError) as error:
            issues.append(_issue("error", "invalid-structured-file", relative, f"Invalid {path.suffix.lower()} syntax at line {getattr(error, 'lineno', '?')}."))
    return issues


def validate_html_accessibility(root: Path) -> list[Issue]:
    issues = []
    for path in iter_repository_files(root):
        if path.suffix.lower() != ".html":
            continue
        audit = StaticHtmlAudit()
        audit.feed(path.read_text(encoding="utf-8"))
        relative = path.relative_to(root)
        if not audit.language:
            issues.append(_issue("error", "html-language", relative, "HTML document must declare its language."))
        if not audit.has_main:
            issues.append(_issue("error", "html-main", relative, "HTML document must contain a main landmark."))
        if audit.h1_count != 1:
            issues.append(_issue("error", "html-h1", relative, "HTML document must contain exactly one h1."))
        if audit.image_without_alt:
            issues.append(_issue("error", "image-alt", relative, "Every image must declare alt text, including decorative images."))
        if audit.duplicate_ids:
            issues.append(_issue("error", "duplicate-html-id", relative, "HTML document contains duplicate id attributes."))
    return issues


def validate_manifest_data(data: object, path: str = "release manifest") -> list[Issue]:
    issues = []
    if not isinstance(data, dict):
        return [_issue("error", "manifest-shape", path, "Manifest root must be an object.")]

    required = {"version", "android", "ios", "releaseNotes"}
    if not required.issubset(data):
        issues.append(_issue("error", "manifest-shape", path, "Manifest is missing required top-level fields."))

    version = data.get("version")
    if not isinstance(version, str) or not SEMVER.fullmatch(version):
        issues.append(_issue("error", "manifest-version", path, "Version must use SemVer without a leading v."))

    android = data.get("android")
    if not isinstance(android, dict):
        issues.append(_issue("error", "manifest-android", path, "Android metadata must be an object."))
    else:
        asset = android.get("asset")
        checksum = android.get("sha256")
        if not isinstance(asset, str) or not APK_NAME.fullmatch(asset):
            issues.append(_issue("error", "apk-name", path, "Android asset must match giramesa-X.Y.Z.apk."))
        if not isinstance(checksum, str) or not SHA256.fullmatch(checksum):
            issues.append(_issue("error", "manifest-checksum", path, "Android SHA-256 must contain exactly 64 hexadecimal characters."))

    ios = data.get("ios")
    if not isinstance(ios, dict):
        issues.append(_issue("error", "manifest-ios", path, "iOS metadata must be an object."))
    else:
        testflight = ios.get("testFlightUrl")
        if not isinstance(testflight, str) or (testflight and not TESTFLIGHT_URL.fullmatch(testflight)):
            issues.append(_issue("error", "testflight-url", path, "TestFlight URL must be empty or use the official public invitation format."))

    notes = data.get("releaseNotes")
    if not isinstance(notes, list) or not notes or not all(isinstance(note, str) and note.strip() for note in notes):
        issues.append(_issue("error", "manifest-notes", path, "Release notes must be a non-empty list of text entries."))
    return issues


def validate_manifests(root: Path) -> list[Issue]:
    issues = []
    for relative in ("release/release-manifest.example.json", "release/release-manifest.json"):
        path = root / relative
        if path.is_file():
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                continue
            issues.extend(validate_manifest_data(data, relative))
    return issues


def validate_public_config(root: Path) -> list[Issue]:
    path = root / "docs/config.js"
    if not path.is_file():
        return []
    content = path.read_text(encoding="utf-8")
    repository_match = re.search(r"githubRepository:\s*['\"]([^'\"]*)['\"]", content)
    testflight_match = re.search(r"testFlightUrl:\s*['\"]([^'\"]*)['\"]", content)
    issues = []
    if not repository_match or not REPOSITORY_SLUG.fullmatch(repository_match.group(1)):
        issues.append(_issue("error", "repository-config", path.relative_to(root), "GitHub repository must be a public owner/name slug."))
    if not testflight_match:
        issues.append(_issue("error", "testflight-config", path.relative_to(root), "TestFlight configuration entry is missing."))
    elif not testflight_match.group(1):
        issues.append(_issue("warning", "testflight-disabled", path.relative_to(root), "TestFlight remains intentionally disabled until a public invitation exists."))
    elif not TESTFLIGHT_URL.fullmatch(testflight_match.group(1)):
        issues.append(_issue("error", "testflight-config", path.relative_to(root), "TestFlight URL is not an official public invitation."))
    return issues


def validate_repository(root: Path) -> list[Issue]:
    checks = (
        validate_required_files,
        validate_forbidden_files,
        validate_text_safety,
        validate_local_references,
        validate_xml_and_json,
        validate_html_accessibility,
        validate_manifests,
        validate_public_config,
    )
    issues = []
    for check in checks:
        issues.extend(check(root))
    return issues


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args(argv)
    root = args.root.resolve()
    issues = validate_repository(root)
    for issue in issues:
        print(f"{issue.severity.upper()}: {issue.code}: {issue.path}: {issue.detail}")
    errors = sum(issue.severity == "error" for issue in issues)
    warnings = sum(issue.severity == "warning" for issue in issues)
    print(f"Validation complete: {errors} error(s), {warnings} warning(s).")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
