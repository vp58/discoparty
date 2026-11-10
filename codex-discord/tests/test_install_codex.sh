#!/usr/bin/env bash

# Noninteractive scratch smoke test for the macOS Codex-only installer.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REAL_PYTHON="$(command -v python3)"
TEST_ROOT="$(mktemp -d "$HOME/.discoparty-codex-install-test.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  if [ "$status" -ne 0 ]; then
    echo "install-codex smoke test failed; captured logs follow:" >&2
    local log
    for log in "$TEST_ROOT"/*.log; do
      [ -f "$log" ] || continue
      echo "===== ${log##*/} =====" >&2
      cat "$log" >&2
    done
  fi
  chmod -R u+rwX "$TEST_ROOT" 2>/dev/null || true
  rm -rf "$TEST_ROOT"
  exit "$status"
}
trap cleanup EXIT

TEST_HOME="$TEST_ROOT/home"
APP_SUPPORT_ROOT="$TEST_HOME/Library/Application Support/Discoparty"
TEST_REPO="$APP_SUPPORT_ROOT/repo"
CANONICAL_TEST_HOME="$("$REAL_PYTHON" -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "$TEST_HOME")"
FAKE_BIN="$TEST_ROOT/fake-bin"
WORK_DIR="$TEST_ROOT/workspace"
LAUNCHCTL_LOG="$TEST_ROOT/launchctl.log"
SECRET_PROBE_LOG="$TEST_ROOT/secret-probe.log"
mkdir -p \
  "$TEST_REPO/launchd/templates" \
  "$TEST_REPO/launchd" \
  "$TEST_REPO/codex_discord_bridge" \
  "$TEST_REPO/conversations" \
  "$TEST_REPO/cx-chat-listener" \
  "$TEST_HOME/Library/LaunchAgents" \
  "$FAKE_BIN" \
  "$WORK_DIR" \
  "$TEST_ROOT/claude-workspace/.claude/hooks" \
  "$TEST_ROOT/claude-workspace/x_System/Scripts" \
  "$TEST_ROOT/claude-workspace/x_System/Skills/eli5" \
  "$TEST_ROOT/claude-workspace/x_System/Skills/marketing/websites/vinaytalks" \
  "$TEST_ROOT/claude-workspace/x_System/Skills/triage" \
  "$TEST_ROOT/claude-workspace/x_System/Skills/skill-finder"

cat > "$TEST_ROOT/claude-workspace/x_System/Skills/eli5/SKILL.md" <<'EOF'
---
name: eli5
description: Test ELI5 skill.
---
# ELI5
EOF
cat > "$TEST_ROOT/claude-workspace/x_System/Skills/marketing/websites/vinaytalks/SKILL.md" <<'EOF'
---
name: marketing/websites/vinaytalks
description: Test vinaytalks skill.
---
# vinaytalks
EOF
cat > "$TEST_ROOT/claude-workspace/x_System/Skills/triage/SKILL.md" <<'EOF'
---
name: triage
description: Test triage skill.
---
# triage
EOF
cat > "$TEST_ROOT/claude-workspace/x_System/Skills/skill-finder/SKILL.md" <<'EOF'
---
name: skill-finder
description: Test canonical skill routing.
---
# skill-finder
EOF
for hook in \
  .claude/hooks/security_validator.py \
  .claude/hooks/em-dash-write-validator.py \
  x_System/Scripts/outbound_send_gate_hook.py \
  x_System/Scripts/hook_command_detect.py; do
  cat > "$TEST_ROOT/claude-workspace/$hook" <<'PY'
#!/usr/bin/env python3
raise SystemExit(0)
PY
  chmod 700 "$TEST_ROOT/claude-workspace/$hook"
done
cat > "$TEST_ROOT/claude-workspace/CLAUDE.md" <<'EOF'
# Vault Guide

## Most Critical Constraint (P0)
Test most critical rule.

## Hard Preview Boundary (P0)
Test preview boundary.

## Dash Repository Boundary (P0)
Test repository boundary.

## Discord Plugin Security (P0)
Test Discord boundary.

## Tool Routing (P0)
Test tool routing.

## P0 Hard Rules (one-line each, link to detail)
Test hard rules.
EOF

cp "$REPO_ROOT/install-codex.sh" "$TEST_REPO/install-codex.sh"
cp "$REPO_ROOT/install.sh" "$TEST_REPO/install.sh"
grep -Fq 'CLAUDE_BIN="$HOME/.local/share/claude/versions/2.1.251"' "$TEST_REPO/install.sh"
grep -Fq 'BUN_BIN="/opt/homebrew/bin/bun"' "$TEST_REPO/install.sh"
"$REAL_PYTHON" - "$TEST_REPO/install.sh" "$FAKE_BIN/claude" "$FAKE_BIN/bun" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
old = 'CLAUDE_BIN="$HOME/.local/share/claude/versions/2.1.251"'
if text.count(old) != 1:
    raise SystemExit("could not locate the exact production Claude CLI pin")
text = text.replace(old, f'CLAUDE_BIN="{sys.argv[2]}"', 1)
old_bun = 'BUN_BIN="/opt/homebrew/bin/bun"'
if text.count(old_bun) != 1:
    raise SystemExit("could not locate the exact production Bun pin")
path.write_text(text.replace(old_bun, f'BUN_BIN="{sys.argv[3]}"', 1))
PY
cp "$REPO_ROOT/uninstall.sh" "$TEST_REPO/uninstall.sh"
cp "$REPO_ROOT/config.example.toml" "$TEST_REPO/config.example.toml"
cp "$REPO_ROOT/conversations/config.py" "$TEST_REPO/conversations/config.py"
cp "$REPO_ROOT/conversations/claude_cli.py" "$TEST_REPO/conversations/claude_cli.py"
cp "$REPO_ROOT/conversations/discord_access.py" "$TEST_REPO/conversations/discord_access.py"
cp "$REPO_ROOT/conversations/discord_identity.py" "$TEST_REPO/conversations/discord_identity.py"
cp "$REPO_ROOT/conversations/discord_permissions.py" "$TEST_REPO/conversations/discord_permissions.py"
cp "$REPO_ROOT/conversations/discord_secret.py" "$TEST_REPO/conversations/discord_secret.py"
cp "$REPO_ROOT/conversations/listener_contract.py" "$TEST_REPO/conversations/listener_contract.py"
cp "$REPO_ROOT/conversations/vault_policy.py" "$TEST_REPO/conversations/vault_policy.py"
cp "$REPO_ROOT/cx-chat-listener/CLAUDE.md" "$TEST_REPO/cx-chat-listener/CLAUDE.md"
cp "$REPO_ROOT/codex_discord_bridge/codex_auth.py" "$TEST_REPO/codex_discord_bridge/codex_auth.py"
cp "$REPO_ROOT/codex_discord_bridge/codex_policy.py" "$TEST_REPO/codex_discord_bridge/codex_policy.py"
cp "$REPO_ROOT/codex_discord_bridge/shared_skills.py" "$TEST_REPO/codex_discord_bridge/shared_skills.py"
cp "$REPO_ROOT/codex_discord_bridge/shared_hooks.py" "$TEST_REPO/codex_discord_bridge/shared_hooks.py"
cp "$REPO_ROOT/codex_discord_bridge/store.py" "$TEST_REPO/codex_discord_bridge/store.py"
cp "$REPO_ROOT/launchd/codex-monitor.sh" "$TEST_REPO/launchd/codex-monitor.sh"
cp \
  "$REPO_ROOT/launchd/templates/com.discoparty.codex-discord-bridge.plist.template" \
  "$TEST_REPO/launchd/templates/com.discoparty.codex-discord-bridge.plist.template"
for template in \
  com.discoparty.cx-chat-healthcheck.plist.template \
  com.discoparty.discord-gateway-client.plist.template \
  com.discoparty.discord-marker-watcher.plist.template; do
  cp "$REPO_ROOT/launchd/templates/$template" "$TEST_REPO/launchd/templates/$template"
done
touch "$TEST_REPO/codex_discord_bridge/main.py"
touch "$TEST_REPO/codex_discord_bridge/__init__.py"
touch "$TEST_ROOT/trusted-instructions.md"
cat > "$TEST_REPO/conversations/discord_http.py" <<'PY'
"""Deterministic Discord HTTP fixture for the installer smoke test."""


def json_request(method, path, token, **kwargs):
    assert method == "GET"
    assert token == "claude-token"
    if path == "/users/@me":
        return {"id": "200000000000000021", "bot": True}
    if path == "/oauth2/applications/@me":
        return {
            "id": "200000000000000022",
            "bot": {"id": "200000000000000021"},
        }
    if path.startswith("/channels/"):
        return {
            "id": path.rsplit("/", 1)[-1],
            "type": 0,
            "guild_id": "200000000000000023",
        }
    raise AssertionError(path)
PY
cat > "$TEST_REPO/conversations/claude_plugin.py" <<'PY'
"""Reviewed-plugin fixture for the shared-config preservation smoke test."""
import json

print(json.dumps({"ok": True, "version": "0.0.4"}))
PY
chmod 755 \
  "$TEST_REPO/install-codex.sh" \
  "$TEST_REPO/install.sh" \
  "$TEST_REPO/uninstall.sh" \
  "$TEST_REPO/launchd/codex-monitor.sh"

if grep -Fq -- '-m venv --clear' "$TEST_REPO/install-codex.sh"; then
  echo "installer still clears a runtime venv in place" >&2
  exit 1
fi
grep -Fq 'runtime-venv-cpython-${RUNTIME_PYTHON_MM}-websockets-${RUNTIME_WEBSOCKETS_VERSION}-${RUNTIME_LOCK_SHA256}' \
  "$TEST_REPO/install-codex.sh"
grep -Fq 'renamex_np' "$TEST_REPO/install-codex.sh"

cat > "$TEST_REPO/config.toml" <<EOF
# CLAUDE_SENTINEL: this text and every Claude table must survive Codex install.
[paths]
workspace_root = "$TEST_ROOT/claude-workspace"
conversations_dir = "$TEST_ROOT/claude-workspace/conversations"

[discord]
chat_channel_id = "200000000000000001"
errors_channel_id = "200000000000000002"
owner_user_id = "200000000000000003"
token_env_var = "DISCORD_BOT_TOKEN"

[runtime]
timezone = "America/New_York"
max_messages_per_minute = 7
max_messages_per_hour = 31
max_concurrent_workers = 2
use_dangerously_skip_permissions = false

[claude_custom]
keep_me = "untouched"

[codex]
enabled = false
state_dir = "~/Library/Application Support/Discoparty/codex-discord"
codex_home = "~/Library/Application Support/Discoparty/codex-discord/home/.codex"
instructions_file = "$TEST_ROOT/trusted-instructions.md"
max_messages_per_minute = 6
max_messages_per_hour = 24
max_concurrent_workers = 4
max_pending_jobs = 40
max_input_chars = 9000
retention_days = 14
max_database_bytes = 134217728
EOF

cat > "$FAKE_BIN/assert-no-secret" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
for secret in 'codex-test-token-without-spaces-123' 'claude-token'; do
  for argument in "$@"; do
    if [[ "$argument" == *"$secret"* ]]; then
      echo "Discord token leaked through child argv" >&2
      exit 96
    fi
  done
  while IFS= read -r entry; do
    if [[ "$entry" == *"$secret"* ]]; then
      echo "Discord token leaked through a child environment" >&2
      exit 97
    fi
  done < <(/usr/bin/env)
done
printf 'ok %s\n' "${1##*/}" >> "$DISCOPARTY_TEST_SECRET_PROBE_LOG"
EOF

cat > "$FAKE_BIN/uname" <<'EOF'
#!/usr/bin/env bash
"${DISCOPARTY_TEST_SECRET_PROBE:?}" "$0" "$@"
case "${1:-}" in
  -s) echo Darwin ;;
  -m) echo arm64 ;;
  *) exit 2 ;;
esac
EOF

cat > "$FAKE_BIN/sysctl" <<'EOF'
#!/usr/bin/env bash
"${DISCOPARTY_TEST_SECRET_PROBE:?}" "$0" "$@"
if [ "${1:-}" = "-n" ] && [ "${2:-}" = "machdep.cpu.brand_string" ]; then
  echo "Apple M5 Max"
  exit 0
fi
exit 2
EOF

cat > "$FAKE_BIN/codex" <<'EOF'
#!/usr/bin/env bash
"${DISCOPARTY_TEST_SECRET_PROBE:?}" "$0" "$@"
case "${1:-}" in
  --version) echo "codex-cli 0.153.4" ;;
  login)
    [ "${2:-}" = "status" ] || exit 2
    [ -n "${CODEX_HOME:-}" ] || exit 3
    [ "$HOME" = "${DISCOPARTY_TEST_EXPECT_REAL_HOME:?}" ] || exit 4
    if [ "${DISCOPARTY_TEST_AUTH_SCENARIO:-}" = "filesystem-artifact" ]; then
      printf '%s\n' '{}' > "$CODEX_HOME/auth.json"
      chmod 600 "$CODEX_HOME/auth.json"
    fi
    echo "Logged in using ChatGPT"
    ;;
  *) exit 2 ;;
esac
EOF

cat > "$FAKE_BIN/python3" <<'EOF'
#!/usr/bin/env bash
"${DISCOPARTY_TEST_SECRET_PROBE:?}" "$0" "$@"
if [ "${1:-}" = "-c" ] && [ "${2:-}" = "import websockets" ]; then
  exit 0
fi
if [ "${1##*/}" = "claude_cli.py" ]; then
  [ "${2:-}" = "verify" ] || exit 84
  [ "${3:-}" = "--path" ] || exit 84
  [ "${4:-}" = "$DISCOPARTY_TEST_CLAUDE_BIN" ] || exit 84
  printf '%s\n' '{"checks":{"claude_cli":"pass"}}'
  exit 0
fi
if [ "${1##*/}" = "bun_runtime.py" ]; then
  [ "${2:-}" = "verify" ] || exit 85
  [ "${3:-}" = "--path" ] || exit 85
  [ "${4:-}" = "$DISCOPARTY_TEST_BUN_BIN" ] || exit 85
  printf '%s\n' '{"checks":{"bun_runtime":"pass"}}'
  exit 0
fi
if [ "${1##*/}" = "discord_access.py" ]; then
  # Production binds the state path to pwd(3), not ambient HOME. Model this
  # scratch HOME as the account database entry without changing the copied
  # production module or weakening its canonical-home boundary.
  exec "$DISCOPARTY_TEST_REAL_PYTHON" - "$@" <<'PY'
import os
import pwd
import runpy
import sys
from types import SimpleNamespace

script = sys.argv[1]
arguments = sys.argv[2:]
account = pwd.getpwuid(os.getuid())
fixture_account = SimpleNamespace(
    pw_dir=os.environ["HOME"],
    pw_name=account.pw_name,
)
pwd.getpwuid = lambda uid: fixture_account
sys.argv = [script, *arguments]
runpy.run_path(script, run_name="__main__")
PY
fi
if [ "${1##*/}" = "shared_skills.py" ]; then
  [ "${2:-}" = "verify" ] || exit 87
  [ "${3:-}" = "--root" ] || exit 87
  [ -n "${4:-}" ] || exit 87
  printf '%s\n' '{"checks":{"shared_skills":"pass"}}'
  exit 0
fi
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "codex_discord_bridge.preflight" ]; then
  [ "${OPENAI_API_KEY+x}" != "x" ] || exit 91
  [ -n "${DISCOPARTY_CONFIG:-}" ] || exit 92
  [ "${DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED+x}" != "x" ] || exit 94
  "$DISCOPARTY_TEST_REAL_PYTHON" - <<'PY'
import os

from conversations.config import CONFIG

expected = os.environ["DISCOPARTY_CODEX_SANDBOX_MODE"] == "danger-full-access"
assert CONFIG.codex.full_computer_access_accepted is expected
PY
  if [ "${DISCOPARTY_TEST_PREFLIGHT_LOG_SYMLINK:-0}" = "1" ]; then
    : > "$DISCOPARTY_TEST_LOG_SWAP_TARGET"
    /bin/rm -f "$DISCOPARTY_REPO_ROOT/logs/codex-discord-bridge.stdout.log"
    /bin/ln -s "$DISCOPARTY_TEST_LOG_SWAP_TARGET" \
      "$DISCOPARTY_REPO_ROOT/logs/codex-discord-bridge.stdout.log"
  fi
  printf '%s\n' '{"checks":{"smoke_preflight":"pass"},"warnings":{}}'
  exit 0
fi
if [ "${1:-}" = "-m" ] && \
   [ "${2:-}" = "codex_discord_bridge.codex_auth" ] && \
   [ "${3:-}" = "logout-configured" ]; then
  [ "$HOME" = "${DISCOPARTY_TEST_EXPECT_REAL_HOME:?}" ] || exit 95
  [ -n "${DISCOPARTY_CONFIG:-}" ] || exit 95
  [ -n "${DISCOPARTY_TEST_AUTH_LOGOUT_MARKER:-}" ] || exit 95
  if [ "${DISCOPARTY_TEST_AUTH_LOGOUT_FAIL:-0}" = "1" ]; then
    exit 95
  fi
  rm -f "$DISCOPARTY_TEST_AUTH_LOGOUT_MARKER"
  printf '%s\n' 'logout-configured' >> "${DISCOPARTY_TEST_AUTH_LOGOUT_LOG:?}"
  printf '%s\n' 'Isolated ChatGPT logout verified.'
  exit 0
fi
if [ "${1##*/}" = "discord_permissions.py" ]; then
  arguments=" $* "
  if [ "${2:-}" = "harden-state" ]; then
    [[ "$arguments" == *" harden-state --conversations-dir "* ]] || exit 81
    printf '%s\n' '{"checks":{"claude_state_modes":"pass"}}'
    exit 0
  fi
  [ "${2:-}" = "verify" ] || exit 81
  [[ "$arguments" == *" verify --token-stdin --guild-id 200000000000000023 "* ]] || exit 82
  [[ "$arguments" == *" --bot-user-id 200000000000000021 "* ]] || exit 82
  [[ "$arguments" == *" --application-id 200000000000000022 --conversations-dir "* ]] || exit 82
  IFS= read -r token
  [ "$token" = "claude-token" ] || exit 83
  printf '%s\n' '{"checks":{"claude_permissions":"pass"}}'
  exit 0
fi
exec "$DISCOPARTY_TEST_REAL_PYTHON" "$@"
EOF

cat > "$FAKE_BIN/security" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
"${DISCOPARTY_TEST_SECRET_PROBE:?}" "$0" "$@"
operation="${1:-}"
shift || true
account=""
service=""
password=""
wants_password=0
while [ $# -gt 0 ]; do
  case "$1" in
    -s) service="$2"; shift 2 ;;
    -a) account="$2"; shift 2 ;;
    -w)
      if [ $# -gt 1 ] && [[ "$2" != -* ]]; then
        password="$2"
        shift 2
      else
        wants_password=1
        shift
      fi
      ;;
    -U) shift ;;
    *) shift ;;
  esac
done
[ -n "$account" ] || exit 2
case "$service" in
  thesystem-secret) entry="$HOME/.fake-keychain-thesystem-$account" ;;
  *) entry="$HOME/.fake-keychain-$account" ;;
esac
case "$operation" in
  find-generic-password)
    [ -f "$entry" ] || exit 44
    if [ "$wants_password" = "1" ]; then cat "$entry"; fi
    ;;
  add-generic-password)
    if [ "$wants_password" = "1" ]; then
      IFS= read -r password
    fi
    printf '%s' "$password" > "$entry"
    chmod 600 "$entry"
    ;;
  delete-generic-password)
    [ -f "$entry" ] || exit 44
    rm -f "$entry"
    ;;
  *) exit 2 ;;
esac
EOF

cat > "$FAKE_BIN/plutil" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
"${DISCOPARTY_TEST_SECRET_PROBE:?}" "$0" "$@"
[ "${1:-}" = "-lint" ] || exit 2
python3 - "$2" <<'PY'
import plistlib
import sys
with open(sys.argv[1], "rb") as stream:
    plistlib.load(stream)
PY
EOF

cat > "$FAKE_BIN/launchctl" <<'EOF'
#!/usr/bin/env bash
"${DISCOPARTY_TEST_SECRET_PROBE:?}" "$0" "$@"
printf '%s\n' "$*" >> "$DISCOPARTY_TEST_LAUNCHCTL_LOG"
if [ -n "${DISCOPARTY_TEST_INSTALL_ORDER_LOG:-}" ]; then
  printf 'launchctl %s\n' "$*" >> "$DISCOPARTY_TEST_INSTALL_ORDER_LOG"
fi
if [ "${DISCOPARTY_TEST_LAUNCHCTL_SCENARIO:-}" = "loaded-bootout-fails" ]; then
  case "${1:-}" in
    print)
      if [ -n "${DISCOPARTY_TEST_LAUNCHCTL_LOADED_LABEL:-}" ] && \
        [ "${2:-}" != "gui/$UID/$DISCOPARTY_TEST_LAUNCHCTL_LOADED_LABEL" ]; then
        exit 1
      fi
      exit 0
      ;;
    bootout) exit 93 ;;
    bootstrap|enable|disable|kickstart) exit 93 ;;
    *) exit 2 ;;
  esac
fi
if [ "${DISCOPARTY_TEST_LAUNCHCTL_SCENARIO:-}" = "stateful" ]; then
  state_file="${DISCOPARTY_TEST_LAUNCHCTL_STATE:?}"
  case "${1:-}" in
    print)
      if [ -n "${DISCOPARTY_TEST_LAUNCHCTL_LOADED_LABEL:-}" ] && \
        [ "${2:-}" != "gui/$UID/$DISCOPARTY_TEST_LAUNCHCTL_LOADED_LABEL" ]; then
        exit 1
      fi
      [ "$(cat "$state_file" 2>/dev/null || true)" = "loaded" ]
      ;;
    bootout)
      if [ -n "${DISCOPARTY_TEST_LAUNCHCTL_LOADED_LABEL:-}" ] && \
        [ "${2:-}" != "gui/$UID/$DISCOPARTY_TEST_LAUNCHCTL_LOADED_LABEL" ]; then
        exit 1
      fi
      [ "$(cat "$state_file" 2>/dev/null || true)" = "loaded" ] || exit 93
      printf '%s\n' unloaded > "$state_file"
      ;;
    bootstrap)
      if [ -n "${DISCOPARTY_TEST_EXPECT_RESTORED_CONFIG_PATH:-}" ]; then
        [ "$(cat "$DISCOPARTY_TEST_EXPECT_RESTORED_CONFIG_PATH")" = \
          "$DISCOPARTY_TEST_EXPECT_RESTORED_CONFIG_VALUE" ] || exit 86
        [ "$(cat "$DISCOPARTY_TEST_EXPECT_RESTORED_CODEX_CONFIG_PATH")" = \
          "$DISCOPARTY_TEST_EXPECT_RESTORED_CODEX_CONFIG_VALUE" ] || exit 87
        [ "$(cat "$DISCOPARTY_TEST_EXPECT_RESTORED_KEYCHAIN_PATH")" = \
          "$DISCOPARTY_TEST_EXPECT_RESTORED_KEYCHAIN_VALUE" ] || exit 88
      fi
      printf '%s\n' loaded > "$state_file"
      ;;
    enable|disable|kickstart) exit 0 ;;
    *) exit 2 ;;
  esac
  exit $?
fi
case "${1:-}" in
  print|print-disabled) exit 1 ;;
  bootstrap|bootout|enable|disable|kickstart) exit 93 ;;
  *) exit 2 ;;
esac
EOF

cat > "$FAKE_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
"${DISCOPARTY_TEST_SECRET_PROBE:?}" "$0" "$@"
if [ "${1:-}" = "has-session" ]; then
  [ "${2:-}" = "-t" ] || exit 2
  [ "${3:-}" = "=cx-chat" ] || exit 1
  [ "${DISCOPARTY_TEST_LEGACY_TMUX:-0}" = "1" ]
  exit $?
fi
exit 0
EOF

cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
"${DISCOPARTY_TEST_SECRET_PROBE:?}" "$0" "$@"
if [ "${1:-}" = "plugin" ] && [ "${2:-}" = "list" ]; then
  printf '%s\n' 'discord@claude-plugins-official'
  exit 0
fi
exit 2
EOF

cat > "$FAKE_BIN/bun" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod 755 "$FAKE_BIN"/*

COMMON_ENV=(
  "HOME=$TEST_HOME"
  "PATH=$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
  "DISCOPARTY_TEST_REAL_PYTHON=$REAL_PYTHON"
  "DISCOPARTY_TEST_LAUNCHCTL_LOG=$LAUNCHCTL_LOG"
  "DISCOPARTY_TEST_SECRET_PROBE=$FAKE_BIN/assert-no-secret"
  "DISCOPARTY_TEST_SECRET_PROBE_LOG=$SECRET_PROBE_LOG"
  "DISCOPARTY_TEST_EXPECT_REAL_HOME=$TEST_HOME"
  "DISCOPARTY_TEST_PYTHON_BIN=$FAKE_BIN/python3"
  "DISCOPARTY_TEST_SECURITY_BIN=$FAKE_BIN/security"
  "DISCOPARTY_TEST_LAUNCHCTL_BIN=$FAKE_BIN/launchctl"
  "DISCOPARTY_TEST_PLUTIL_BIN=$FAKE_BIN/plutil"
  "DISCOPARTY_TEST_UNAME_BIN=$FAKE_BIN/uname"
  "DISCOPARTY_TEST_SYSCTL_BIN=$FAKE_BIN/sysctl"
  "DISCOPARTY_REPO_ROOT=$TEST_REPO"
  "DISCOPARTY_CODEX_BIN=$FAKE_BIN/codex"
  "DISCOPARTY_CODEX_GUILD_ID=100000000000000001"
  "DISCOPARTY_CODEX_CHANNEL_ID=100000000000000002"
  "DISCOPARTY_CODEX_OWNER_USER_ID=100000000000000003"
  "DISCOPARTY_CODEX_BOT_USER_ID=100000000000000004"
  "DISCOPARTY_CODEX_APPLICATION_ID=100000000000000005"
  "DISCOPARTY_CODEX_WORKING_DIRECTORY=$WORK_DIR"
  "DISCOPARTY_CODEX_SANDBOX_MODE=workspace-write"
  "OLD_KEYCHAIN_TOKEN=codex-test-token-without-spaces-123"
)

# Noninteractive installs must begin with the dedicated credential already in
# Keychain. The fake security client maps this private fixture to that entry.
printf '%s' 'codex-test-token-without-spaces-123' \
  > "$TEST_HOME/.fake-keychain-discord-bot-token-codex"
chmod 600 "$TEST_HOME/.fake-keychain-discord-bot-token-codex"

FORBIDDEN_ENV_TOKEN='forbidden-environment-token-should-not-be-read'
if env "${COMMON_ENV[@]}" \
  DISCOPARTY_CODEX_DISCORD_BOT_TOKEN="$FORBIDDEN_ENV_TOKEN" \
  DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor \
  >"$TEST_ROOT/discord-token-env.log" 2>&1; then
  echo "installer accepted a Discord token from the process environment" >&2
  exit 1
fi
grep -Fq "DISCOPARTY_CODEX_DISCORD_BOT_TOKEN is forbidden" \
  "$TEST_ROOT/discord-token-env.log"
! grep -Fq "$FORBIDDEN_ENV_TOKEN" "$TEST_ROOT/discord-token-env.log"

if env "${COMMON_ENV[@]}" \
  DISCOPARTY_CODEX_SANDBOX_MODE=danger-full-access \
  DISCOPARTY_CODEX_CHANNEL_TRUST=public \
  DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=not-accepted \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor \
  >"$TEST_ROOT/wrong-acceptance.log" 2>&1; then
  echo "installer accepted danger-full-access without the exact acknowledgement" >&2
  exit 1
fi
grep -Fq "requires DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED" \
  "$TEST_ROOT/wrong-acceptance.log"
test ! -e "$TEST_HOME/Library/Application Support/Discoparty/codex-discord"

cat > "$FAKE_BIN/sysctl-base-m5" <<'EOF'
#!/usr/bin/env bash
"${DISCOPARTY_TEST_SECRET_PROBE:?}" "$0" "$@"
if [ "${1:-}" = "-n" ] && [ "${2:-}" = "machdep.cpu.brand_string" ]; then
  echo "Apple M5"
  exit 0
fi
exit 2
EOF
chmod 755 "$FAKE_BIN/sysctl-base-m5"
if env "${COMMON_ENV[@]}" \
  DISCOPARTY_TEST_SYSCTL_BIN="$FAKE_BIN/sysctl-base-m5" \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor \
  >"$TEST_ROOT/base-m5.log" 2>&1; then
  echo "installer accepted a base Apple M5 host" >&2
  exit 1
fi
grep -Fq "targets the reviewed Apple M5 Max host" "$TEST_ROOT/base-m5.log"
test ! -e "$TEST_HOME/Library/Application Support/Discoparty/codex-discord"

if env "${COMMON_ENV[@]}" \
  OPENAI_API_KEY=forbidden \
  DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor \
  >"$TEST_ROOT/api-key.log" 2>&1; then
  echo "installer accepted OPENAI_API_KEY" >&2
  exit 1
fi
grep -Fq "OPENAI_API_KEY must be unset" "$TEST_ROOT/api-key.log"

OUTSIDE_APPROVED_STATE="$TEST_HOME/outside-approved-root"
if env "${COMMON_ENV[@]}" \
  DISCOPARTY_CODEX_STATE_DIR="$OUTSIDE_APPROVED_STATE" \
  DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor \
  >"$TEST_ROOT/state-approved-root.log" 2>&1; then
  echo "installer accepted a state directory outside the approved macOS root" >&2
  exit 1
fi
grep -Fq "state_dir must stay under canonical ~/Library/Application Support/Discoparty" \
  "$TEST_ROOT/state-approved-root.log"
test ! -e "$OUTSIDE_APPROVED_STATE"

chmod 777 "$TEST_HOME"
if env "${COMMON_ENV[@]}" \
  DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor \
  >"$TEST_ROOT/home-mode.log" 2>&1; then
  echo "installer accepted a group/world-writable HOME" >&2
  exit 1
fi
grep -Fq "Canonical HOME must be current-user-owned and not group/world writable" \
  "$TEST_ROOT/home-mode.log"
chmod 700 "$TEST_HOME"

chmod 777 "$TEST_HOME/Library/Application Support"
if env "${COMMON_ENV[@]}" \
  DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor \
  >"$TEST_ROOT/application-support-mode.log" 2>&1; then
  echo "installer accepted a writable Application Support ancestry" >&2
  exit 1
fi
grep -Fq "state_dir components must not be group/world writable" \
  "$TEST_ROOT/application-support-mode.log"
chmod 700 "$TEST_HOME/Library/Application Support"

UNSAFE_REPO_STATE="$TEST_REPO/unsafe-codex-state"
if env "${COMMON_ENV[@]}" \
  DISCOPARTY_CODEX_STATE_DIR="$UNSAFE_REPO_STATE" \
  DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor \
  >"$TEST_ROOT/state-repo-overlap.log" 2>&1; then
  echo "installer accepted a state directory inside the repository" >&2
  exit 1
fi
grep -Fq "state_dir must not overlap the Disco Party repository" \
  "$TEST_ROOT/state-repo-overlap.log"
test ! -e "$UNSAFE_REPO_STATE"

if env "${COMMON_ENV[@]}" \
  DISCOPARTY_CODEX_WORKING_DIRECTORY="$TEST_REPO" \
  DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor \
  >"$TEST_ROOT/workspace-repo-overlap.log" 2>&1; then
  echo "installer accepted a workspace that overlaps the repository" >&2
  exit 1
fi
grep -Fq "working_directory must not overlap the Disco Party repository" \
  "$TEST_ROOT/workspace-repo-overlap.log"

SHARED_TEST_ROOT="$TEST_ROOT/claude-workspace/x_System/Skills"
if env "${COMMON_ENV[@]}" \
  DISCOPARTY_CODEX_WORKING_DIRECTORY="$SHARED_TEST_ROOT" \
  DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor \
  >"$TEST_ROOT/workspace-shared-skills-equal.log" 2>&1; then
  echo "installer accepted the canonical shared skill root as its workspace" >&2
  exit 1
fi
grep -Fq "canonical shared Vault skill root must not overlap the Codex working_directory" \
  "$TEST_ROOT/workspace-shared-skills-equal.log"

if env "${COMMON_ENV[@]}" \
  DISCOPARTY_CODEX_WORKING_DIRECTORY="$SHARED_TEST_ROOT/eli5" \
  DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor \
  >"$TEST_ROOT/workspace-shared-skills-descendant.log" 2>&1; then
  echo "installer accepted a shared skill child as its workspace" >&2
  exit 1
fi
grep -Fq "canonical shared Vault skill root must not overlap the Codex working_directory" \
  "$TEST_ROOT/workspace-shared-skills-descendant.log"

if env "${COMMON_ENV[@]}" \
  DISCOPARTY_CODEX_WORKING_DIRECTORY="$SHARED_TEST_ROOT/.." \
  DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor \
  >"$TEST_ROOT/workspace-shared-skills-ancestor.log" 2>&1; then
  echo "installer accepted a shared skill ancestor as its workspace" >&2
  exit 1
fi
grep -Fq "canonical shared Vault skill root must not overlap the Codex working_directory" \
  "$TEST_ROOT/workspace-shared-skills-ancestor.log"

SHARED_TEST_ALIAS="/System/Volumes/Data$TEST_ROOT/claude-workspace/x_System"
if [ -d "$SHARED_TEST_ALIAS" ] && \
  [ "$SHARED_TEST_ALIAS" -ef "$TEST_ROOT/claude-workspace/x_System" ]; then
  if env "${COMMON_ENV[@]}" \
    DISCOPARTY_CODEX_WORKING_DIRECTORY="$SHARED_TEST_ALIAS" \
    DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED \
    "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor \
    >"$TEST_ROOT/workspace-shared-skills-alias.log" 2>&1; then
    echo "installer accepted a filesystem alias containing the shared skills" >&2
    exit 1
  fi
  grep -Fq "canonical shared Vault skill root must not overlap the Codex working_directory" \
    "$TEST_ROOT/workspace-shared-skills-alias.log"
fi

OVERLAP_WORKSPACE="$APP_SUPPORT_ROOT/overlap-workspace"
mkdir "$OVERLAP_WORKSPACE"
if env "${COMMON_ENV[@]}" \
  DISCOPARTY_CODEX_WORKING_DIRECTORY="$OVERLAP_WORKSPACE" \
  DISCOPARTY_CODEX_STATE_DIR="$OVERLAP_WORKSPACE/codex-state" \
  DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor \
  >"$TEST_ROOT/state-workspace-overlap.log" 2>&1; then
  echo "installer accepted overlapping workspace and state directories" >&2
  exit 1
fi
grep -Fq "state_dir must not overlap the Codex working_directory" \
  "$TEST_ROOT/state-workspace-overlap.log"
test ! -e "$OVERLAP_WORKSPACE/codex-state"
rmdir "$OVERLAP_WORKSPACE"

if env "${COMMON_ENV[@]}" \
  DISCOPARTY_CODEX_WORKING_DIRECTORY="$TEST_HOME/Library/LaunchAgents" \
  DISCOPARTY_CODEX_STATE_DIR="$APP_SUPPORT_ROOT/safe-control-test-state" \
  DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor \
  >"$TEST_ROOT/workspace-control-overlap.log" 2>&1; then
  echo "installer accepted a workspace containing LaunchAgent controls" >&2
  exit 1
fi
grep -Fq "Codex LaunchAgent plist must not overlap the Codex working_directory" \
  "$TEST_ROOT/workspace-control-overlap.log"

mkdir "$APP_SUPPORT_ROOT/state-target"
ln -s "$APP_SUPPORT_ROOT/state-target" "$APP_SUPPORT_ROOT/state-link"
if env "${COMMON_ENV[@]}" \
  DISCOPARTY_CODEX_STATE_DIR="$APP_SUPPORT_ROOT/state-link" \
  DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor \
  >"$TEST_ROOT/state-symlink.log" 2>&1; then
  echo "installer accepted a symlinked state directory" >&2
  exit 1
fi
grep -Fq "state_dir components must be real directories, not symlinks" \
  "$TEST_ROOT/state-symlink.log"
rm -f "$APP_SUPPORT_ROOT/state-link"
rmdir "$APP_SUPPORT_ROOT/state-target"

mkdir "$APP_SUPPORT_ROOT/unsafe-state-parent"
chmod 777 "$APP_SUPPORT_ROOT/unsafe-state-parent"
if env "${COMMON_ENV[@]}" \
  DISCOPARTY_CODEX_STATE_DIR="$APP_SUPPORT_ROOT/unsafe-state-parent/codex-state" \
  DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor \
  >"$TEST_ROOT/state-parent-mode.log" 2>&1; then
  echo "installer accepted a group/world-writable state ancestor" >&2
  exit 1
fi
grep -Fq "state_dir components must not be group/world writable" \
  "$TEST_ROOT/state-parent-mode.log"
test ! -e "$APP_SUPPORT_ROOT/unsafe-state-parent/codex-state"
chmod 700 "$APP_SUPPORT_ROOT/unsafe-state-parent"
rmdir "$APP_SUPPORT_ROOT/unsafe-state-parent"

mkdir "$TEST_ROOT/log-target"
ln -s "$TEST_ROOT/log-target" "$TEST_REPO/logs"
if env "${COMMON_ENV[@]}" \
  DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor \
  >"$TEST_ROOT/log-symlink.log" 2>&1; then
  echo "installer accepted a symlinked logs directory" >&2
  exit 1
fi
grep -Fq "Codex logs directory must be a real directory, not a symlink" \
  "$TEST_ROOT/log-symlink.log"
rm -f "$TEST_REPO/logs"
rmdir "$TEST_ROOT/log-target"

mkdir "$TEST_REPO/logs"
touch "$TEST_ROOT/stdout-target.log"
ln -s "$TEST_ROOT/stdout-target.log" \
  "$TEST_REPO/logs/codex-discord-bridge.stdout.log"
if env "${COMMON_ENV[@]}" \
  DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor \
  >"$TEST_ROOT/stdout-log-symlink.log" 2>&1; then
  echo "installer accepted a symlinked stdout log" >&2
  exit 1
fi
grep -Fq "Codex stdout log must be a real regular file, not a symlink" \
  "$TEST_ROOT/stdout-log-symlink.log"
rm -f "$TEST_REPO/logs/codex-discord-bridge.stdout.log"
rmdir "$TEST_REPO/logs"
rm -f "$TEST_ROOT/stdout-target.log"

chmod 666 "$TEST_REPO/config.toml"
if env "${COMMON_ENV[@]}" \
  DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor \
  >"$TEST_ROOT/config-mode.log" 2>&1; then
  echo "installer accepted a group/world-writable config" >&2
  exit 1
fi
grep -Fq "Disco Party config must not be group/world writable" \
  "$TEST_ROOT/config-mode.log"
chmod 600 "$TEST_REPO/config.toml"
test ! -e "$TEST_HOME/Library/Application Support/Discoparty/codex-discord"
test ! -e "$TEST_REPO/logs"

env "${COMMON_ENV[@]}" \
  DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor \
  >"$TEST_ROOT/install.log"

PLIST="$TEST_HOME/Library/LaunchAgents/com.discoparty.codex-discord-bridge.plist"
INSTALLED_CODEX_HOME="$CANONICAL_TEST_HOME/Library/Application Support/Discoparty/codex-discord/home/.codex"
test -f "$PLIST"
DISCOPARTY_TEST_SECRET_PROBE="$FAKE_BIN/assert-no-secret" \
  DISCOPARTY_TEST_SECRET_PROBE_LOG="$SECRET_PROBE_LOG" \
  "$FAKE_BIN/plutil" -lint "$PLIST" >/dev/null
grep -Fq "CLAUDE_SENTINEL" "$TEST_REPO/config.toml"
grep -Fq 'keep_me = "untouched"' "$TEST_REPO/config.toml"
grep -Fq 'chat_channel_id = "200000000000000001"' "$TEST_REPO/config.toml"
grep -Fq 'channel_id = "100000000000000002"' "$TEST_REPO/config.toml"
grep -Fq 'sandbox_mode = "workspace-write"' "$TEST_REPO/config.toml"
grep -Fq 'full_computer_access_accepted = false' "$TEST_REPO/config.toml"
grep -Fq "shared_skills_root = \"$TEST_ROOT/claude-workspace/x_System/Skills\"" \
  "$TEST_REPO/config.toml"
[ "$(readlink "$INSTALLED_CODEX_HOME/skills/eli5")" = \
  "$TEST_ROOT/claude-workspace/x_System/Skills/eli5" ]
[ "$(readlink "$INSTALLED_CODEX_HOME/skills/vinaytalks")" = \
  "$TEST_ROOT/claude-workspace/x_System/Skills/marketing/websites/vinaytalks" ]
[ "$(readlink "$INSTALLED_CODEX_HOME/skills/triage")" = \
  "$TEST_ROOT/claude-workspace/x_System/Skills/triage" ]
[ "$(readlink "$INSTALLED_CODEX_HOME/skills/skill-finder")" = \
  "$TEST_ROOT/claude-workspace/x_System/Skills/skill-finder" ]
grep -Fq "state_dir = \"$CANONICAL_TEST_HOME/Library/Application Support/Discoparty/codex-discord\"" \
  "$TEST_REPO/config.toml"
grep -Fq "codex_home = \"$CANONICAL_TEST_HOME/Library/Application Support/Discoparty/codex-discord/home/.codex\"" \
  "$TEST_REPO/config.toml"
grep -Fq "instructions_file = \"$TEST_ROOT/trusted-instructions.md\"" "$TEST_REPO/config.toml"
grep -Fq 'max_messages_per_minute = 6' "$TEST_REPO/config.toml"
grep -Fq 'max_messages_per_hour = 24' "$TEST_REPO/config.toml"
grep -Fq 'max_concurrent_workers = 4' "$TEST_REPO/config.toml"
grep -Fq 'max_pending_jobs = 40' "$TEST_REPO/config.toml"
grep -Fq 'max_input_chars = 9000' "$TEST_REPO/config.toml"
grep -Fq 'retention_days = 14' "$TEST_REPO/config.toml"
grep -Fq 'max_database_bytes = 134217728' "$TEST_REPO/config.toml"
[ "$(grep -c '^\[codex\]$' "$TEST_REPO/config.toml")" = "1" ]
! grep -Fq 'codex-test-token-without-spaces-123' "$TEST_REPO/config.toml" "$PLIST"
! grep -Fq 'OPENAI_API_KEY' "$TEST_REPO/config.toml" "$PLIST"
[ "$(cat "$TEST_HOME/.fake-keychain-discord-bot-token-codex")" = "codex-test-token-without-spaces-123" ]
[ "$("$REAL_PYTHON" -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$PLIST")" = "0o600" ]
test ! -e "$TEST_HOME/Library/Application Support/Discoparty/codex-discord/home/.codex/auth.json"
grep -Fq 'cli_auth_credentials_store = "keyring"' \
  "$TEST_HOME/Library/Application Support/Discoparty/codex-discord/home/.codex/config.toml"
INSTALLED_HOOKS="$INSTALLED_CODEX_HOME/hooks.json"
test -f "$INSTALLED_HOOKS"
! grep -Fq "$TEST_ROOT/claude-workspace" "$INSTALLED_HOOKS"
grep -Fq '/usr/bin/python3 -I -S' "$INSTALLED_HOOKS"
grep -Fq -- '--discoparty-deny-only' "$INSTALLED_HOOKS"
"$REAL_PYTHON" - "$INSTALLED_HOOKS" \
  "$TEST_HOME/Library/Application Support/Discoparty/codex-discord/hook-runtime" <<'PY'
import json
import os
import stat
import sys
from pathlib import Path

hooks_path = Path(sys.argv[1])
runtime_parent = Path(sys.argv[2])
assert stat.S_IMODE(hooks_path.stat().st_mode) == 0o600
payload = json.loads(hooks_path.read_text())
groups = payload["hooks"]["PreToolUse"]
assert [group["matcher"] for group in groups] == [
    "^Bash$", "^(Bash|apply_patch)$", "^Bash$"
]
commands = [group["hooks"][0]["command"] for group in groups]
assert all(command.startswith("/usr/bin/python3 -I -S ") for command in commands)
roots = list(runtime_parent.iterdir())
assert len(roots) == 1
runtime = roots[0]
assert stat.S_IMODE(runtime.stat().st_mode) == 0o500
assert {path.name for path in runtime.iterdir()} == {
    "manifest.json",
    "security_validator.py",
    "em-dash-write-validator.py",
    "outbound_send_gate_hook.py",
    "hook_command_detect.py",
}
for path in runtime.iterdir():
    metadata = path.stat()
    assert stat.S_IMODE(metadata.st_mode) == 0o400
    assert metadata.st_nlink == 1
    assert not path.is_symlink()
    assert str(path) in "\n".join(commands) or path.name == "manifest.json"
PY
test -f "$TEST_HOME/Library/Application Support/Discoparty/codex-discord/policy/vault-p0.md"
grep -Fq 'Source SHA-256:' \
  "$TEST_HOME/Library/Application Support/Discoparty/codex-discord/policy/vault-p0.md"
! grep -Eq '(^| )(bootstrap|bootout|enable|kickstart)( |$)' "$LAUNCHCTL_LOG"

cp "$TEST_REPO/config.toml" "$TEST_ROOT/config-valid-worker-pool.toml"
"$REAL_PYTHON" - "$TEST_REPO/config.toml" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
old = "max_concurrent_workers = 4"
if text.count(old) != 1:
    raise SystemExit("worker-pool fixture is not unique")
path.write_text(text.replace(old, "max_concurrent_workers = 5", 1))
PY
if env "${COMMON_ENV[@]}" \
  DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor --reinstall \
  >"$TEST_ROOT/worker-pool-range.log" 2>&1; then
  echo "installer accepted max_concurrent_workers outside 1..4" >&2
  exit 1
fi
grep -Fq "codex.max_concurrent_workers must be between 1 and 4" \
  "$TEST_ROOT/worker-pool-range.log"
cp "$TEST_ROOT/config-valid-worker-pool.toml" "$TEST_REPO/config.toml"
chmod 600 "$TEST_REPO/config.toml"

LOG_SWAP_TARGET="$TEST_ROOT/recheck-log-target.log"
if env "${COMMON_ENV[@]}" \
  DISCOPARTY_TEST_PREFLIGHT_LOG_SYMLINK=1 \
  DISCOPARTY_TEST_LOG_SWAP_TARGET="$LOG_SWAP_TARGET" \
  DISCOPARTY_CODEX_CHANNEL_ID=100000000000000009 \
  DISCOPARTY_CODEX_SANDBOX_MODE=workspace-write \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor --reinstall \
  >"$TEST_ROOT/log-recheck.log" 2>&1; then
  echo "installer accepted a stdout symlink introduced after topology validation" >&2
  exit 1
fi
grep -Fq "Codex log target codex-discord-bridge.stdout.log" \
  "$TEST_ROOT/log-recheck.log"
test -L "$TEST_REPO/logs/codex-discord-bridge.stdout.log"
rm -f "$TEST_REPO/logs/codex-discord-bridge.stdout.log" "$LOG_SWAP_TARGET"
grep -Fq 'channel_id = "100000000000000002"' "$TEST_REPO/config.toml"
grep -Fq 'sandbox_mode = "workspace-write"' "$TEST_REPO/config.toml"

if env "${COMMON_ENV[@]}" \
  DISCOPARTY_TEST_AUTH_SCENARIO=filesystem-artifact \
  DISCOPARTY_CODEX_CHANNEL_ID=100000000000000009 \
  DISCOPARTY_CODEX_SANDBOX_MODE=workspace-write \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor --reinstall \
  >"$TEST_ROOT/auth-mode.log" 2>&1; then
  echo "installer accepted a filesystem ChatGPT credential artifact" >&2
  exit 1
fi
grep -Fq "ChatGPT login created a forbidden filesystem credential artifact" \
  "$TEST_ROOT/auth-mode.log"
grep -Fq 'channel_id = "100000000000000002"' "$TEST_REPO/config.toml"
grep -Fq 'sandbox_mode = "workspace-write"' "$TEST_REPO/config.toml"
rm -f "$INSTALLED_CODEX_HOME/auth.json"

env \
  "HOME=$CANONICAL_TEST_HOME" \
  "PATH=$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
  "DISCOPARTY_TEST_REAL_PYTHON=$REAL_PYTHON" \
  "DISCOPARTY_TEST_EXPECT_REAL_HOME=$CANONICAL_TEST_HOME" \
  "DISCOPARTY_TEST_LAUNCHCTL_LOG=$LAUNCHCTL_LOG" \
  "DISCOPARTY_TEST_SECRET_PROBE=$FAKE_BIN/assert-no-secret" \
  "DISCOPARTY_TEST_SECRET_PROBE_LOG=$SECRET_PROBE_LOG" \
  "OLD_KEYCHAIN_TOKEN=codex-test-token-without-spaces-123" \
  "DISCOPARTY_TEST_PYTHON_BIN=$FAKE_BIN/python3" \
  "DISCOPARTY_TEST_SECURITY_BIN=$FAKE_BIN/security" \
  "DISCOPARTY_TEST_LAUNCHCTL_BIN=$FAKE_BIN/launchctl" \
  "DISCOPARTY_TEST_PLUTIL_BIN=$FAKE_BIN/plutil" \
  "DISCOPARTY_TEST_UNAME_BIN=$FAKE_BIN/uname" \
  "DISCOPARTY_TEST_SYSCTL_BIN=$FAKE_BIN/sysctl" \
  "DISCOPARTY_REPO_ROOT=$TEST_REPO" \
  "DISCOPARTY_CODEX_BIN=$FAKE_BIN/codex" \
  "DISCOPARTY_CODEX_GUILD_ID=100000000000000001" \
  "DISCOPARTY_CODEX_CHANNEL_ID=100000000000000009" \
  "DISCOPARTY_CODEX_OWNER_USER_ID=100000000000000003" \
  "DISCOPARTY_CODEX_BOT_USER_ID=100000000000000004" \
  "DISCOPARTY_CODEX_APPLICATION_ID=100000000000000005" \
  "DISCOPARTY_CODEX_WORKING_DIRECTORY=$WORK_DIR" \
  "DISCOPARTY_CODEX_CHANNEL_TRUST=public" \
  "DISCOPARTY_CODEX_SANDBOX_MODE=danger-full-access" \
  "DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED" \
  "$TEST_REPO/install-codex.sh" --scratch --non-interactive --no-monitor --reinstall \
  >"$TEST_ROOT/public-full-access.log"

[ "$(grep -c '^\[codex\]$' "$TEST_REPO/config.toml")" = "1" ]
grep -Fq 'channel_id = "100000000000000009"' "$TEST_REPO/config.toml"
grep -Fq 'channel_trust = "public"' "$TEST_REPO/config.toml"
grep -Fq 'sandbox_mode = "danger-full-access"' "$TEST_REPO/config.toml"
grep -Fq 'full_computer_access_accepted = true' "$TEST_REPO/config.toml"
grep -Fq "CLAUDE_SENTINEL" "$TEST_REPO/config.toml"
grep -Fq "instructions_file = \"$TEST_ROOT/trusted-instructions.md\"" "$TEST_REPO/config.toml"
grep -Fq 'max_messages_per_minute = 6' "$TEST_REPO/config.toml"
grep -Fq 'max_messages_per_hour = 24' "$TEST_REPO/config.toml"
grep -Fq 'max_concurrent_workers = 4' "$TEST_REPO/config.toml"
grep -Fq 'max_pending_jobs = 40' "$TEST_REPO/config.toml"
grep -Fq 'max_input_chars = 9000' "$TEST_REPO/config.toml"
grep -Fq 'retention_days = 14' "$TEST_REPO/config.toml"
grep -Fq 'max_database_bytes = 134217728' "$TEST_REPO/config.toml"

# A Claude reinstall owns only the Claude tables in the shared file. It must
# leave the already-installed Codex provider byte-for-byte intact.
sed -n '/^\[codex\]$/,$p' "$TEST_REPO/config.toml" > "$TEST_ROOT/codex-before-claude.toml"
CLAUDE_COMMON_ENV=(
  "HOME=$CANONICAL_TEST_HOME"
  "PATH=$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
  "DISCOPARTY_TEST_REAL_PYTHON=$REAL_PYTHON"
  "DISCOPARTY_TEST_LAUNCHCTL_LOG=$LAUNCHCTL_LOG"
  "DISCOPARTY_TEST_SECRET_PROBE=$FAKE_BIN/assert-no-secret"
  "DISCOPARTY_TEST_SECRET_PROBE_LOG=$SECRET_PROBE_LOG"
  "DISCOPARTY_TEST_CLAUDE_BIN=$FAKE_BIN/claude"
  "DISCOPARTY_TEST_BUN_BIN=$FAKE_BIN/bun"
  "DISCOPARTY_CLAUDE_FULL_AUTHORITY=1"
  "REPO_ROOT=$TEST_REPO"
  "DISCOPARTY_TIMEZONE=America/New_York"
)

CLAUDE_REJECTED_WORKSPACE="$TEST_ROOT/claude-rejected-workspace"
cp "$TEST_REPO/config.toml" "$TEST_ROOT/config-before-legacy-guard.toml"
touch "$TEST_HOME/Library/LaunchAgents/com.thesystem.discord-gateway-client.plist"
if env "${CLAUDE_COMMON_ENV[@]}" \
  "DISCORD_BOT_TOKEN=claude-token" \
  "WORKSPACE_ROOT=$CLAUDE_REJECTED_WORKSPACE" \
  "DISCOPARTY_LISTEN_CHANNEL_ID=200000000000000011" \
  "DISCOPARTY_ERRORS_CHANNEL_ID=200000000000000012" \
  "DISCOPARTY_OWNER_USER_ID=200000000000000013" \
  "$TEST_REPO/install.sh" --scratch --non-interactive --reinstall \
  >"$TEST_ROOT/claude-legacy-plist.log" 2>&1; then
  echo "Claude installer accepted a legacy com.thesystem gateway plist" >&2
  exit 1
fi
grep -Fq "Legacy Claude Discord footprint detected" \
  "$TEST_ROOT/claude-legacy-plist.log"
rm -f "$TEST_HOME/Library/LaunchAgents/com.thesystem.discord-gateway-client.plist"
cmp "$TEST_ROOT/config-before-legacy-guard.toml" "$TEST_REPO/config.toml"
test ! -e "$CLAUDE_REJECTED_WORKSPACE"
test ! -e "$TEST_HOME/.fake-keychain-discord-bot-token"

if env "${CLAUDE_COMMON_ENV[@]}" \
  "DISCOPARTY_TEST_LEGACY_TMUX=1" \
  "DISCORD_BOT_TOKEN=claude-token" \
  "WORKSPACE_ROOT=$CLAUDE_REJECTED_WORKSPACE" \
  "DISCOPARTY_LISTEN_CHANNEL_ID=200000000000000011" \
  "DISCOPARTY_ERRORS_CHANNEL_ID=200000000000000012" \
  "DISCOPARTY_OWNER_USER_ID=200000000000000013" \
  "$TEST_REPO/install.sh" --scratch --non-interactive --reinstall \
  >"$TEST_ROOT/claude-legacy-tmux.log" 2>&1; then
  echo "Claude installer accepted the legacy cx-chat tmux listener" >&2
  exit 1
fi
grep -Fq "tmux:cx-chat" "$TEST_ROOT/claude-legacy-tmux.log"
cmp "$TEST_ROOT/config-before-legacy-guard.toml" "$TEST_REPO/config.toml"
test ! -e "$CLAUDE_REJECTED_WORKSPACE"
test ! -e "$TEST_HOME/.fake-keychain-discord-bot-token"

LEGACY_CLAUDE_STATE="$TEST_ROOT/legacy-claude.launch-state"
printf '%s\n' loaded > "$LEGACY_CLAUDE_STATE"
if env "${CLAUDE_COMMON_ENV[@]}" \
  "DISCOPARTY_TEST_LAUNCHCTL_SCENARIO=stateful" \
  "DISCOPARTY_TEST_LAUNCHCTL_STATE=$LEGACY_CLAUDE_STATE" \
  "DISCOPARTY_TEST_LAUNCHCTL_LOADED_LABEL=com.thesystem.discord-gateway-client" \
  "DISCORD_BOT_TOKEN=claude-token" \
  "WORKSPACE_ROOT=$CLAUDE_REJECTED_WORKSPACE" \
  "DISCOPARTY_LISTEN_CHANNEL_ID=200000000000000011" \
  "DISCOPARTY_ERRORS_CHANNEL_ID=200000000000000012" \
  "DISCOPARTY_OWNER_USER_ID=200000000000000013" \
  "$TEST_REPO/install.sh" --scratch --non-interactive --reinstall \
  >"$TEST_ROOT/claude-legacy-loaded.log" 2>&1; then
  echo "Claude installer accepted a loaded legacy gateway without a plist" >&2
  exit 1
fi
grep -Fq "com.thesystem.discord-gateway-client (loaded)" \
  "$TEST_ROOT/claude-legacy-loaded.log"
cmp "$TEST_ROOT/config-before-legacy-guard.toml" "$TEST_REPO/config.toml"
test ! -e "$CLAUDE_REJECTED_WORKSPACE"
test ! -e "$TEST_HOME/.fake-keychain-discord-bot-token"

if env "${CLAUDE_COMMON_ENV[@]}" \
  "DISCORD_BOT_TOKEN=claude-token" \
  "WORKSPACE_ROOT=$CLAUDE_REJECTED_WORKSPACE" \
  "DISCOPARTY_LISTEN_CHANNEL_ID=100000000000000009" \
  "DISCOPARTY_ERRORS_CHANNEL_ID=200000000000000012" \
  "DISCOPARTY_OWNER_USER_ID=200000000000000013" \
  "$TEST_REPO/install.sh" --scratch --non-interactive --reinstall \
  >"$TEST_ROOT/claude-shared-channel.log" 2>&1; then
  echo "Claude installer accepted the configured Codex channel" >&2
  exit 1
fi
grep -Fq "Claude and Codex must use different Discord channels" \
  "$TEST_ROOT/claude-shared-channel.log"
cmp "$TEST_ROOT/config-before-legacy-guard.toml" "$TEST_REPO/config.toml"
test ! -e "$CLAUDE_REJECTED_WORKSPACE"
test ! -e "$TEST_HOME/.fake-keychain-discord-bot-token"

# Prove that the preserved provider's configured service/account are used,
# rather than a hard-coded Codex Keychain location.
cp "$TEST_REPO/config.toml" "$TEST_ROOT/config-before-custom-codex-keychain.toml"
"$REAL_PYTHON" - "$TEST_REPO/config.toml" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
old = (
    'keychain_service = "discoparty-secret"\n'
    'keychain_account = "discord-bot-token-codex"'
)
new = (
    'keychain_service = "thesystem-secret"\n'
    'keychain_account = "codex-separation-test"'
)
if text.count(old) != 1:
    raise SystemExit("could not locate the exact Codex Keychain binding")
path.write_text(text.replace(old, new, 1))
PY
mv \
  "$TEST_HOME/.fake-keychain-discord-bot-token-codex" \
  "$TEST_HOME/.fake-keychain-thesystem-codex-separation-test"
cp "$TEST_REPO/config.toml" "$TEST_ROOT/config-custom-keychain-before-reject.toml"
if env "${CLAUDE_COMMON_ENV[@]}" \
  "DISCORD_BOT_TOKEN=codex-test-token-without-spaces-123" \
  "WORKSPACE_ROOT=$CLAUDE_REJECTED_WORKSPACE" \
  "DISCOPARTY_LISTEN_CHANNEL_ID=200000000000000011" \
  "DISCOPARTY_ERRORS_CHANNEL_ID=200000000000000012" \
  "DISCOPARTY_OWNER_USER_ID=200000000000000013" \
  "$TEST_REPO/install.sh" --scratch --non-interactive --reinstall \
  >"$TEST_ROOT/claude-shared-token.log" 2>&1; then
  echo "Claude installer accepted the configured Codex bot token" >&2
  exit 1
fi
grep -Fq "Claude and Codex must use different Discord bot tokens" \
  "$TEST_ROOT/claude-shared-token.log"
cmp "$TEST_ROOT/config-custom-keychain-before-reject.toml" "$TEST_REPO/config.toml"
test ! -e "$CLAUDE_REJECTED_WORKSPACE"
test ! -e "$TEST_HOME/.fake-keychain-discord-bot-token"
mv \
  "$TEST_HOME/.fake-keychain-thesystem-codex-separation-test" \
  "$TEST_HOME/.fake-keychain-discord-bot-token-codex"
cp "$TEST_ROOT/config-before-custom-codex-keychain.toml" "$TEST_REPO/config.toml"
chmod 600 "$TEST_REPO/config.toml"

STALE_MARKER_STATE="$TEST_ROOT/stale-marker.launch-state"
STALE_MARKER_PLIST="$TEST_HOME/Library/LaunchAgents/com.discoparty.discord-marker-watcher.plist"
printf '%s\n' loaded > "$STALE_MARKER_STATE"
touch "$STALE_MARKER_PLIST"
cp "$TEST_REPO/config.toml" "$TEST_ROOT/config-before-marker-bootout-failure.toml"
if env "${CLAUDE_COMMON_ENV[@]}" \
  "DISCOPARTY_TEST_LAUNCHCTL_SCENARIO=loaded-bootout-fails" \
  "DISCOPARTY_TEST_LAUNCHCTL_LOADED_LABEL=com.discoparty.discord-marker-watcher" \
  "DISCORD_BOT_TOKEN=claude-token" \
  "WORKSPACE_ROOT=$CLAUDE_REJECTED_WORKSPACE" \
  "DISCOPARTY_LISTEN_CHANNEL_ID=200000000000000011" \
  "DISCOPARTY_ERRORS_CHANNEL_ID=200000000000000012" \
  "DISCOPARTY_OWNER_USER_ID=200000000000000013" \
  "$TEST_REPO/install.sh" --scratch --non-interactive --reinstall \
  >"$TEST_ROOT/claude-marker-bootout-failure.log" 2>&1; then
  echo "Claude installer continued after stale marker watcher bootout failed" >&2
  exit 1
fi
grep -Fq "Could not unload obsolete com.discoparty.discord-marker-watcher" \
  "$TEST_ROOT/claude-marker-bootout-failure.log"
cmp "$TEST_ROOT/config-before-marker-bootout-failure.toml" "$TEST_REPO/config.toml"
test -f "$STALE_MARKER_PLIST"
test ! -e "$CLAUDE_REJECTED_WORKSPACE"
test ! -e "$TEST_HOME/.fake-keychain-discord-bot-token"

mkdir -p "$TEST_ROOT/claude-reinstall-workspace"
cp \
  "$TEST_ROOT/claude-workspace/CLAUDE.md" \
  "$TEST_ROOT/claude-reinstall-workspace/CLAUDE.md"

env "${CLAUDE_COMMON_ENV[@]}" \
  "DISCOPARTY_TEST_LAUNCHCTL_SCENARIO=stateful" \
  "DISCOPARTY_TEST_LAUNCHCTL_STATE=$STALE_MARKER_STATE" \
  "DISCOPARTY_TEST_LAUNCHCTL_LOADED_LABEL=com.discoparty.discord-marker-watcher" \
  "DISCORD_BOT_TOKEN=claude-token" \
  "WORKSPACE_ROOT=$TEST_ROOT/claude-reinstall-workspace" \
  "DISCOPARTY_LISTEN_CHANNEL_ID=200000000000000011" \
  "DISCOPARTY_ERRORS_CHANNEL_ID=200000000000000012" \
  "DISCOPARTY_OWNER_USER_ID=200000000000000013" \
  "$TEST_REPO/install.sh" --scratch --non-interactive --reinstall \
  >"$TEST_ROOT/claude-reinstall.log"
[ "$(cat "$STALE_MARKER_STATE")" = "unloaded" ]
test ! -e "$STALE_MARKER_PLIST"
grep -Fq "Obsolete marker watcher is absent" "$TEST_ROOT/claude-reinstall.log"
sed -n '/^\[codex\]$/,$p' "$TEST_REPO/config.toml" > "$TEST_ROOT/codex-after-claude.toml"
cmp "$TEST_ROOT/codex-before-claude.toml" "$TEST_ROOT/codex-after-claude.toml"
[ "$(grep -c '^\[codex\]$' "$TEST_REPO/config.toml")" = "1" ]
grep -Fq 'enabled = true' "$TEST_ROOT/codex-after-claude.toml"
grep -Fq 'channel_id = "100000000000000009"' "$TEST_ROOT/codex-after-claude.toml"
grep -Fq 'chat_channel_id = "200000000000000011"' "$TEST_REPO/config.toml"
grep -Fq 'guild_id = "200000000000000023"' "$TEST_REPO/config.toml"
grep -Fq 'bot_user_id = "200000000000000021"' "$TEST_REPO/config.toml"
grep -Fq 'application_id = "200000000000000022"' "$TEST_REPO/config.toml"
"$REAL_PYTHON" -c 'import sys,tomllib; tomllib.load(open(sys.argv[1], "rb"))' \
  "$TEST_REPO/config.toml"

# A running Codex provider permits an exact Claude reinstall but blocks any
# new routing or principal binding before plugin, workspace, Keychain, or
# config mutation.
RUNNING_CODEX_STATE="$TEST_ROOT/claude-running-codex.launch-state"
printf '%s\n' loaded > "$RUNNING_CODEX_STATE"
env "${CLAUDE_COMMON_ENV[@]}" \
  "DISCOPARTY_TEST_LAUNCHCTL_SCENARIO=stateful" \
  "DISCOPARTY_TEST_LAUNCHCTL_STATE=$RUNNING_CODEX_STATE" \
  "DISCOPARTY_TEST_LAUNCHCTL_LOADED_LABEL=com.discoparty.codex-discord-bridge" \
  "DISCORD_BOT_TOKEN=claude-token" \
  "WORKSPACE_ROOT=$TEST_ROOT/claude-reinstall-workspace" \
  "DISCOPARTY_LISTEN_CHANNEL_ID=200000000000000011" \
  "DISCOPARTY_ERRORS_CHANNEL_ID=200000000000000012" \
  "DISCOPARTY_OWNER_USER_ID=200000000000000013" \
  "$TEST_REPO/install.sh" --scratch --non-interactive --reinstall \
  >"$TEST_ROOT/claude-running-codex-unchanged.log"

cp "$TEST_REPO/config.toml" "$TEST_ROOT/config-before-running-codex-reject.toml"
cp \
  "$TEST_HOME/.fake-keychain-discord-bot-token" \
  "$TEST_ROOT/claude-keychain-before-running-codex-reject"
RUNNING_REJECTED_WORKSPACE="$TEST_ROOT/claude-running-codex-rejected-workspace"
if env "${CLAUDE_COMMON_ENV[@]}" \
  "DISCOPARTY_TEST_LAUNCHCTL_SCENARIO=stateful" \
  "DISCOPARTY_TEST_LAUNCHCTL_STATE=$RUNNING_CODEX_STATE" \
  "DISCOPARTY_TEST_LAUNCHCTL_LOADED_LABEL=com.discoparty.codex-discord-bridge" \
  "DISCORD_BOT_TOKEN=claude-token" \
  "WORKSPACE_ROOT=$RUNNING_REJECTED_WORKSPACE" \
  "DISCOPARTY_LISTEN_CHANNEL_ID=200000000000000019" \
  "DISCOPARTY_ERRORS_CHANNEL_ID=200000000000000012" \
  "DISCOPARTY_OWNER_USER_ID=200000000000000013" \
  "$TEST_REPO/install.sh" --scratch --non-interactive --reinstall \
  >"$TEST_ROOT/claude-running-codex-changed.log" 2>&1; then
  echo "Claude installer changed routing while the Codex provider was running" >&2
  exit 1
fi
grep -Fq "Codex is running; stop it before changing Claude Discord routing or identity" \
  "$TEST_ROOT/claude-running-codex-changed.log"
cmp "$TEST_ROOT/config-before-running-codex-reject.toml" "$TEST_REPO/config.toml"
cmp \
  "$TEST_ROOT/claude-keychain-before-running-codex-reject" \
  "$TEST_HOME/.fake-keychain-discord-bot-token"
test ! -e "$RUNNING_REJECTED_WORKSPACE"

# Exercise the production reinstall ordering without granting the smoke test
# access to real launchd. This fixture is byte-for-byte production code with
# only its final main invocation removed.
SOURCEABLE_INSTALLER="$TEST_ROOT/install-codex-sourceable.sh"
[ "$(tail -n 1 "$TEST_REPO/install-codex.sh")" = 'main "$@"' ]
sed '$d' "$TEST_REPO/install-codex.sh" > "$SOURCEABLE_INSTALLER"

# Build an exact, private legacy deployment fixture under a separate HOME.
# All launchd and Keychain operations below use fakes; the live com.thesystem
# service and its credentials are never inspected or changed by this test.
LEGACY_TEST_ROOT="$TEST_ROOT/legacy-takeover"
LEGACY_TEST_HOME="$LEGACY_TEST_ROOT/home"
LEGACY_TEST_REPO="$LEGACY_TEST_HOME/TheSystem/x_System/Assistant/codex-discord-bridge"
LEGACY_TEST_PLIST="$LEGACY_TEST_HOME/Library/LaunchAgents/com.thesystem.codex-discord-bridge.plist"
LEGACY_TEST_STATE="$LEGACY_TEST_HOME/Library/Application Support/thesystem/codex-discord"
LEGACY_NEW_STATE="$LEGACY_TEST_HOME/Library/Application Support/Discoparty/codex-discord"
LEGACY_LAUNCH_STATE="$LEGACY_TEST_ROOT/legacy.launch-state"
LEGACY_NEW_LAUNCH_STATE="$LEGACY_TEST_ROOT/discoparty.launch-state"
LEGACY_DISABLED_STATE="$LEGACY_TEST_ROOT/legacy.disabled"
LEGACY_ORDER="$LEGACY_TEST_ROOT/order.log"
LEGACY_STATE_TRANSITIONS="$LEGACY_TEST_ROOT/state-transitions.log"
LEGACY_MUTATION_MARKER="$LEGACY_TEST_ROOT/unexpected-mutation"
LEGACY_ROOT_CURSOR=100000000000000190
LEGACY_POLICY_BINDING=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
mkdir -p "$LEGACY_TEST_ROOT"

create_legacy_fixture() {
  local trust="${1:-public}"
  local job_state="${2:-completed}"
  rm -rf \
    "$LEGACY_TEST_HOME/Library/Application Support/thesystem" \
    "$LEGACY_TEST_HOME/Library/Application Support/Discoparty" \
    "$LEGACY_TEST_REPO"
  rm -f \
    "$LEGACY_TEST_PLIST" \
    "$LEGACY_TEST_HOME/Library/LaunchAgents/com.discoparty.codex-discord-bridge.plist" \
    "$LEGACY_DISABLED_STATE" \
    "$LEGACY_TEST_HOME/.fake-keychain-discord-bot-token-codex" \
    "$LEGACY_TEST_HOME/.fake-keychain-thesystem-discord-bot-token-admin" \
    "$LEGACY_MUTATION_MARKER"
  : > "$LEGACY_ORDER"
  : > "$LEGACY_STATE_TRANSITIONS"
  mkdir -p \
    "$LEGACY_TEST_REPO" \
    "$LEGACY_TEST_HOME/Library/LaunchAgents" \
    "$LEGACY_TEST_STATE"
  chmod 700 \
    "$LEGACY_TEST_HOME" \
    "$LEGACY_TEST_REPO" \
    "$LEGACY_TEST_STATE"
  printf '%s\n' loaded > "$LEGACY_LAUNCH_STATE"
  printf '%s\n' unloaded > "$LEGACY_NEW_LAUNCH_STATE"
  printf '%s' 'codex-test-token-without-spaces-123' \
    > "$LEGACY_TEST_HOME/.fake-keychain-thesystem-discord-bot-token-admin"
  chmod 600 "$LEGACY_TEST_HOME/.fake-keychain-thesystem-discord-bot-token-admin"

  "$REAL_PYTHON" - \
    "$LEGACY_TEST_PLIST" "$LEGACY_TEST_REPO" "$LEGACY_TEST_HOME" \
    "$WORK_DIR" "$LEGACY_TEST_STATE/jobs.sqlite3" "$trust" "$job_state" \
    100000000000000001 100000000000000002 100000000000000003 \
    100000000000000004 100000000000000005 "$LEGACY_ROOT_CURSOR" <<'PY'
import os
import plistlib
import sqlite3
import sys
from pathlib import Path

(
    plist_raw,
    repo_raw,
    home_raw,
    workspace_raw,
    database_raw,
    trust,
    job_state,
    guild_id,
    channel_id,
    owner_id,
    bot_id,
    application_id,
    cursor,
) = sys.argv[1:]
plist = Path(plist_raw)
repo = Path(repo_raw).resolve(strict=True)
home = Path(home_raw).resolve(strict=True)
workspace = Path(workspace_raw).resolve(strict=True)
database = Path(database_raw)
payload = {
    "Label": "com.thesystem.codex-discord-bridge",
    "ProgramArguments": [
        "/opt/homebrew/bin/python3",
        "-m",
        "codex_discord_bridge.main",
    ],
    "WorkingDirectory": str(repo),
    "EnvironmentVariables": {
        "HOME": str(home),
        "PATH": "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        "PYTHONPATH": str(repo),
        "PYTHONUNBUFFERED": "1",
        "CODEX_DISCORD_GUILD_ID": guild_id,
        "CODEX_DISCORD_CHANNEL_ID": channel_id,
        "CODEX_DISCORD_OWNER_USER_ID": owner_id,
        "CODEX_DISCORD_BOT_USER_ID": bot_id,
        "CODEX_DISCORD_APPLICATION_ID": application_id,
        "CODEX_DISCORD_ENABLE": "FULL_COMPUTER_ACCESS_ACCEPTED",
        "CODEX_DISCORD_USE_SHARED_LOGIN": "1",
        "CODEX_DISCORD_CHANNEL_TRUST": trust,
        "CODEX_DISCORD_WORKSPACE": str(workspace),
    },
    "StandardOutPath": str(
        home / "Library/Logs/TheSystem/codex-discord-bridge.stdout.log"
    ),
    "StandardErrorPath": str(
        home / "Library/Logs/TheSystem/codex-discord-bridge.stderr.log"
    ),
    "RunAtLoad": True,
    "KeepAlive": {"Crashed": True, "SuccessfulExit": False},
    "ThrottleInterval": 10,
}
with plist.open("wb") as stream:
    plistlib.dump(payload, stream)
plist.chmod(0o600)

with sqlite3.connect(database) as db:
    db.executescript(
        """
        CREATE TABLE jobs (
          event_id TEXT PRIMARY KEY, guild_id TEXT, channel_id TEXT,
          author_id TEXT, state TEXT, ready INTEGER
        );
        CREATE TABLE sessions (scope TEXT PRIMARY KEY, thread_id TEXT);
        CREATE TABLE deliveries (
          event_id TEXT, chunk_index INTEGER, state TEXT
        );
        CREATE TABLE delivery_manifests (event_id TEXT PRIMARY KEY, state TEXT);
        CREATE TABLE channel_cursors (
          channel_id TEXT PRIMARY KEY, event_id TEXT
        );
        """
    )
    event_id = str(int(cursor) - 10)
    db.execute(
        "INSERT INTO jobs VALUES(?,?,?,?,?,1)",
        (event_id, guild_id, channel_id, owner_id, job_state),
    )
    delivery_state = "prepared" if job_state == "uncertain" else "sent"
    db.execute("INSERT INTO deliveries VALUES(?,0,?)", (event_id, delivery_state))
    db.execute(
        "INSERT INTO delivery_manifests VALUES(?,?)", (event_id, delivery_state)
    )
    db.execute("INSERT INTO sessions VALUES('legacy-scope','legacy-thread')")
    db.execute("INSERT INTO channel_cursors VALUES(?,?)", (channel_id, cursor))
database.chmod(0o600)
PY
}

LEGACY_FAKE_LAUNCHCTL="$LEGACY_TEST_ROOT/launchctl"
cat > "$LEGACY_FAKE_LAUNCHCTL" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
"${DISCOPARTY_TEST_SECRET_PROBE:?}" "$0" "$@"
printf 'launchctl %s\n' "$*" >> "$DISCOPARTY_TEST_INSTALL_ORDER_LOG"
command_name="${1:-}"
target="${2:-}"
case "$command_name" in
  print)
    case "$target" in
      */com.thesystem.codex-discord-bridge)
        [ "$(cat "$DISCOPARTY_TEST_LEGACY_LAUNCH_STATE")" = "loaded" ] || exit 1
        printf '    pid = %s\n' "${DISCOPARTY_TEST_LEGACY_PID:-999999}"
        ;;
      */com.discoparty.codex-discord-bridge)
        [ "$(cat "$DISCOPARTY_TEST_NEW_LAUNCH_STATE")" = "loaded" ]
        ;;
      *) exit 1 ;;
    esac
    ;;
  print-disabled)
    if [ -e "$DISCOPARTY_TEST_LEGACY_DISABLED_STATE" ]; then
      printf '"com.thesystem.codex-discord-bridge" => true\n'
    fi
    ;;
  bootout)
    case "$target" in
      */com.thesystem.codex-discord-bridge)
        [ "$(cat "$DISCOPARTY_TEST_LEGACY_LAUNCH_STATE")" = "loaded" ] || exit 93
        printf '%s\n' unloaded > "$DISCOPARTY_TEST_LEGACY_LAUNCH_STATE"
        ;;
      */com.discoparty.codex-discord-bridge)
        [ "$(cat "$DISCOPARTY_TEST_NEW_LAUNCH_STATE")" = "loaded" ] || exit 93
        printf '%s\n' unloaded > "$DISCOPARTY_TEST_NEW_LAUNCH_STATE"
        ;;
      *) exit 2 ;;
    esac
    ;;
  disable)
    : > "$DISCOPARTY_TEST_LEGACY_DISABLED_STATE"
    ;;
  enable)
    rm -f "$DISCOPARTY_TEST_LEGACY_DISABLED_STATE"
    ;;
  bootstrap)
    plist_path="${3:-}"
    case "${plist_path##*/}" in
      com.thesystem.codex-discord-bridge.plist)
        printf '%s\n' loaded > "$DISCOPARTY_TEST_LEGACY_LAUNCH_STATE"
        ;;
      com.discoparty.codex-discord-bridge.plist)
        printf '%s\n' loaded > "$DISCOPARTY_TEST_NEW_LAUNCH_STATE"
        ;;
      *) exit 2 ;;
    esac
    ;;
  kickstart) ;;
  *) exit 2 ;;
esac
EOF
chmod 700 "$LEGACY_FAKE_LAUNCHCTL"

LEGACY_DRIVER_COMMON="$LEGACY_TEST_ROOT/driver-common.sh"
cat > "$LEGACY_DRIVER_COMMON" <<'EOF'
eval "$(declare -f write_legacy_handoff_state | sed '1s/write_legacy_handoff_state/production_write_legacy_handoff_state/')"
eval "$(declare -f capture_legacy_process_tree | sed '1s/capture_legacy_process_tree/production_capture_legacy_process_tree/')"
eval "$(declare -f verify_legacy_descendants_stopped | sed '1s/verify_legacy_descendants_stopped/production_verify_legacy_descendants_stopped/')"

SCRATCH=0
NON_INTERACTIVE=1
REINSTALL=0
START_MONITOR=0

check_no_api_key() { :; }
check_prerequisites() { :; }
resolve_settings() {
  PYTHON_BIN="$DISCOPARTY_TEST_REAL_PYTHON"
  SECURITY_BIN="$DISCOPARTY_TEST_SECURITY_BIN"
  LAUNCHCTL_BIN="$DISCOPARTY_TEST_LAUNCHCTL_BIN"
  REPO_ROOT="$DISCOPARTY_TEST_REPO"
  CONFIG_PATH="$DISCOPARTY_TEST_LEGACY_HOME/discoparty-config.toml"
  PLIST_PATH="$DISCOPARTY_TEST_LEGACY_HOME/Library/LaunchAgents/com.discoparty.codex-discord-bridge.plist"
  STATE_DIR="$DISCOPARTY_TEST_NEW_STATE"
  LOG_DIR="$DISCOPARTY_TEST_REPO/logs"
  WORKER_HOME="$STATE_DIR/home"
  CODEX_HOME_DIR="$WORKER_HOME/.codex"
  SHARED_SKILLS_ROOT="$DISCOPARTY_TEST_SHARED_SKILLS_ROOT"
  DISCOPARTY_CODEX_GUILD_ID=100000000000000001
  DISCOPARTY_CODEX_CHANNEL_ID=100000000000000002
  DISCOPARTY_CODEX_OWNER_USER_ID=100000000000000003
  DISCOPARTY_CODEX_BOT_USER_ID=100000000000000004
  DISCOPARTY_CODEX_APPLICATION_ID=100000000000000005
  DISCOPARTY_CODEX_WORKING_DIRECTORY="$DISCOPARTY_TEST_WORK_DIR"
  DISCOPARTY_CODEX_SANDBOX_MODE=danger-full-access
  TOPOLOGY_VALIDATED=1
}
legacy_stage() {
  printf '%s\n' "$1" >> "$DISCOPARTY_TEST_INSTALL_ORDER_LOG"
}
prepare_log_directory() {
  legacy_stage stage-log-directory
  mkdir -p "$STATE_DIR"
  chmod 700 "$STATE_DIR"
}
prepare_isolated_codex() {
  legacy_stage stage-isolated-auth
  mkdir -p "$CODEX_HOME_DIR"
  chmod 700 "$WORKER_HOME" "$CODEX_HOME_DIR"
}
prepare_shared_skill_bridge() { legacy_stage stage-shared-skills; }
prepare_vault_policy_seal() { legacy_stage stage-vault-policy; }
prepare_python_runtime() { legacy_stage stage-runtime; }
verify_reviewed_codex_package() { legacy_stage stage-cli-preflight; }
ensure_isolated_chatgpt_login() { legacy_stage stage-subscription-login; }
update_codex_config() { legacy_stage stage-config; }
run_preflight() { legacy_stage stage-provider-preflight; }
render_plist() { legacy_stage stage-render-plist; }
capture_legacy_process_tree() { LEGACY_PROCESS_PIDS=""; }
verify_legacy_descendants_stopped() {
  LEGACY_DESCENDANTS_DRAINED=1
  return 0
}
current_policy_binding() { printf '%s\n' "$DISCOPARTY_TEST_POLICY_BINDING"; }
write_legacy_handoff_state() {
  printf '%s\n' "$1" >> "$DISCOPARTY_TEST_STATE_TRANSITIONS"
  production_write_legacy_handoff_state "$@"
}
bootstrap_agent() {
  [ "$(cat "$DISCOPARTY_TEST_LEGACY_LAUNCH_STATE")" = "unloaded" ]
  [ -e "$DISCOPARTY_TEST_LEGACY_DISABLED_STATE" ]
  legacy_stage replacement-bootstrap
}
start_monitor() { :; }
EOF

LEGACY_COMMON_ENV=(
  "HOME=$LEGACY_TEST_HOME"
  "DISCOPARTY_TEST_SOURCEABLE_INSTALLER=$SOURCEABLE_INSTALLER"
  "DISCOPARTY_TEST_DRIVER_COMMON=$LEGACY_DRIVER_COMMON"
  "DISCOPARTY_TEST_REAL_PYTHON=$REAL_PYTHON"
  "DISCOPARTY_TEST_SECURITY_BIN=$FAKE_BIN/security"
  "DISCOPARTY_TEST_LAUNCHCTL_BIN=$LEGACY_FAKE_LAUNCHCTL"
  "DISCOPARTY_TEST_SECRET_PROBE=$FAKE_BIN/assert-no-secret"
  "DISCOPARTY_TEST_SECRET_PROBE_LOG=$SECRET_PROBE_LOG"
  "DISCOPARTY_TEST_REPO=$TEST_REPO"
  "DISCOPARTY_TEST_LEGACY_HOME=$LEGACY_TEST_HOME"
  "DISCOPARTY_TEST_NEW_STATE=$LEGACY_NEW_STATE"
  "DISCOPARTY_TEST_WORK_DIR=$WORK_DIR"
  "DISCOPARTY_TEST_SHARED_SKILLS_ROOT=$TEST_ROOT/claude-workspace/x_System/Skills"
  "DISCOPARTY_TEST_INSTALL_ORDER_LOG=$LEGACY_ORDER"
  "DISCOPARTY_TEST_STATE_TRANSITIONS=$LEGACY_STATE_TRANSITIONS"
  "DISCOPARTY_TEST_LEGACY_LAUNCH_STATE=$LEGACY_LAUNCH_STATE"
  "DISCOPARTY_TEST_NEW_LAUNCH_STATE=$LEGACY_NEW_LAUNCH_STATE"
  "DISCOPARTY_TEST_LEGACY_DISABLED_STATE=$LEGACY_DISABLED_STATE"
  "DISCOPARTY_TEST_POLICY_BINDING=$LEGACY_POLICY_BINDING"
)

# A legacy footprint blocks an ordinary installation before any staged
# mutation, even when the replacement label is absent.
create_legacy_fixture public completed
cat > "$LEGACY_TEST_ROOT/dual-run-driver.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$DISCOPARTY_TEST_SOURCEABLE_INSTALLER"
source "$DISCOPARTY_TEST_DRIVER_COMMON"
TAKE_OVER_LEGACY=0
IMPORT_LEGACY_TOKEN=0
prepare_log_directory() {
  : > "$DISCOPARTY_TEST_MUTATION_MARKER"
  return 97
}
main
EOF
chmod 700 "$LEGACY_TEST_ROOT/dual-run-driver.sh"
if env "${LEGACY_COMMON_ENV[@]}" \
  "DISCOPARTY_TEST_MUTATION_MARKER=$LEGACY_MUTATION_MARKER" \
  "$LEGACY_TEST_ROOT/dual-run-driver.sh" \
  >"$TEST_ROOT/legacy-dual-run.log" 2>&1; then
  echo "ordinary install accepted a legacy Codex provider" >&2
  exit 1
fi
grep -Fq "Refusing a dual-run" "$TEST_ROOT/legacy-dual-run.log"
test ! -e "$LEGACY_MUTATION_MARKER"
test ! -e "$LEGACY_NEW_STATE"
[ "$(cat "$LEGACY_LAUNCH_STATE")" = "loaded" ]

# Takeover validates every exact legacy plist field. This fixture deliberately
# disagrees with the requested public channel trust and must be rejected.
create_legacy_fixture owner_private completed
cat > "$LEGACY_TEST_ROOT/invalid-plist-driver.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$DISCOPARTY_TEST_SOURCEABLE_INSTALLER"
source "$DISCOPARTY_TEST_DRIVER_COMMON"
TAKE_OVER_LEGACY=1
IMPORT_LEGACY_TOKEN=0
main
EOF
chmod 700 "$LEGACY_TEST_ROOT/invalid-plist-driver.sh"
if env "${LEGACY_COMMON_ENV[@]}" \
  "$LEGACY_TEST_ROOT/invalid-plist-driver.sh" \
  >"$TEST_ROOT/legacy-invalid-plist.log" 2>&1; then
  echo "takeover accepted an unexpected legacy channel-trust policy" >&2
  exit 1
fi
grep -Fq "environment does not match the reviewed channel-trust deployment" \
  "$TEST_ROOT/legacy-invalid-plist.log"
[ "$(cat "$LEGACY_LAUNCH_STATE")" = "loaded" ]
test ! -e "$LEGACY_NEW_STATE"

# A successful scratch validation removes its rendered replacement plist. The
# next real takeover therefore sees one installed provider, not an ambiguous
# legacy-plus-staged pair.
create_legacy_fixture public completed
cat > "$LEGACY_TEST_ROOT/scratch-driver.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$DISCOPARTY_TEST_SOURCEABLE_INSTALLER"
source "$DISCOPARTY_TEST_DRIVER_COMMON"
SCRATCH=1
TAKE_OVER_LEGACY=1
IMPORT_LEGACY_TOKEN=1
render_plist() {
  legacy_stage stage-render-plist
  printf '%s\n' validated-scratch-plist > "$PLIST_PATH"
  chmod 600 "$PLIST_PATH"
  PLIST_EXISTED=0
  PLIST_MUTATED=1
}
bootstrap_agent() {
  [ ! -e "$PLIST_PATH" ]
  legacy_stage scratch-bootstrap-skipped
}
main
EOF
chmod 700 "$LEGACY_TEST_ROOT/scratch-driver.sh"
env "${LEGACY_COMMON_ENV[@]}" \
  "$LEGACY_TEST_ROOT/scratch-driver.sh" \
  >"$TEST_ROOT/legacy-scratch.log"
grep -Fq "rendered replacement plist was removed" "$TEST_ROOT/legacy-scratch.log"
test ! -e "$LEGACY_TEST_HOME/Library/LaunchAgents/com.discoparty.codex-discord-bridge.plist"
[ "$(cat "$LEGACY_LAUNCH_STATE")" = "loaded" ]
test ! -e "$LEGACY_DISABLED_STATE"

# The complete fake takeover proves late quiesce, direct Keychain-to-Keychain
# import, private backup, ordered state transitions, and policy-scoped cursor
# reconciliation before replacement bootstrap.
create_legacy_fixture public completed
cat > "$LEGACY_TEST_ROOT/success-driver.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$DISCOPARTY_TEST_SOURCEABLE_INSTALLER"
source "$DISCOPARTY_TEST_DRIVER_COMMON"
TAKE_OVER_LEGACY=1
IMPORT_LEGACY_TOKEN=1
main
EOF
chmod 700 "$LEGACY_TEST_ROOT/success-driver.sh"
env "${LEGACY_COMMON_ENV[@]}" \
  DISCOPARTY_CODEX_LEGACY_MAINTENANCE_ACCEPTED=LEGACY_MAINTENANCE_ACCEPTED \
  "$LEGACY_TEST_ROOT/success-driver.sh" \
  >"$TEST_ROOT/legacy-success.log"

render_line="$(grep -n -m 1 '^stage-render-plist$' "$LEGACY_ORDER" | cut -d: -f1)"
legacy_bootout_line="$(grep -n -m 1 '^launchctl bootout .*/com.thesystem.codex-discord-bridge$' "$LEGACY_ORDER" | cut -d: -f1)"
replacement_bootstrap_line="$(grep -n -m 1 '^replacement-bootstrap$' "$LEGACY_ORDER" | cut -d: -f1)"
[ "$render_line" -lt "$legacy_bootout_line" ]
[ "$legacy_bootout_line" -lt "$replacement_bootstrap_line" ]
cat > "$LEGACY_TEST_ROOT/expected-states" <<'EOF'
maintenance_accepted
legacy_quiesced
backup_complete
cursor_reconciled
new_ready
EOF
cmp "$LEGACY_TEST_ROOT/expected-states" "$LEGACY_STATE_TRANSITIONS"
[ "$(cat "$LEGACY_LAUNCH_STATE")" = "unloaded" ]
test -e "$LEGACY_DISABLED_STATE"
[ "$(cat "$LEGACY_TEST_HOME/.fake-keychain-discord-bot-token-codex")" = \
  "codex-test-token-without-spaces-123" ]
[ "$(cat "$LEGACY_TEST_HOME/.fake-keychain-thesystem-discord-bot-token-admin")" = \
  "codex-test-token-without-spaces-123" ]
"$REAL_PYTHON" - \
  "$LEGACY_NEW_STATE" "$LEGACY_POLICY_BINDING" "$LEGACY_ROOT_CURSOR" <<'PY'
import json
import os
import sqlite3
import stat
import sys
from pathlib import Path

state = Path(sys.argv[1])
binding, cursor = sys.argv[2:]
marker = state / "legacy-takeover.json"
payload = json.loads(marker.read_text())
assert payload["state"] == "new_ready"
assert payload["root_cursor"] == cursor
backup = Path(payload["backup_dir"])
assert backup.parent == state / "migration-backups"
for path in (marker, backup / "jobs.sqlite3", backup / "manifest.json", backup / "com.thesystem.codex-discord-bridge.plist"):
    metadata = path.lstat()
    assert stat.S_ISREG(metadata.st_mode)
    assert stat.S_IMODE(metadata.st_mode) == 0o600
    assert metadata.st_nlink == 1
with sqlite3.connect(f"file:{state / 'jobs.sqlite3'}?mode=ro", uri=True) as db:
    row = db.execute(
        "SELECT event_id FROM channel_cursors WHERE channel_id=?",
        (f"policy:{binding}:100000000000000002",),
    ).fetchone()
    assert row == (cursor,)
    assert db.execute("SELECT COUNT(*) FROM jobs").fetchone() == (0,)
PY
! grep -Fq 'codex-test-token-without-spaces-123' \
  "$TEST_ROOT/legacy-success.log" "$LEGACY_ORDER" "$LEGACY_STATE_TRANSITIONS" \
  "$LEGACY_NEW_STATE/legacy-takeover.json"

# Keeping the old disabled plist for rollback must not permanently block later
# Disco Party reinstalls. Acceptance requires the exact old service, an unloaded
# and disabled old label, and a matching new_ready marker plus backup hashes.
printf '%s\n' retained-discoparty-plist \
  > "$LEGACY_TEST_HOME/Library/LaunchAgents/com.discoparty.codex-discord-bridge.plist"
chmod 600 "$LEGACY_TEST_HOME/Library/LaunchAgents/com.discoparty.codex-discord-bridge.plist"
cat > "$LEGACY_TEST_ROOT/archived-reinstall-driver.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$DISCOPARTY_TEST_SOURCEABLE_INSTALLER"
source "$DISCOPARTY_TEST_DRIVER_COMMON"
REINSTALL=1
TAKE_OVER_LEGACY=0
IMPORT_LEGACY_TOKEN=0
main
EOF
chmod 700 "$LEGACY_TEST_ROOT/archived-reinstall-driver.sh"
env "${LEGACY_COMMON_ENV[@]}" \
  "$LEGACY_TEST_ROOT/archived-reinstall-driver.sh" \
  >"$TEST_ROOT/legacy-archived-reinstall.log"
grep -Fq "disabled, integrity-checked rollback artifact" \
  "$TEST_ROOT/legacy-archived-reinstall.log"
[ "$(cat "$LEGACY_LAUNCH_STATE")" = "unloaded" ]
test -e "$LEGACY_DISABLED_STATE"
rm -f "$LEGACY_TEST_HOME/Library/LaunchAgents/com.discoparty.codex-discord-bridge.plist"
env "${LEGACY_COMMON_ENV[@]}" \
  "$LEGACY_TEST_ROOT/archived-reinstall-driver.sh" \
  >"$TEST_ROOT/legacy-archived-after-uninstall.log"
grep -Fq "disabled, integrity-checked rollback artifact" \
  "$TEST_ROOT/legacy-archived-after-uninstall.log"

# If the durable cursor or marker no longer matches, bootstrap is forbidden.
# Rollback removes only the still-empty replacement ledger, restores the prior
# Disco Party Keychain snapshot, and restarts the exact old label.
create_legacy_fixture public completed
printf '%s' prior-discoparty-token \
  > "$LEGACY_TEST_HOME/.fake-keychain-discord-bot-token-codex"
chmod 600 "$LEGACY_TEST_HOME/.fake-keychain-discord-bot-token-codex"
cat > "$LEGACY_TEST_ROOT/cursor-mismatch-driver.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$DISCOPARTY_TEST_SOURCEABLE_INSTALLER"
source "$DISCOPARTY_TEST_DRIVER_COMMON"
eval "$(declare -f reconcile_legacy_root_cursor | sed '1s/reconcile_legacy_root_cursor/production_reconcile_legacy_root_cursor/')"
TAKE_OVER_LEGACY=1
IMPORT_LEGACY_TOKEN=1
reconcile_legacy_root_cursor() {
  production_reconcile_legacy_root_cursor
  "$PYTHON_BIN" - "$STATE_DIR/jobs.sqlite3" "$DISCOPARTY_CODEX_CHANNEL_ID" "$DISCOPARTY_TEST_POLICY_BINDING" <<'PY'
import sqlite3
import sys
database, channel, binding = sys.argv[1:]
with sqlite3.connect(database) as db:
    db.execute(
        "UPDATE channel_cursors SET event_id='1' WHERE channel_id=?",
        (f"policy:{binding}:{channel}",),
    )
PY
}
main
EOF
chmod 700 "$LEGACY_TEST_ROOT/cursor-mismatch-driver.sh"
if env "${LEGACY_COMMON_ENV[@]}" \
  DISCOPARTY_CODEX_LEGACY_MAINTENANCE_ACCEPTED=LEGACY_MAINTENANCE_ACCEPTED \
  "$LEGACY_TEST_ROOT/cursor-mismatch-driver.sh" \
  >"$TEST_ROOT/legacy-cursor-mismatch.log" 2>&1; then
  echo "replacement bootstrapped with a mismatched legacy cursor" >&2
  exit 1
fi
grep -Fq "replacement bootstrap is forbidden" "$TEST_ROOT/legacy-cursor-mismatch.log"
[ "$(cat "$LEGACY_TEST_HOME/.fake-keychain-discord-bot-token-codex")" = \
  "prior-discoparty-token" ]
[ "$(cat "$LEGACY_LAUNCH_STATE")" = "loaded" ]
test ! -e "$LEGACY_DISABLED_STATE"
test ! -e "$LEGACY_NEW_STATE/jobs.sqlite3"
"$REAL_PYTHON" -c \
  'import json,sys; assert json.load(open(sys.argv[1]))["state"] == "rolled_back"' \
  "$LEGACY_NEW_STATE/legacy-takeover.json"

# A stopped old process is not enough. Unfinished or ambiguous legacy work
# blocks cursor handoff, then rollback returns the old service to its prior
# loaded and enabled state without leaving the imported token behind.
create_legacy_fixture public uncertain
cat > "$LEGACY_TEST_ROOT/nonquiescent-driver.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$DISCOPARTY_TEST_SOURCEABLE_INSTALLER"
source "$DISCOPARTY_TEST_DRIVER_COMMON"
TAKE_OVER_LEGACY=1
IMPORT_LEGACY_TOKEN=1
main
EOF
chmod 700 "$LEGACY_TEST_ROOT/nonquiescent-driver.sh"
if env "${LEGACY_COMMON_ENV[@]}" \
  DISCOPARTY_CODEX_LEGACY_MAINTENANCE_ACCEPTED=LEGACY_MAINTENANCE_ACCEPTED \
  "$LEGACY_TEST_ROOT/nonquiescent-driver.sh" \
  >"$TEST_ROOT/legacy-nonquiescent.log" 2>&1; then
  echo "takeover accepted unfinished legacy jobs or deliveries" >&2
  exit 1
fi
grep -Fq "legacy ledger is not quiescent" "$TEST_ROOT/legacy-nonquiescent.log"
[ "$(cat "$LEGACY_LAUNCH_STATE")" = "loaded" ]
test ! -e "$LEGACY_DISABLED_STATE"
test ! -e "$LEGACY_TEST_HOME/.fake-keychain-discord-bot-token-codex"
test ! -e "$LEGACY_NEW_STATE/jobs.sqlite3"

# A captured App Server descendant that survives launchd bootout blocks the
# backup and cursor phases. Rollback also refuses to start another old parent
# while that descendant could still be acting with the legacy authority.
create_legacy_fixture public completed
/bin/sleep 60 &
LEGACY_SURVIVOR_PID=$!
cat > "$LEGACY_TEST_ROOT/descendant-driver.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$DISCOPARTY_TEST_SOURCEABLE_INSTALLER"
source "$DISCOPARTY_TEST_DRIVER_COMMON"
TAKE_OVER_LEGACY=1
IMPORT_LEGACY_TOKEN=1
capture_legacy_process_tree() { production_capture_legacy_process_tree; }
verify_legacy_descendants_stopped() { production_verify_legacy_descendants_stopped; }
sleep() { :; }
main
EOF
chmod 700 "$LEGACY_TEST_ROOT/descendant-driver.sh"
if env "${LEGACY_COMMON_ENV[@]}" \
  "DISCOPARTY_TEST_LEGACY_PID=$LEGACY_SURVIVOR_PID" \
  DISCOPARTY_CODEX_LEGACY_MAINTENANCE_ACCEPTED=LEGACY_MAINTENANCE_ACCEPTED \
  "$LEGACY_TEST_ROOT/descendant-driver.sh" \
  >"$TEST_ROOT/legacy-descendant.log" 2>&1; then
  kill "$LEGACY_SURVIVOR_PID" >/dev/null 2>&1 || true
  wait "$LEGACY_SURVIVOR_PID" 2>/dev/null || true
  echo "takeover accepted a surviving legacy descendant" >&2
  exit 1
fi
kill "$LEGACY_SURVIVOR_PID" >/dev/null 2>&1 || true
wait "$LEGACY_SURVIVOR_PID" 2>/dev/null || true
grep -Fq "descendant survived quiesce" "$TEST_ROOT/legacy-descendant.log"
grep -Fq "was not restarted" "$TEST_ROOT/legacy-descendant.log"
[ "$(cat "$LEGACY_LAUNCH_STATE")" = "unloaded" ]
test ! -e "$LEGACY_NEW_STATE/jobs.sqlite3"
"$REAL_PYTHON" -c \
  'import json,sys; assert json.load(open(sys.argv[1]))["state"] == "rollback_blocked"' \
  "$LEGACY_NEW_STATE/legacy-takeover.json"

RACE_ROOT="$TEST_ROOT/reinstall-race"
RACE_STATE="$RACE_ROOT/launchctl.state"
RACE_ORDER="$RACE_ROOT/order.log"
RACE_PLIST="$RACE_ROOT/prior.plist"
RACE_CONFIG="$RACE_ROOT/config.toml"
RACE_CODEX_HOME="$RACE_ROOT/codex-home"
RACE_KEYCHAIN="$TEST_HOME/.fake-keychain-discord-bot-token-codex"
mkdir -p "$RACE_CODEX_HOME"
chmod 700 "$RACE_CODEX_HOME"
printf '%s\n' loaded > "$RACE_STATE"
printf '%s\n' prior-plist > "$RACE_PLIST"
printf '%s\n' prior-config > "$RACE_CONFIG"
printf '%s\n' prior-codex-policy > "$RACE_CODEX_HOME/config.toml"

RACE_MUTATION_MARKER="$RACE_ROOT/unexpected-mutation"
cat > "$RACE_ROOT/bootout-failure-driver.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$DISCOPARTY_TEST_SOURCEABLE_INSTALLER"

SCRATCH=0
REINSTALL=1
START_MONITOR=0
LAUNCHCTL_BIN="$DISCOPARTY_TEST_LAUNCHCTL_BIN"

check_no_api_key() { :; }
check_prerequisites() { :; }
detect_and_validate_legacy() { :; }
resolve_settings() {
  PYTHON_BIN="$DISCOPARTY_TEST_REAL_PYTHON"
  REPO_ROOT="$DISCOPARTY_TEST_REPO"
  CONFIG_PATH="$DISCOPARTY_TEST_RACE_CONFIG"
  PLIST_PATH="$DISCOPARTY_TEST_RACE_PLIST"
  STATE_DIR="$DISCOPARTY_TEST_RACE_ROOT/state"
  LOG_DIR="$DISCOPARTY_TEST_RACE_ROOT/logs"
  WORKER_HOME="$STATE_DIR/home"
  CODEX_HOME_DIR="$DISCOPARTY_TEST_RACE_CODEX_HOME"
  SHARED_SKILLS_ROOT="$DISCOPARTY_TEST_SHARED_SKILLS_ROOT"
  DISCOPARTY_CODEX_WORKING_DIRECTORY="$DISCOPARTY_TEST_WORK_DIR"
  DISCOPARTY_CODEX_SANDBOX_MODE="workspace-write"
  TOPOLOGY_VALIDATED=1
}
unexpected_mutation() {
  : > "$DISCOPARTY_TEST_RACE_MUTATION_MARKER"
  return 97
}
prepare_log_directory() { unexpected_mutation; }
prepare_isolated_codex() { unexpected_mutation; }
prepare_shared_skill_bridge() { unexpected_mutation; }
prepare_vault_policy_seal() { unexpected_mutation; }
prepare_python_runtime() { unexpected_mutation; }
verify_reviewed_codex_package() { unexpected_mutation; }
ensure_isolated_chatgpt_login() { unexpected_mutation; }
resolve_bot_token() { unexpected_mutation; }
store_bot_token() { unexpected_mutation; }
update_codex_config() { unexpected_mutation; }
run_preflight() { unexpected_mutation; }
render_plist() { unexpected_mutation; }
bootstrap_agent() { unexpected_mutation; }
start_monitor() { unexpected_mutation; }

main
EOF
chmod 700 "$RACE_ROOT/bootout-failure-driver.sh"

if env \
  "HOME=$TEST_HOME" \
  "DISCOPARTY_TEST_SOURCEABLE_INSTALLER=$SOURCEABLE_INSTALLER" \
  "DISCOPARTY_TEST_REPO=$TEST_REPO" \
  "DISCOPARTY_TEST_REAL_PYTHON=$REAL_PYTHON" \
  "DISCOPARTY_TEST_RACE_ROOT=$RACE_ROOT" \
  "DISCOPARTY_TEST_RACE_CONFIG=$RACE_CONFIG" \
  "DISCOPARTY_TEST_RACE_PLIST=$RACE_PLIST" \
  "DISCOPARTY_TEST_RACE_CODEX_HOME=$RACE_CODEX_HOME" \
  "DISCOPARTY_TEST_RACE_MUTATION_MARKER=$RACE_MUTATION_MARKER" \
  "DISCOPARTY_TEST_WORK_DIR=$WORK_DIR" \
  "DISCOPARTY_TEST_SHARED_SKILLS_ROOT=$TEST_ROOT/claude-workspace/x_System/Skills" \
  "DISCOPARTY_TEST_LAUNCHCTL_BIN=$FAKE_BIN/launchctl" \
  "DISCOPARTY_TEST_LAUNCHCTL_LOG=$LAUNCHCTL_LOG" \
  "DISCOPARTY_TEST_LAUNCHCTL_SCENARIO=loaded-bootout-fails" \
  "DISCOPARTY_TEST_SECRET_PROBE=$FAKE_BIN/assert-no-secret" \
  "DISCOPARTY_TEST_SECRET_PROBE_LOG=$SECRET_PROBE_LOG" \
  "$RACE_ROOT/bootout-failure-driver.sh" \
  >"$TEST_ROOT/reinstall-bootout-failure.log" 2>&1; then
  echo "installer continued after existing Codex agent bootout failed" >&2
  exit 1
fi
grep -Fq "no Codex state was changed" "$TEST_ROOT/reinstall-bootout-failure.log"
test ! -e "$RACE_MUTATION_MARKER"

cat > "$RACE_ROOT/success-driver.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$DISCOPARTY_TEST_SOURCEABLE_INSTALLER"

SCRATCH=0
REINSTALL=1
START_MONITOR=0
LAUNCHCTL_BIN="$DISCOPARTY_TEST_LAUNCHCTL_BIN"

check_no_api_key() { :; }
check_prerequisites() { :; }
detect_and_validate_legacy() { :; }
resolve_settings() {
  PYTHON_BIN="$DISCOPARTY_TEST_REAL_PYTHON"
  REPO_ROOT="$DISCOPARTY_TEST_REPO"
  CONFIG_PATH="$DISCOPARTY_TEST_RACE_CONFIG"
  PLIST_PATH="$DISCOPARTY_TEST_RACE_PLIST"
  STATE_DIR="$DISCOPARTY_TEST_RACE_ROOT/state"
  LOG_DIR="$DISCOPARTY_TEST_RACE_ROOT/logs"
  WORKER_HOME="$STATE_DIR/home"
  CODEX_HOME_DIR="$DISCOPARTY_TEST_RACE_CODEX_HOME"
  SHARED_SKILLS_ROOT="$DISCOPARTY_TEST_SHARED_SKILLS_ROOT"
  DISCOPARTY_CODEX_WORKING_DIRECTORY="$DISCOPARTY_TEST_WORK_DIR"
  DISCOPARTY_CODEX_SANDBOX_MODE="workspace-write"
  TOPOLOGY_VALIDATED=1
}
require_stopped() {
  [ "$(cat "$DISCOPARTY_TEST_LAUNCHCTL_STATE")" = "unloaded" ]
}
prepare_log_directory() {
  require_stopped
  printf '%s\n' mutation-log-directory >> "$DISCOPARTY_TEST_INSTALL_ORDER_LOG"
}
prepare_isolated_codex() {
  require_stopped
  printf '%s\n' mutation-codex-home >> "$DISCOPARTY_TEST_INSTALL_ORDER_LOG"
}
prepare_shared_skill_bridge() {
  require_stopped
  printf '%s\n' mutation-shared-skills >> "$DISCOPARTY_TEST_INSTALL_ORDER_LOG"
}
prepare_vault_policy_seal() {
  require_stopped
  printf '%s\n' mutation-vault-policy >> "$DISCOPARTY_TEST_INSTALL_ORDER_LOG"
}
prepare_python_runtime() { require_stopped; }
verify_reviewed_codex_package() {
  require_stopped
  printf '%s\n' appserver-schema-preflight >> "$DISCOPARTY_TEST_INSTALL_ORDER_LOG"
}
ensure_isolated_chatgpt_login() { require_stopped; }
resolve_bot_token() { require_stopped; }
store_bot_token() {
  require_stopped
  printf '%s\n' mutation-keychain >> "$DISCOPARTY_TEST_INSTALL_ORDER_LOG"
}
update_codex_config() {
  require_stopped
  printf '%s\n' mutation-discoparty-config >> "$DISCOPARTY_TEST_INSTALL_ORDER_LOG"
}
run_preflight() {
  require_stopped
  printf '%s\n' provider-preflight >> "$DISCOPARTY_TEST_INSTALL_ORDER_LOG"
}
render_plist() { require_stopped; }
bootstrap_agent() {
  require_stopped
  "$LAUNCHCTL_BIN" bootstrap "gui/$UID" "$PLIST_PATH"
}
start_monitor() { :; }

main
EOF
chmod 700 "$RACE_ROOT/success-driver.sh"

env \
  "HOME=$TEST_HOME" \
  "DISCOPARTY_TEST_SOURCEABLE_INSTALLER=$SOURCEABLE_INSTALLER" \
  "DISCOPARTY_TEST_REPO=$TEST_REPO" \
  "DISCOPARTY_TEST_REAL_PYTHON=$REAL_PYTHON" \
  "DISCOPARTY_TEST_RACE_ROOT=$RACE_ROOT" \
  "DISCOPARTY_TEST_RACE_CONFIG=$RACE_CONFIG" \
  "DISCOPARTY_TEST_RACE_PLIST=$RACE_PLIST" \
  "DISCOPARTY_TEST_RACE_CODEX_HOME=$RACE_CODEX_HOME" \
  "DISCOPARTY_TEST_WORK_DIR=$WORK_DIR" \
  "DISCOPARTY_TEST_SHARED_SKILLS_ROOT=$TEST_ROOT/claude-workspace/x_System/Skills" \
  "DISCOPARTY_TEST_LAUNCHCTL_BIN=$FAKE_BIN/launchctl" \
  "DISCOPARTY_TEST_LAUNCHCTL_LOG=$LAUNCHCTL_LOG" \
  "DISCOPARTY_TEST_LAUNCHCTL_SCENARIO=stateful" \
  "DISCOPARTY_TEST_LAUNCHCTL_STATE=$RACE_STATE" \
  "DISCOPARTY_TEST_INSTALL_ORDER_LOG=$RACE_ORDER" \
  "DISCOPARTY_TEST_SECRET_PROBE=$FAKE_BIN/assert-no-secret" \
  "DISCOPARTY_TEST_SECRET_PROBE_LOG=$SECRET_PROBE_LOG" \
  "$RACE_ROOT/success-driver.sh" >"$TEST_ROOT/reinstall-order.log"

bootout_line="$(grep -n -m 1 '^launchctl bootout ' "$RACE_ORDER" | cut -d: -f1)"
codex_mutation_line="$(grep -n -m 1 '^mutation-codex-home$' "$RACE_ORDER" | cut -d: -f1)"
schema_line="$(grep -n -m 1 '^appserver-schema-preflight$' "$RACE_ORDER" | cut -d: -f1)"
provider_line="$(grep -n -m 1 '^provider-preflight$' "$RACE_ORDER" | cut -d: -f1)"
bootstrap_line="$(grep -n -m 1 '^launchctl bootstrap ' "$RACE_ORDER" | cut -d: -f1)"
[ "$bootout_line" -lt "$codex_mutation_line" ]
[ "$bootout_line" -lt "$schema_line" ]
[ "$bootout_line" -lt "$provider_line" ]
[ "$provider_line" -lt "$bootstrap_line" ]
[ "$(cat "$RACE_STATE")" = "loaded" ]

# A failure after shared inputs change must restore them all before launchd is
# allowed to reload the old plist.
printf '%s\n' loaded > "$RACE_STATE"
: > "$RACE_ORDER"
printf '%s\n' prior-plist > "$RACE_PLIST"
printf '%s\n' prior-config > "$RACE_CONFIG"
printf '%s\n' prior-codex-policy > "$RACE_CODEX_HOME/config.toml"
printf '%s\n' prior-token > "$RACE_KEYCHAIN"

cat > "$RACE_ROOT/rollback-driver.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$DISCOPARTY_TEST_SOURCEABLE_INSTALLER"

SCRATCH=0
REINSTALL=1
START_MONITOR=0
LAUNCHCTL_BIN="$DISCOPARTY_TEST_LAUNCHCTL_BIN"
SECURITY_BIN="$DISCOPARTY_TEST_SECURITY_BIN"

check_no_api_key() { :; }
check_prerequisites() { :; }
detect_and_validate_legacy() { :; }
resolve_settings() {
  PYTHON_BIN="$DISCOPARTY_TEST_REAL_PYTHON"
  REPO_ROOT="$DISCOPARTY_TEST_REPO"
  CONFIG_PATH="$DISCOPARTY_TEST_RACE_CONFIG"
  PLIST_PATH="$DISCOPARTY_TEST_RACE_PLIST"
  STATE_DIR="$DISCOPARTY_TEST_RACE_ROOT/state"
  LOG_DIR="$DISCOPARTY_TEST_RACE_ROOT/logs"
  WORKER_HOME="$STATE_DIR/home"
  CODEX_HOME_DIR="$DISCOPARTY_TEST_RACE_CODEX_HOME"
  SHARED_SKILLS_ROOT="$DISCOPARTY_TEST_SHARED_SKILLS_ROOT"
  DISCOPARTY_CODEX_WORKING_DIRECTORY="$DISCOPARTY_TEST_WORK_DIR"
  DISCOPARTY_CODEX_SANDBOX_MODE="workspace-write"
  TOPOLOGY_VALIDATED=1
}
prepare_log_directory() { :; }
prepare_isolated_codex() {
  CODEX_CONFIG_EXISTED=1
  CODEX_CONFIG_BACKUP="$(mktemp "$DISCOPARTY_TEST_RACE_ROOT/codex-config-backup.XXXXXX")"
  cp -p "$CODEX_HOME_DIR/config.toml" "$CODEX_CONFIG_BACKUP"
  CODEX_CONFIG_MUTATED=1
  printf '%s\n' failed-new-codex-policy > "$CODEX_HOME_DIR/config.toml"
}
prepare_shared_skill_bridge() { :; }
prepare_vault_policy_seal() { :; }
prepare_python_runtime() { :; }
verify_reviewed_codex_package() { :; }
ensure_isolated_chatgpt_login() { :; }
resolve_bot_token() { :; }
store_bot_token() {
  OLD_KEYCHAIN_PRESENT=1
  OLD_KEYCHAIN_TOKEN="prior-token"
  KEYCHAIN_MUTATED=1
  printf '%s\n' failed-new-token > "$HOME/.fake-keychain-discord-bot-token-codex"
}
update_codex_config() {
  CONFIG_EXISTED=1
  CONFIG_BACKUP="$(mktemp "$DISCOPARTY_TEST_RACE_ROOT/config-backup.XXXXXX")"
  cp -p "$CONFIG_PATH" "$CONFIG_BACKUP"
  CONFIG_MUTATED=1
  printf '%s\n' failed-new-config > "$CONFIG_PATH"
}
run_preflight() {
  printf '%s\n' provider-preflight-failed >> "$DISCOPARTY_TEST_INSTALL_ORDER_LOG"
  return 79
}
render_plist() { return 90; }
bootstrap_agent() { return 91; }
start_monitor() { return 92; }

main
EOF
chmod 700 "$RACE_ROOT/rollback-driver.sh"

if env \
  "HOME=$TEST_HOME" \
  "DISCOPARTY_TEST_SOURCEABLE_INSTALLER=$SOURCEABLE_INSTALLER" \
  "DISCOPARTY_TEST_REPO=$TEST_REPO" \
  "DISCOPARTY_TEST_REAL_PYTHON=$REAL_PYTHON" \
  "DISCOPARTY_TEST_RACE_ROOT=$RACE_ROOT" \
  "DISCOPARTY_TEST_RACE_CONFIG=$RACE_CONFIG" \
  "DISCOPARTY_TEST_RACE_PLIST=$RACE_PLIST" \
  "DISCOPARTY_TEST_RACE_CODEX_HOME=$RACE_CODEX_HOME" \
  "DISCOPARTY_TEST_WORK_DIR=$WORK_DIR" \
  "DISCOPARTY_TEST_SHARED_SKILLS_ROOT=$TEST_ROOT/claude-workspace/x_System/Skills" \
  "DISCOPARTY_TEST_LAUNCHCTL_BIN=$FAKE_BIN/launchctl" \
  "DISCOPARTY_TEST_SECURITY_BIN=$FAKE_BIN/security" \
  "DISCOPARTY_TEST_LAUNCHCTL_LOG=$LAUNCHCTL_LOG" \
  "DISCOPARTY_TEST_LAUNCHCTL_SCENARIO=stateful" \
  "DISCOPARTY_TEST_LAUNCHCTL_STATE=$RACE_STATE" \
  "DISCOPARTY_TEST_INSTALL_ORDER_LOG=$RACE_ORDER" \
  "DISCOPARTY_TEST_EXPECT_RESTORED_CONFIG_PATH=$RACE_CONFIG" \
  "DISCOPARTY_TEST_EXPECT_RESTORED_CONFIG_VALUE=prior-config" \
  "DISCOPARTY_TEST_EXPECT_RESTORED_CODEX_CONFIG_PATH=$RACE_CODEX_HOME/config.toml" \
  "DISCOPARTY_TEST_EXPECT_RESTORED_CODEX_CONFIG_VALUE=prior-codex-policy" \
  "DISCOPARTY_TEST_EXPECT_RESTORED_KEYCHAIN_PATH=$RACE_KEYCHAIN" \
  "DISCOPARTY_TEST_EXPECT_RESTORED_KEYCHAIN_VALUE=prior-token" \
  "DISCOPARTY_TEST_SECRET_PROBE=$FAKE_BIN/assert-no-secret" \
  "DISCOPARTY_TEST_SECRET_PROBE_LOG=$SECRET_PROBE_LOG" \
  "$RACE_ROOT/rollback-driver.sh" >"$TEST_ROOT/reinstall-rollback.log" 2>&1; then
  echo "installer reinstall rollback fixture unexpectedly succeeded" >&2
  exit 1
fi
[ "$(cat "$RACE_CONFIG")" = "prior-config" ]
[ "$(cat "$RACE_CODEX_HOME/config.toml")" = "prior-codex-policy" ]
[ "$(cat "$RACE_KEYCHAIN")" = "prior-token" ]
[ "$(cat "$RACE_STATE")" = "loaded" ]
grep -Fq "Restored and restarted the prior com.discoparty.codex-discord-bridge" \
  "$TEST_ROOT/reinstall-rollback.log"
failed_line="$(grep -n -m 1 '^provider-preflight-failed$' "$RACE_ORDER" | cut -d: -f1)"
rollback_bootstrap_line="$(grep -n -m 1 '^launchctl bootstrap ' "$RACE_ORDER" | cut -d: -f1)"
[ "$failed_line" -lt "$rollback_bootstrap_line" ]

touch "$TEST_HOME/Library/LaunchAgents/com.discoparty.discord-gateway-client.plist"
printf '%s' 'claude-token' > "$TEST_HOME/.fake-keychain-discord-bot-token"
AUTH_LOGIN_MARKER="$TEST_HOME/.fake-codex-chatgpt-login"
AUTH_LOGOUT_LOG="$TEST_ROOT/auth-logout.log"
printf '%s\n' logged-in > "$AUTH_LOGIN_MARKER"
if env \
  "HOME=$TEST_HOME" \
  "PATH=$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
  "DISCOPARTY_TEST_LAUNCHCTL_LOG=$LAUNCHCTL_LOG" \
  "DISCOPARTY_TEST_SECRET_PROBE=$FAKE_BIN/assert-no-secret" \
  "DISCOPARTY_TEST_SECRET_PROBE_LOG=$SECRET_PROBE_LOG" \
  "DISCOPARTY_TEST_LAUNCHCTL_SCENARIO=loaded-bootout-fails" \
  "DISCOPARTY_TEST_MODE=1" \
  "DISCOPARTY_TEST_SECURITY_BIN=$FAKE_BIN/security" \
  "DISCOPARTY_TEST_LAUNCHCTL_BIN=$FAKE_BIN/launchctl" \
  "DISCOPARTY_TEST_PYTHON_BIN=$FAKE_BIN/python3" \
  "DISCOPARTY_TEST_EXPECT_REAL_HOME=$TEST_HOME" \
  "DISCOPARTY_TEST_AUTH_LOGOUT_MARKER=$AUTH_LOGIN_MARKER" \
  "DISCOPARTY_TEST_AUTH_LOGOUT_LOG=$AUTH_LOGOUT_LOG" \
  "$TEST_REPO/uninstall.sh" --codex --non-interactive \
  >"$TEST_ROOT/uninstall-bootout-failure.log" 2>&1; then
  echo "Codex uninstall reported success after launchctl bootout failed" >&2
  exit 1
fi
grep -Fq "Could not unload com.discoparty.codex-discord-bridge" \
  "$TEST_ROOT/uninstall-bootout-failure.log"
test -f "$PLIST"
test -f "$TEST_HOME/.fake-keychain-discord-bot-token-codex"
test -f "$AUTH_LOGIN_MARKER"

env \
  "HOME=$TEST_HOME" \
  "PATH=$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
  "DISCOPARTY_TEST_LAUNCHCTL_LOG=$LAUNCHCTL_LOG" \
  "DISCOPARTY_TEST_SECRET_PROBE=$FAKE_BIN/assert-no-secret" \
  "DISCOPARTY_TEST_SECRET_PROBE_LOG=$SECRET_PROBE_LOG" \
  "DISCOPARTY_TEST_MODE=1" \
  "DISCOPARTY_TEST_SECURITY_BIN=$FAKE_BIN/security" \
  "DISCOPARTY_TEST_LAUNCHCTL_BIN=$FAKE_BIN/launchctl" \
  "DISCOPARTY_TEST_PYTHON_BIN=$FAKE_BIN/python3" \
  "DISCOPARTY_TEST_EXPECT_REAL_HOME=$TEST_HOME" \
  "DISCOPARTY_TEST_AUTH_LOGOUT_MARKER=$AUTH_LOGIN_MARKER" \
  "DISCOPARTY_TEST_AUTH_LOGOUT_LOG=$AUTH_LOGOUT_LOG" \
  "$TEST_REPO/uninstall.sh" --codex --non-interactive \
  >"$TEST_ROOT/uninstall.log"

test ! -e "$PLIST"
test ! -e "$TEST_HOME/.fake-keychain-discord-bot-token-codex"
test ! -e "$AUTH_LOGIN_MARKER"
[ "$(grep -c '^logout-configured$' "$AUTH_LOGOUT_LOG")" = "1" ]
test -e "$TEST_HOME/Library/LaunchAgents/com.discoparty.discord-gateway-client.plist"
[ "$(cat "$TEST_HOME/.fake-keychain-discord-bot-token")" = "claude-token" ]
grep -Fq "Claude was left unchanged" "$TEST_ROOT/uninstall.log"

printf '%s\n' logged-in > "$AUTH_LOGIN_MARKER"
env \
  "HOME=$TEST_HOME" \
  "PATH=$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
  "DISCOPARTY_TEST_LAUNCHCTL_LOG=$LAUNCHCTL_LOG" \
  "DISCOPARTY_TEST_SECRET_PROBE=$FAKE_BIN/assert-no-secret" \
  "DISCOPARTY_TEST_SECRET_PROBE_LOG=$SECRET_PROBE_LOG" \
  "DISCOPARTY_TEST_MODE=1" \
  "DISCOPARTY_TEST_SECURITY_BIN=$FAKE_BIN/security" \
  "DISCOPARTY_TEST_LAUNCHCTL_BIN=$FAKE_BIN/launchctl" \
  "DISCOPARTY_TEST_PYTHON_BIN=$FAKE_BIN/python3" \
  "DISCOPARTY_TEST_EXPECT_REAL_HOME=$TEST_HOME" \
  "DISCOPARTY_TEST_AUTH_LOGOUT_MARKER=$AUTH_LOGIN_MARKER" \
  "DISCOPARTY_TEST_AUTH_LOGOUT_LOG=$AUTH_LOGOUT_LOG" \
  "$TEST_REPO/uninstall.sh" --codex --non-interactive \
    --keep-keychain --keep-chatgpt-login \
  >"$TEST_ROOT/uninstall-keep-login.log"
test -f "$AUTH_LOGIN_MARKER"
[ "$(grep -c '^logout-configured$' "$AUTH_LOGOUT_LOG")" = "1" ]
grep -Fq "isolated ChatGPT login was retained" \
  "$TEST_ROOT/uninstall-keep-login.log"
test -s "$SECRET_PROBE_LOG"
! grep -Fq 'leaked' "$SECRET_PROBE_LOG"

echo "install-codex scratch and reinstall smoke test: PASS"
