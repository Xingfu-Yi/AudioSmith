#!/usr/bin/env python3
"""Verify Hugging Face and ModelScope against the app's Swift manifests.

The default check streams every model file from both mirrors and validates its
size and SHA-256 without retaining model weights. Use --probe-only for a fast
config.json check during ordinary development.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent.parent
MANIFEST_PATH = ROOT / "AudioSmith/Model/ModelManifest.swift"
CHUNK_BYTES = 4 * 1024 * 1024


@dataclass(frozen=True)
class FileEntry:
    path: str
    size: int
    sha256: str


@dataclass(frozen=True)
class ModelEntry:
    symbol: str
    identifier: str
    repository: str
    revision: str
    model_scope_revision: str
    files: tuple[FileEntry, ...]


def swift_value(block: str, key: str) -> str:
    match = re.search(rf'{re.escape(key)}:\s*"([^"]+)"', block)
    if not match:
        raise ValueError(f"missing {key} in ModelManifest.{block[:40]!r}")
    return match.group(1)


def manifest_blocks(text: str) -> list[tuple[str, str]]:
    blocks: list[tuple[str, str]] = []
    marker = re.compile(r"static let (\w+) = ModelManifest\(")
    for match in marker.finditer(text):
        start = match.start()
        cursor = match.end() - 1
        depth = 0
        while cursor < len(text):
            character = text[cursor]
            if character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
                if depth == 0:
                    blocks.append((match.group(1), text[start : cursor + 1]))
                    break
            cursor += 1
        else:
            raise ValueError(f"unterminated ModelManifest.{match.group(1)}")
    return blocks


def load_manifest() -> tuple[ModelEntry, ...]:
    text = MANIFEST_PATH.read_text(encoding="utf-8")
    models: list[ModelEntry] = []
    file_pattern = re.compile(
        r'\.init\(path:\s*"([^"]+)",\s*size:\s*([0-9_]+),\s*'
        r'sha256:\s*"([0-9a-f]{64})"\)'
    )
    for symbol, block in manifest_blocks(text):
        files = tuple(
            FileEntry(path, int(size.replace("_", "")), digest)
            for path, size, digest in file_pattern.findall(block)
        )
        if not files:
            raise ValueError(f"ModelManifest.{symbol} contains no parseable files")
        models.append(
            ModelEntry(
                symbol=symbol,
                identifier=swift_value(block, "identifier"),
                repository=swift_value(block, "repository"),
                revision=swift_value(block, "revision"),
                model_scope_revision=swift_value(block, "modelScopeRevision"),
                files=files,
            )
        )
    if not models:
        raise ValueError("no model manifests found")
    return tuple(models)


def remote_url(source: str, model: ModelEntry, path: str) -> str:
    encoded_path = "/".join(quote(part, safe="") for part in path.split("/"))
    if source == "huggingface":
        repository = "/".join(quote(part, safe="") for part in model.repository.split("/"))
        return (
            f"https://huggingface.co/{repository}/resolve/"
            f"{quote(model.revision, safe='')}/{encoded_path}"
        )
    query = urlencode(
        {"Revision": model.model_scope_revision, "FilePath": path}
    )
    repository = "/".join(quote(part, safe="") for part in model.repository.split("/"))
    return f"https://modelscope.cn/api/v1/models/{repository}/repo?{query}"


def stream_digest(url: str, timeout: float) -> tuple[int, str]:
    request = Request(url, headers={"User-Agent": "AudioSmith-mirror-verifier/1"})
    size = 0
    hasher = hashlib.sha256()
    with urlopen(request, timeout=timeout) as response:
        status = getattr(response, "status", 200)
        if not 200 <= status < 300:
            raise RuntimeError(f"HTTP {status}")
        while chunk := response.read(CHUNK_BYTES):
            size += len(chunk)
            hasher.update(chunk)
    return size, hasher.hexdigest()


def verify_file(
    model: ModelEntry, file: FileEntry, source: str, timeout: float
) -> tuple[int, str]:
    url = remote_url(source, model, file.path)
    size, digest = stream_digest(url, timeout)
    if size != file.size:
        raise RuntimeError(f"size {size:,}; expected {file.size:,}")
    if digest != file.sha256:
        raise RuntimeError(f"SHA-256 {digest}; expected {file.sha256}")
    return size, digest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--probe-only",
        action="store_true",
        help="verify only each model's config.json from both mirrors",
    )
    parser.add_argument(
        "--model",
        action="append",
        default=[],
        help="manifest symbol or identifier to verify; repeatable (default: all)",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=120.0,
        help="per-request socket timeout in seconds (default: 120)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        models = load_manifest()
    except (OSError, ValueError) as error:
        print(f"manifest error: {error}", file=sys.stderr)
        return 2

    requested = set(args.model)
    if requested:
        models = tuple(
            model
            for model in models
            if model.symbol in requested or model.identifier in requested
        )
        if not models:
            print("no requested model matched the Swift manifest", file=sys.stderr)
            return 2

    failures = 0
    for model in models:
        files = model.files
        if args.probe_only:
            files = tuple(file for file in files if file.path == "config.json")
        print(f"{model.identifier}: {len(files)} file(s)")
        for file in files:
            mirror_results: dict[str, tuple[int, str]] = {}
            for source in ("modelscope", "huggingface"):
                try:
                    result = verify_file(model, file, source, args.timeout)
                    mirror_results[source] = result
                    print(f"  OK {source:11} {file.path} ({result[0]:,} bytes)")
                except Exception as error:  # report all mirrors/files in one run
                    failures += 1
                    print(
                        f"  FAIL {source:11} {file.path}: {error}",
                        file=sys.stderr,
                    )
            if len(mirror_results) == 2 and len(set(mirror_results.values())) != 1:
                failures += 1
                print(f"  FAIL mirrors differ for {file.path}", file=sys.stderr)

    if failures:
        print(f"mirror verification failed: {failures} error(s)", file=sys.stderr)
        return 1
    print("mirror verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
