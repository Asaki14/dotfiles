#!/usr/bin/env python3
"""Compile the bar's proxy health and group parsing; no Clash, network or config."""
from pathlib import Path
import subprocess

REPO = Path(__file__).resolve().parent.parent
BUILD = REPO / "build" / "test-proxy-health"


def declaration(source, signature):
    start = source.index(signature)
    # Top-level declarations in bar.swift end with an unindented closing brace.
    end = source.index("\n}", start) + 2
    return source[start:end] + "\n"


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    source = (REPO / "helper/bar.swift").read_text()
    names = ["enum AIProxyHealth", "func aiProbeHealth(", "enum AIProbeOutcome",
             "struct AIFailureConfirmation", "struct ProxyNodeStatus", "struct ProxyGroupStatus",
             "func proxyAIGroupName(", "func parseProxyGroups("]
    # bar.swift reads proxy-ai-group / proxy-auto-group from bar-items.conf; tests use the defaults.
    text = ("import Foundation\nfunc configuredValues(_ directive: String) -> [String]? { nil }\n"
            + "".join(declaration(source, name) for name in names))
    text += (REPO / "test/proxy-health.swift").read_text()
    main_file = BUILD / "main.swift"
    main_file.write_text(text)
    binary = BUILD / "proxy-health"
    subprocess.run(["swiftc", "-O", str(main_file), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    main()
