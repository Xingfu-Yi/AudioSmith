#!/usr/bin/env python3
"""Validate every repository-owned Audio Smith SKILL.md without dependencies."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOTS = (Path("DictateAgent/Resources/Skills"), Path("Examples/Skills"))
NAME_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
CONTEXT_HEADINGS = {"dictation context", "context", "听写上下文", "上下文"}
VOCABULARY_HEADINGS = {
    "vocabulary",
    "preferred vocabulary",
    "preferred terms",
    "词汇",
    "术语",
}


def section(lines: list[str], headings: set[str]) -> list[str]:
    captured: list[str] = []
    active = False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("## "):
            if active:
                break
            active = stripped[3:].strip().lower() in headings
            continue
        if active:
            if stripped.startswith("# "):
                break
            captured.append(line)
    return captured


def metadata_value(lines: list[str], key: str) -> str | None:
    prefix = f"{key}:"
    for line in lines:
        if line.lower().startswith(prefix):
            value = line.split(":", 1)[1].strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            return value
    return None


def validate(path: Path) -> list[str]:
    errors: list[str] = []
    if path.stat().st_size > 256 * 1024:
        errors.append("file exceeds 256KB")
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return ["file is not valid UTF-8"]

    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return ["missing opening YAML frontmatter delimiter"]
    try:
        closing = next(index for index, line in enumerate(lines[1:], 1) if line.strip() == "---")
    except StopIteration:
        return ["missing closing YAML frontmatter delimiter"]

    frontmatter = lines[1:closing]
    name = metadata_value(frontmatter, "name")
    description = metadata_value(frontmatter, "description")
    if not name:
        errors.append("frontmatter name is required")
    elif not NAME_PATTERN.fullmatch(name) or len(name) > 64:
        errors.append("name must be 1-64 lowercase letters, digits or hyphen-separated words")
    elif name != path.parent.name:
        errors.append(f"name {name!r} does not match directory {path.parent.name!r}")
    if not description:
        errors.append("frontmatter description is required")

    body = lines[closing + 1 :]
    context = "\n".join(section(body, CONTEXT_HEADINGS)).strip()
    vocabulary = section(body, VOCABULARY_HEADINGS)
    terms = [line for line in vocabulary if line.strip().startswith("- ") and "`" in line]
    if not context and not terms:
        errors.append("Dictation context or Vocabulary content is required")
    if len(terms) > 200:
        errors.append("Vocabulary exceeds 200 entries")
    return errors


def main() -> int:
    paths = sorted(path for root in ROOTS if root.exists() for path in root.glob("*/SKILL.md"))
    if not paths:
        print("No repository Skills found.", file=sys.stderr)
        return 1

    failed = False
    for path in paths:
        errors = validate(path)
        if errors:
            failed = True
            for error in errors:
                print(f"{path}: {error}", file=sys.stderr)
        else:
            print(f"valid: {path}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
