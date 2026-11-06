#!/usr/bin/env python3
"""Compile the actual bar parsers; no network, external scripts or live caches."""
import os
from pathlib import Path
import subprocess

REPO = Path(__file__).resolve().parent.parent
BUILD = REPO / "build" / "test-ai-usage"


def declaration(source, signature):
    start = source.index(signature)
    # Top-level declarations in bar.swift end with an unindented closing brace.
    end = source.index("\n}", start) + 2
    return source[start:end] + "\n"


def parser_source(source):
    names = ["struct AIRow {", "struct AIUsage {", "struct AIWindow {",
             "func aiCacheURL(", "func aiWindows(", "func aiCachedUsage(",
             "func aiPrimary(", "func aiRemaining(", "func aiWindowRows(",
             "func aiClaudeRows(", "func aiCodexRows(", "func aiPillLabel(",
             "func aiParsedUsage("]
    return "import Foundation\nimport CoreFoundation\n" + "".join(
        declaration(source, name) for name in names)


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    source = parser_source((REPO / "helper/bar.swift").read_text())
    source += (REPO / "test/ai-usage.swift").read_text()
    main_file = BUILD / "main.swift"
    main_file.write_text(source)
    binary = BUILD / "ai-usage"
    subprocess.run(["swiftc", "-O", str(main_file), "-o", str(binary)], check=True)
    subprocess.run([str(binary), str(REPO / "test/fixtures/ai-usage"), str(BUILD)], check=True,
                   env={**os.environ, "TZ": "UTC"})


if __name__ == "__main__":
    main()
