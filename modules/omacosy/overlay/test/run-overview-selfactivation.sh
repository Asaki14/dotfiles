#!/usr/bin/env bash
# Builds the overview from THIS worktree and runs the self-activation
# regression test against it. Nothing installed is touched: the daemon
# under test runs with OMACOSY_OVERVIEW_TEST_ID, so it keeps its own
# pidfile, ffm flag and log, and never kills its siblings.
#
# Needs Accessibility permission for the calling terminal (the test posts
# CGEvents) and an idle keyboard — see test/README.md.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${OUT:-$(mktemp -d)}
# same swiftc line install.sh uses for the overview
swiftc -O -F /System/Library/PrivateFrameworks -framework SkyLight \
  -o "$OUT/omacosy-overview" helper/overview.swift
swiftc -O -o "$OUT/overview-selfactivation" test/overview-selfactivation.swift
OVERVIEW_BIN="$OUT/omacosy-overview" exec "$OUT/overview-selfactivation"
