#!/usr/bin/env python3
"""Validate Sonoic's agent harness structure."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]

REQUIRED_FILES = [
    "AGENTS.md",
    "ARCHITECTURE.md",
    "README.md",
    "CONTRIBUTING.md",
    "plan.md",
    "docs/agent-harness.md",
    "docs/design-docs/index.md",
    "docs/design-docs/core-beliefs.md",
    "docs/exec-plans/index.md",
    "docs/exec-plans/template.md",
    "docs/exec-plans/active/README.md",
    "docs/exec-plans/completed/README.md",
    "docs/exec-plans/tech-debt-tracker.md",
    "docs/generated/README.md",
    "docs/product-specs/index.md",
    "docs/references/index.md",
    "docs/QUALITY_SCORE.md",
    "docs/RELIABILITY.md",
    "docs/SECURITY.md",
]

REQUIRED_DIRS = [
    "docs/design-docs",
    "docs/exec-plans/active",
    "docs/exec-plans/completed",
    "docs/generated",
    "docs/product-specs",
    "docs/references",
    "scripts",
]

EXEC_PLAN_TEMPLATE_SECTIONS = [
    "## Goal",
    "## Scope",
    "## Acceptance Criteria",
    "## Validation",
    "## Decision Log",
    "## Progress",
]

FORBIDDEN_TRACKED_PATTERNS = [
    ".DS_Store",
    "DerivedData/",
    "build/",
    ".xcuserstate",
    ".xccheckout",
    ".xcscmblueprint",
    ".xcbkptlist",
    "xcuserdata/",
]

LINK_PATTERN = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")


def main() -> int:
    errors: list[str] = []

    errors.extend(check_required_paths())
    errors.extend(check_agents_size())
    errors.extend(check_exec_plan_template())
    errors.extend(check_markdown_links())
    errors.extend(check_tracked_local_artifacts())

    if errors:
        print("Agent harness check failed:\n")
        for error in errors:
            print(f"- {error}")
        return 1

    print("Agent harness check passed.")
    return 0


def check_required_paths() -> list[str]:
    errors: list[str] = []

    for relative_path in REQUIRED_FILES:
        path = ROOT / relative_path
        if not path.is_file():
            errors.append(f"Missing required file: {relative_path}")

    for relative_path in REQUIRED_DIRS:
        path = ROOT / relative_path
        if not path.is_dir():
            errors.append(f"Missing required directory: {relative_path}")

    return errors


def check_agents_size() -> list[str]:
    path = ROOT / "AGENTS.md"
    if not path.exists():
        return []

    line_count = len(path.read_text(encoding="utf-8").splitlines())
    if line_count > 120:
        return [f"AGENTS.md should stay map-sized. Current line count: {line_count}; limit: 120"]

    return []


def check_exec_plan_template() -> list[str]:
    path = ROOT / "docs/exec-plans/template.md"
    if not path.exists():
        return []

    text = path.read_text(encoding="utf-8")
    return [
        f"Execution plan template is missing required section: {section}"
        for section in EXEC_PLAN_TEMPLATE_SECTIONS
        if section not in text
    ]


def check_markdown_links() -> list[str]:
    errors: list[str] = []

    for path in markdown_files():
        text = path.read_text(encoding="utf-8")
        for match in LINK_PATTERN.finditer(text):
            raw_target = match.group(1).strip()
            if not should_check_link(raw_target):
                continue

            target = normalize_link_target(raw_target)
            if not target:
                continue

            resolved = (path.parent / target).resolve()
            try:
                resolved.relative_to(ROOT)
            except ValueError:
                errors.append(f"{path.relative_to(ROOT)} links outside the repository: {raw_target}")
                continue

            if not resolved.exists():
                line_number = text[: match.start()].count("\n") + 1
                errors.append(
                    f"{path.relative_to(ROOT)}:{line_number} has a broken local link: {raw_target}"
                )

    return errors


def markdown_files() -> list[Path]:
    ignored_parts = {".git", ".build", "DerivedData", "build", "node_modules"}
    return sorted(
        path
        for path in ROOT.rglob("*.md")
        if not any(part in ignored_parts for part in path.relative_to(ROOT).parts)
    )


def should_check_link(target: str) -> bool:
    lowered = target.lower()
    if not target or target.startswith("#"):
        return False
    if lowered.startswith(("http://", "https://", "mailto:", "tel:")):
        return False
    return True


def normalize_link_target(target: str) -> str:
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1]

    target = target.split("#", 1)[0]
    target = target.split("?", 1)[0]
    target = unquote(target)
    return target


def check_tracked_local_artifacts() -> list[str]:
    try:
        result = subprocess.run(
            ["git", "ls-files"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError) as error:
        return [f"Could not inspect tracked files with git ls-files: {error}"]

    errors: list[str] = []
    for tracked_file in result.stdout.splitlines():
        for pattern in FORBIDDEN_TRACKED_PATTERNS:
            if pattern in tracked_file:
                errors.append(f"Local artifact is tracked: {tracked_file}")

    return errors


if __name__ == "__main__":
    sys.exit(main())
