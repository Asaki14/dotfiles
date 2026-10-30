#!/bin/bash
# codexbar_omp.sh - codexbar wrapper for omacosy-bar (bar-items.conf `codexbar` directive).
# Claude usage comes from OAuth, never browser cookies: `auto` stops at the
# missing claude.ai cookie instead of trying OAuth, so `--provider claude`
# always forces `--source oauth` and hands codexbar an access token via
# CODEXBAR_CLAUDE_OAUTH_TOKEN. codexbar's CLI will not read the keychain
# itself without a prompt, so the token is read here:
# 1. omp's Anthropic OAuth login (~/.omp/agent/agent.db), if one is active;
# 2. Claude Code's own login (`claude auth login`) in the
#    "Claude Code-credentials" keychain item. Claude Code refreshes it only when
#    it runs, so a token about to expire is renewed by touching the CLI first.
# Only access tokens are passed; refresh tokens stay with their owners, so
# codexbar cannot rotate them and log omp or Claude Code out.
# Every other provider falls through to plain codexbar.

CODEXBAR=/opt/homebrew/bin/codexbar
CLAUDE=/opt/homebrew/bin/claude
OMP_DB="$HOME/.omp/agent/agent.db"

is_claude=0
prev=
for arg in "$@"; do
  [ "$prev" = "--provider" ] && [ "$arg" = "claude" ] && is_claude=1
  prev=$arg
done

# Prints Claude Code's access token, or nothing when it is missing or expires
# within $1 seconds.
claude_code_token() {
  /usr/bin/security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null |
    /usr/bin/python3 -c '
import json, sys, time
try:
    oauth = json.load(sys.stdin)["claudeAiOauth"]
    expires = oauth["expiresAt"]
    expires = expires / 1000 if expires > 1e11 else expires
    if expires - time.time() > int(sys.argv[1]):
        print(oauth["accessToken"])
except Exception:
    pass
' "$1"
}

if [ "$is_claude" = 1 ]; then
  token=
  if [ -r "$OMP_DB" ]; then
    token=$(/usr/bin/sqlite3 -readonly "$OMP_DB" \
      "SELECT json_extract(data, '$.access') FROM auth_credentials
       WHERE provider = 'anthropic' AND credential_type = 'oauth' AND disabled_cause IS NULL
       ORDER BY updated_at DESC LIMIT 1" 2>/dev/null)
  fi
  if [ -z "$token" ]; then
    token=$(claude_code_token 600)
    if [ -z "$token" ] && [ -x "$CLAUDE" ]; then
      "$CLAUDE" auth status >/dev/null 2>&1
      token=$(claude_code_token 0)
    fi
  fi
  if [ -n "$token" ]; then
    CODEXBAR_CLAUDE_OAUTH_TOKEN="$token" exec "$CODEXBAR" "$@" --source oauth
  fi
  # No usable login: let codexbar report its own OAuth error.
  exec "$CODEXBAR" "$@" --source oauth
fi

exec "$CODEXBAR" "$@"
