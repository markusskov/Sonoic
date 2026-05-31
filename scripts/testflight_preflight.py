#!/usr/bin/env python3
"""Run local, secret-safe checks before a Sonoic TestFlight candidate."""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]

INFO_PLIST = ROOT / "SonoicApp/Info.plist"
APP_ENTITLEMENTS = ROOT / "SonoicApp/Sonoic.entitlements"
WIDGET_ENTITLEMENTS = ROOT / "SonoicWidgetsExtension.entitlements"
OAUTH_CONFIG = ROOT / "Config/SonoicOAuth.xcconfig"
OAUTH_LOCAL_EXAMPLE = ROOT / "Config/SonoicOAuth.local.example.xcconfig"
OAUTH_LOCAL = ROOT / "Config/SonoicOAuth.local.xcconfig"
WORKER_PACKAGE = ROOT / "sonoic-sonos-worker/package.json"
WORKER_WRANGLER = ROOT / "sonoic-sonos-worker/wrangler.jsonc"
WORKER_README = ROOT / "sonoic-sonos-worker/README.md"
WORKER_SOURCE = ROOT / "sonoic-sonos-worker/src/index.ts"

REQUIRED_DOCS = [
    ROOT / "docs/TESTFLIGHT_READINESS.md",
    ROOT / "docs/SECURITY.md",
    ROOT / "docs/RELIABILITY.md",
    ROOT / "docs/sonos-oauth-dev-setup.md",
]

OAUTH_BUNDLE_KEYS = [
    "SonoicSonosOAuthClientID",
    "SonoicSonosOAuthRedirectURI",
    "SonoicSonosOAuthTokenExchangeURL",
    "SonoicSonosOAuthTokenRefreshURL",
    "SonoicSonosCloudQueueCreateURL",
]

OAUTH_CONFIG_KEYS = [
    "SONOS_OAUTH_CLIENT_ID",
    "SONOS_OAUTH_REDIRECT_URI",
    "SONOS_OAUTH_TOKEN_EXCHANGE_URL",
    "SONOS_OAUTH_TOKEN_REFRESH_URL",
    "SONOS_CLOUD_QUEUE_CREATE_URL",
]

LIKELY_SECRET_PATTERNS = [
    ("GitHub token", re.compile(r"\bgh[opsu]_[A-Za-z0-9_]{20,}\b")),
    ("Stripe or RevenueCat-style secret key", re.compile(r"\b(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{16,}\b")),
    ("JWT", re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b")),
    ("private key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("assigned Sonos client secret", re.compile(r"\bSONOS_CLIENT_SECRET\s*=\s*[^<\s#][^\n]*")),
]

BINARY_SUFFIXES = {
    ".appiconset",
    ".car",
    ".cer",
    ".gif",
    ".heic",
    ".icns",
    ".jpg",
    ".jpeg",
    ".keychain",
    ".mobileprovision",
    ".p12",
    ".pdf",
    ".png",
    ".webp",
    ".xcarchive",
}

FORBIDDEN_TRACKED_SUFFIXES = [
    ".env",
    ".local.xcconfig",
    ".mobileprovision",
    ".p12",
    ".cer",
    ".keychain",
    ".xcarchive",
]


class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def require(self, condition: bool, message: str) -> None:
        if not condition:
            self.errors.append(message)

    def warn(self, condition: bool, message: str) -> None:
        if not condition:
            self.warnings.append(message)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--strict-git", action="store_true", help="fail when tracked changes are present")
    parser.add_argument("--run-harness", action="store_true", help="run scripts/agent_harness_check.py")
    parser.add_argument("--run-worker-tests", action="store_true", help="run npm test in sonoic-sonos-worker")
    parser.add_argument("--run-generic-build", action="store_true", help="run generic iOS build")
    args = parser.parse_args()

    report = Report()
    check_required_docs(report)
    check_git_state(report, strict=args.strict_git)
    check_info_plist(report)
    check_entitlements(report)
    check_oauth_config(report)
    check_worker_config(report)
    check_oauth_worker_alignment(report)
    check_tracked_file_hygiene(report)
    check_likely_secret_literals(report)

    if args.run_harness:
        run_checked(report, ["python3", "scripts/agent_harness_check.py"], "agent harness")
    if args.run_worker_tests:
        run_checked(report, ["npm", "test"], "Worker tests", cwd=ROOT / "sonoic-sonos-worker")
    if args.run_generic_build:
        run_checked(
            report,
            [
                "xcodebuild",
                "-project",
                "Sonoic.xcodeproj",
                "-scheme",
                "Sonoic",
                "-destination",
                "generic/platform=iOS",
                "CODE_SIGNING_ALLOWED=NO",
                "build",
            ],
            "generic iOS build",
        )

    print_report(report)
    return 1 if report.errors else 0


def check_required_docs(report: Report) -> None:
    for path in REQUIRED_DOCS:
        report.require(path.is_file(), f"Missing release-readiness doc: {path.relative_to(ROOT)}")


def check_git_state(report: Report, *, strict: bool) -> None:
    result = run_capture(["git", "status", "--porcelain"])
    if result is None:
        report.warnings.append("Could not inspect git status.")
        return

    tracked_changes = [
        line for line in result.stdout.splitlines()
        if line and not line.startswith("?? ")
    ]
    if tracked_changes and strict:
        report.errors.append("Tracked changes are present; commit or stash before release preflight.")
    elif tracked_changes:
        report.warnings.append("Tracked changes are present; review before building a TestFlight candidate.")

    unexpected_untracked = [
        line for line in result.stdout.splitlines()
        if line.startswith("?? ") and not line.startswith("?? .charles/")
    ]
    if unexpected_untracked:
        report.warnings.append("Untracked files other than .charles/ are present; review before release.")


def check_info_plist(report: Report) -> None:
    info = read_plist(INFO_PLIST, report)
    if not isinstance(info, dict):
        return

    url_types = info.get("CFBundleURLTypes")
    schemes: list[str] = []
    if isinstance(url_types, list):
        for entry in url_types:
            if isinstance(entry, dict) and isinstance(entry.get("CFBundleURLSchemes"), list):
                schemes.extend(str(scheme) for scheme in entry["CFBundleURLSchemes"])

    report.require("sonoic" in schemes, "Info.plist must register the sonoic URL scheme.")
    report.require(info.get("SonoicSonosOAuthCallbackScheme") == "sonoic", "OAuth callback scheme must be sonoic.")
    report.require("playback-control-all" in str(info.get("SonoicSonosOAuthScopes", "")), "OAuth scope must include playback-control-all.")

    for key in OAUTH_BUNDLE_KEYS:
        value = info.get(key)
        report.require(isinstance(value, str) and value.strip(), f"Info.plist missing {key}.")
        if isinstance(value, str):
            report.require(value.strip().startswith("$("), f"{key} should come from build settings, not a literal value.")

    report.require("Apple Music" in str(info.get("NSAppleMusicUsageDescription", "")), "Apple Music usage description is missing or vague.")
    report.require("local network" in str(info.get("NSLocalNetworkUsageDescription", "")).lower(), "Local network usage description is missing or vague.")

    ats = info.get("NSAppTransportSecurity")
    report.require(isinstance(ats, dict) and ats.get("NSAllowsLocalNetworking") is True, "ATS must allow local networking for Sonos discovery.")

    bonjour = info.get("NSBonjourServices")
    report.require(isinstance(bonjour, list) and "_sonos._tcp" in bonjour, "Bonjour services must include _sonos._tcp.")

    background_modes = info.get("UIBackgroundModes")
    report.require(isinstance(background_modes, list) and "audio" in background_modes, "UIBackgroundModes must include audio.")
    report.require(isinstance(background_modes, list) and "fetch" in background_modes, "UIBackgroundModes must include fetch.")

    bg_identifiers = info.get("BGTaskSchedulerPermittedIdentifiers")
    report.require(
        isinstance(bg_identifiers, list) and "com.markusskov.Sonoic.player-refresh" in bg_identifiers,
        "BGTaskSchedulerPermittedIdentifiers must include the player refresh task.",
    )


def check_entitlements(report: Report) -> None:
    app = read_plist(APP_ENTITLEMENTS, report)
    widget = read_plist(WIDGET_ENTITLEMENTS, report)
    if not isinstance(app, dict) or not isinstance(widget, dict):
        return

    key = "com.apple.security.application-groups"
    app_groups = app.get(key)
    widget_groups = widget.get(key)
    report.require(isinstance(app_groups, list) and bool(app_groups), "App entitlements need an App Group.")
    report.require(isinstance(widget_groups, list) and bool(widget_groups), "Widget entitlements need an App Group.")
    report.require(app_groups == widget_groups, "App and widget App Groups must match exactly.")


def check_oauth_config(report: Report) -> None:
    config = read_text(OAUTH_CONFIG, report)
    example = read_text(OAUTH_LOCAL_EXAMPLE, report)
    if config is None or example is None:
        return

    for key in OAUTH_CONFIG_KEYS:
        report.require(key in config, f"Config/SonoicOAuth.xcconfig missing {key}.")
        report.require(key in example, f"Local OAuth example missing {key}.")

    report.require('#include? "SonoicOAuth.local.xcconfig"' in config, "Default OAuth config should include optional local override.")
    report.require("SONOS_CLIENT_SECRET" not in config, "Default OAuth config must not reference SONOS_CLIENT_SECRET.")
    report.require("SONOS_CLIENT_SECRET" not in example, "Local OAuth example must not reference SONOS_CLIENT_SECRET.")

    if OAUTH_LOCAL.exists():
        report.warnings.append("Local OAuth override exists; verify it stays untracked and never paste its values into logs.")


def check_worker_config(report: Report) -> None:
    package_text = read_text(WORKER_PACKAGE, report)
    wrangler = read_text(WORKER_WRANGLER, report)
    worker_readme = read_text(WORKER_README, report)
    worker_source = read_text(WORKER_SOURCE, report)
    if package_text is None or wrangler is None or worker_readme is None or worker_source is None:
        return

    try:
        package = json.loads(package_text)
    except json.JSONDecodeError as error:
        report.errors.append(f"Could not parse {WORKER_PACKAGE.relative_to(ROOT)}: {error}")
        return

    scripts = package.get("scripts", {})
    report.require(isinstance(scripts, dict) and "test" in scripts, "Worker package must define npm test.")
    report.require(isinstance(scripts, dict) and "deploy" in scripts, "Worker package must define npm run deploy.")

    for key in ["SONOS_CLIENT_ID", "SONOS_REDIRECT_URI", "SONOIC_APP_REDIRECT_URI"]:
        report.require(key in wrangler, f"Worker wrangler config missing non-secret var {key}.")

    for binding in ["SONOS_BROKER_CODE_REDEMPTIONS", "SONOIC_CLOUD_QUEUES"]:
        report.require(binding in wrangler, f"Worker wrangler config missing Durable Object binding {binding}.")

    for route in [
        "/healthz",
        "/oauth/sonos/callback",
        "/api/sonos/token",
        "/api/sonos/token/refresh",
        "/api/sonos/events",
        "/api/sonos/cloud-queues",
    ]:
        report.require(route in worker_source, f"Worker source missing route {route}.")

    report.require(
        "Cache-Control" in worker_source and "no-store" in worker_source,
        "Worker JSON responses should include Cache-Control: no-store.",
    )
    report.require(
        "safeSonosTokenErrorDetail" in worker_source,
        "Worker token error responses should redact upstream details through safeSonosTokenErrorDetail.",
    )
    report.require("SONOS_CLIENT_SECRET" in worker_readme, "Worker README should document the Sonos client secret boundary.")
    report.require("BROKER_CODE_SIGNING_SECRET" in worker_readme, "Worker README should document broker-code signing secret.")


def check_oauth_worker_alignment(report: Report) -> None:
    example = read_text(OAUTH_LOCAL_EXAMPLE, report)
    wrangler = read_text(WORKER_WRANGLER, report)
    if example is None or wrangler is None:
        return

    app_redirect = normalized_xcconfig_url(xcconfig_value(example, "SONOS_OAUTH_REDIRECT_URI"))
    worker_redirect = quoted_config_value(wrangler, "SONOS_REDIRECT_URI")
    report.require(
        bool(app_redirect and worker_redirect and app_redirect == worker_redirect),
        "Local OAuth example redirect URI must match the Worker SONOS_REDIRECT_URI.",
    )

    origin = url_origin(app_redirect)
    if origin is None:
        report.errors.append("Local OAuth example redirect URI must be a valid HTTPS URL.")
        return

    expected_urls = {
        "SONOS_OAUTH_TOKEN_EXCHANGE_URL": f"{origin}/api/sonos/token",
        "SONOS_OAUTH_TOKEN_REFRESH_URL": f"{origin}/api/sonos/token/refresh",
        "SONOS_CLOUD_QUEUE_CREATE_URL": f"{origin}/api/sonos/cloud-queues",
    }
    for key, expected_url in expected_urls.items():
        actual_url = normalized_xcconfig_url(xcconfig_value(example, key))
        report.require(actual_url == expected_url, f"Local OAuth example {key} must be {expected_url}.")


def xcconfig_value(text: str, key: str) -> str | None:
    match = re.search(rf"^{re.escape(key)}\s*=\s*(.+?)\s*$", text, flags=re.MULTILINE)
    return match.group(1).strip() if match else None


def normalized_xcconfig_url(value: str | None) -> str | None:
    if value is None:
        return None

    return (
        value.strip()
        .replace("https:/$(SONOIC_EMPTY)/", "https://")
        .replace("http:/$(SONOIC_EMPTY)/", "http://")
    )


def quoted_config_value(text: str, key: str) -> str | None:
    match = re.search(rf'"{re.escape(key)}"\s*:\s*"([^"]+)"', text)
    return match.group(1).strip() if match else None


def url_origin(url: str | None) -> str | None:
    if url is None:
        return None

    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.netloc:
        return None

    return f"{parsed.scheme}://{parsed.netloc}"


def check_tracked_file_hygiene(report: Report) -> None:
    result = run_capture(["git", "ls-files"])
    if result is None:
        report.warnings.append("Could not inspect tracked files.")
        return

    for relative_path in result.stdout.splitlines():
        lowered = relative_path.lower()
        for suffix in FORBIDDEN_TRACKED_SUFFIXES:
            if lowered.endswith(suffix):
                report.errors.append(f"Release-sensitive local artifact is tracked: {relative_path}")


def check_likely_secret_literals(report: Report) -> None:
    result = run_capture(["git", "ls-files"])
    if result is None:
        return

    for relative_path in result.stdout.splitlines():
        path = ROOT / relative_path
        if should_skip_secret_scan(path):
            continue

        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue

        for line_number, line in enumerate(text.splitlines(), start=1):
            for label, pattern in LIKELY_SECRET_PATTERNS:
                if pattern.search(line):
                    report.errors.append(f"{relative_path}:{line_number} may contain a {label}; inspect without printing it.")


def should_skip_secret_scan(path: Path) -> bool:
    parts = path.relative_to(ROOT).parts
    if any(part in {"node_modules", ".git", "DerivedData", "build"} for part in parts):
        return True
    return path.suffix.lower() in BINARY_SUFFIXES


def read_plist(path: Path, report: Report) -> object | None:
    try:
        with path.open("rb") as handle:
            return plistlib.load(handle)
    except FileNotFoundError:
        report.errors.append(f"Missing plist: {path.relative_to(ROOT)}")
    except plistlib.InvalidFileException as error:
        report.errors.append(f"Could not parse plist {path.relative_to(ROOT)}: {error}")
    return None


def read_text(path: Path, report: Report) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as error:
        report.errors.append(f"Could not read {path.relative_to(ROOT)}: {error}")
        return None


def run_capture(command: list[str], *, cwd: Path = ROOT) -> subprocess.CompletedProcess[str] | None:
    try:
        return subprocess.run(command, cwd=cwd, check=True, capture_output=True, text=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


def run_checked(report: Report, command: list[str], label: str, *, cwd: Path = ROOT) -> None:
    print(f"\nRunning {label}...", flush=True)
    try:
        subprocess.run(command, cwd=cwd, check=True)
    except FileNotFoundError:
        report.errors.append(f"{label} command was not found: {command[0]}")
    except subprocess.CalledProcessError as error:
        report.errors.append(f"{label} failed with exit code {error.returncode}.")


def print_report(report: Report) -> None:
    print("\nSonoic TestFlight preflight")
    print("==========================")

    if report.errors:
        print("\nErrors:")
        for error in report.errors:
            print(f"- {error}")

    if report.warnings:
        print("\nWarnings:")
        for warning in report.warnings:
            print(f"- {warning}")

    if not report.errors:
        print("\nStatic preflight passed.")
        print("Manual device validation and App Store Connect/TestFlight checks are still required.")


if __name__ == "__main__":
    sys.exit(main())
