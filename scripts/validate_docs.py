#!/usr/bin/env python3
"""Validate repository documentation and demo assets without dependencies."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parent.parent
READMES = (ROOT / "README.md", ROOT / "README.zh-CN.md")
MAX_GIF_BYTES = 5 * 1024 * 1024

REQUIRED_HEADINGS = {
    "README.md": {
        "Developer Preview",
        "Requirements",
        "Quick Start from Source",
        "How It Works",
        "Skills",
        "Privacy",
        "Measured Performance",
        "Development",
        "Roadmap",
        "Contributing",
        "License",
    },
    "README.zh-CN.md": {
        "开发者预览版",
        "运行要求",
        "从源码快速开始",
        "工作原理",
        "Skills",
        "隐私",
        "实测性能",
        "开发",
        "路线图",
        "参与贡献",
        "许可证",
    },
}

MARKDOWN_LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
FENCE = re.compile(r"^\s*(```|~~~)")


def markdown_files() -> list[Path]:
    roots = [
        *ROOT.glob("*.md"),
        *(ROOT / "docs").glob("*.md"),
        *(ROOT / ".github").rglob("*.md"),
    ]
    return sorted(set(path.resolve() for path in roots if path.is_file()))


def visible_markdown(text: str) -> str:
    kept: list[str] = []
    fence_marker: str | None = None
    for line in text.splitlines():
        match = FENCE.match(line)
        if match:
            marker = match.group(1)
            if fence_marker is None:
                fence_marker = marker
            elif marker == fence_marker:
                fence_marker = None
            continue
        if fence_marker is None:
            kept.append(line)
    return "\n".join(kept)


def local_target(raw: str) -> str | None:
    value = raw.strip()
    if value.startswith("<") and ">" in value:
        value = value[1 : value.index(">")]
    else:
        value = value.split(maxsplit=1)[0]
    value = unquote(value)
    if not value or value.startswith("#"):
        return None
    if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", value):
        return None
    return value.split("#", 1)[0]


def validate_links(path: Path) -> list[str]:
    errors: list[str] = []
    text = visible_markdown(path.read_text(encoding="utf-8"))
    for match in MARKDOWN_LINK.finditer(text):
        target = local_target(match.group(1))
        if target is None:
            continue
        resolved = (path.parent / target).resolve()
        try:
            resolved.relative_to(ROOT)
        except ValueError:
            errors.append(f"link escapes repository: {target}")
            continue
        if not resolved.exists():
            errors.append(f"missing local link target: {target}")
    return errors


def validate_readme(path: Path) -> list[str]:
    errors: list[str] = []
    text = path.read_text(encoding="utf-8")
    headings = {
        line[3:].strip()
        for line in text.splitlines()
        if line.startswith("## ")
    }
    missing = REQUIRED_HEADINGS[path.name] - headings
    for heading in sorted(missing):
        errors.append(f"missing required section: {heading}")

    if path.name == "README.md" and "[简体中文](README.zh-CN.md)" not in text:
        errors.append("missing Simplified Chinese language switch")
    if path.name == "README.zh-CN.md" and "[English](README.md)" not in text:
        errors.append("missing English language switch")
    return errors


def validate_assets() -> list[tuple[Path, str]]:
    errors: list[tuple[Path, str]] = []
    assets = ROOT / "docs/assets"
    demo_gif = assets / "demo.gif"
    demo_poster = assets / "demo-poster.png"
    referenced = "\n".join(path.read_text(encoding="utf-8") for path in READMES)

    for path in (demo_gif, demo_poster):
        if path.as_posix().removeprefix(ROOT.as_posix() + "/") in referenced:
            if not path.is_file():
                errors.append((path, "referenced demo asset is missing"))
            elif path.stat().st_size == 0:
                errors.append((path, "demo asset is empty"))

    if demo_gif.is_file():
        data = demo_gif.read_bytes()
        if not data.startswith((b"GIF87a", b"GIF89a")):
            errors.append((demo_gif, "asset is not a GIF"))
        if len(data) > MAX_GIF_BYTES:
            errors.append(
                (demo_gif, f"GIF is {len(data)} bytes; limit is {MAX_GIF_BYTES}")
            )

    if demo_poster.is_file() and not demo_poster.read_bytes().startswith(
        b"\x89PNG\r\n\x1a\n"
    ):
        errors.append((demo_poster, "asset is not a PNG"))
    return errors


def main() -> int:
    failures: list[tuple[Path, str]] = []
    for path in READMES:
        if not path.is_file():
            failures.append((path, "required README is missing"))
            continue
        for error in validate_readme(path):
            failures.append((path, error))

    for path in markdown_files():
        try:
            path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            failures.append((path, "document is not valid UTF-8"))
            continue
        for error in validate_links(path):
            failures.append((path, error))

    failures.extend(validate_assets())
    if failures:
        for path, error in failures:
            print(f"{path.relative_to(ROOT)}: {error}", file=sys.stderr)
        return 1

    print(f"valid: {len(markdown_files())} Markdown documents")
    print("valid: demo assets are absent or valid when referenced")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
