#!/usr/bin/env bash
#
# Install only Disco Party's Codex Discord provider on the reviewed Apple M5 Max host.
# The existing Claude installer and services are not changed by this script.

set -euo pipefail
set +a
umask 077

# Never accept the Discord credential through the process environment. Record
# only whether the forbidden variable was present, then remove it before the
# first child process. Interactive installs read it silently from the TTY;
# unattended installs require the dedicated Keychain entry to exist already.
CODEX_DISCORD_TOKEN_ENV_WAS_SET=0
if [ "${DISCOPARTY_CODEX_DISCORD_BOT_TOKEN+x}" = "x" ]; then
  CODEX_DISCORD_TOKEN_ENV_WAS_SET=1
fi
unset DISCOPARTY_CODEX_DISCORD_BOT_TOKEN || true
NEW_CODEX_TOKEN=""
export -n NEW_CODEX_TOKEN 2>/dev/null || true
OLD_KEYCHAIN_TOKEN=""
export -n OLD_KEYCHAIN_TOKEN 2>/dev/null || true
LEGACY_KEYCHAIN_TOKEN=""
export -n LEGACY_KEYCHAIN_TOKEN 2>/dev/null || true
OPENAI_API_KEY_WAS_SET=0
if [ "${OPENAI_API_KEY+x}" = "x" ]; then
  OPENAI_API_KEY_WAS_SET=1
fi
unset OPENAI_API_KEY || true
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.discoparty.codex-discord-bridge"
LEGACY_LABEL="com.thesystem.codex-discord-bridge"
TMUX_SESSION="discoparty-codex"
KEYCHAIN_SERVICE="discoparty-secret"
KEYCHAIN_ACCOUNT="discord-bot-token-codex"
LEGACY_KEYCHAIN_SERVICE="thesystem-secret"
LEGACY_KEYCHAIN_ACCOUNT="discord-bot-token-admin"
EXPECTED_CODEX_VERSION="codex-cli 0.153.4"
REVIEWED_NATIVE_CODEX_BIN="/opt/homebrew/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex"

SCRATCH=0
NON_INTERACTIVE=0
REINSTALL=0
START_MONITOR=1
TAKE_OVER_LEGACY=0
IMPORT_LEGACY_TOKEN=0

PYTHON_BIN=""
CODEX_BIN=""
SECURITY_BIN=""
REPO_ROOT=""
CONFIG_PATH=""
PLIST_PATH=""
STATE_DIR=""
LOG_DIR=""
WORKER_HOME=""
CODEX_HOME_DIR=""
KEYCHAIN_HOME=""
SHARED_SKILLS_ROOT=""
RUNTIME_TMP=""
RUNTIME_VENV=""
RUNTIME_VENV_TEMP=""
RUNTIME_VENV_CREATED=0
RUNTIME_PYTHON_MM=""
RUNTIME_WEBSOCKETS_VERSION=""
RUNTIME_LOCK_SHA256=""
ORIGINAL_PLIST_PYTHON=""
TOPOLOGY_VALIDATED=0
NATIVE_CODEX_BIN=""
SECURITY_BIN="/usr/bin/security"
LAUNCHCTL_BIN="/bin/launchctl"
PLUTIL_BIN="/usr/bin/plutil"
UNAME_BIN="/usr/bin/uname"
SYSCTL_BIN="/usr/sbin/sysctl"

LEGACY_REPO_ROOT=""
LEGACY_PLIST_PATH=""
LEGACY_STATE_DIR=""
LEGACY_DATABASE_PATH=""
LEGACY_DETECTED=0
LEGACY_VALIDATED=0
LEGACY_ARCHIVED=0
LEGACY_PRIOR_LOADED=0
LEGACY_PRIOR_DISABLED=0
LEGACY_AGENT_QUIESCED=0
LEGACY_DISABLED=0
LEGACY_DESCENDANTS_DRAINED=0
LEGACY_PROCESS_PIDS=""
LEGACY_ROOT_CURSOR=""
LEGACY_BACKUP_DIR=""
LEGACY_HANDOFF_STATE="none"
LEGACY_HANDOFF_DB_CREATED=0
LEGACY_HANDOFF_MARKER=""

OLD_KEYCHAIN_PRESENT=0
KEYCHAIN_MUTATED=0

CONFIG_BACKUP=""
CONFIG_EXISTED=0
CONFIG_MUTATED=0
PLIST_BACKUP=""
PLIST_EXISTED=0
PLIST_SNAPSHOTTED=0
PLIST_MUTATED=0
BOOTSTRAP_MUTATED=0
PRIOR_AGENT_QUIESCED=0
CODEX_CONFIG_BACKUP=""
CODEX_CONFIG_EXISTED=0
CODEX_CONFIG_MUTATED=0
CODEX_HOOKS_BACKUP=""
CODEX_HOOKS_EXISTED=0
CODEX_HOOKS_MUTATED=0
SKILL_BRIDGE_CREATED=0

red()    { printf "\033[31m%s\033[0m\n" "$*"; }
green()  { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
blue()   { printf "\033[34m%s\033[0m\n" "$*"; }
say()    { printf "%s\n" "$*"; }

die() {
  red "ERROR: $*"
  exit 1
}

require_topology_validated() {
  [ "$TOPOLOGY_VALIDATED" = "1" ] || \
    die "Filesystem topology has not passed fail-closed validation."
}

usage() {
  cat <<'EOF'
Usage: ./install-codex.sh [options]

Installs only the Codex Discord provider. Claude remains untouched.

Options:
  --scratch           Render and validate, but do not bootstrap launchd or
                      start the tmux monitor.
  --non-interactive   Read nonsecret settings from environment variables. The
                      dedicated Discord token must already be in Keychain.
  --reinstall         Replace an existing Codex provider installation.
  --take-over-legacy  Opt in to replacing the exact validated legacy
                      com.thesystem Codex bridge. This requires a maintenance
                      acknowledgment and a durable root-cursor handoff.
  --import-legacy-token
                      With --take-over-legacy, copy the exact legacy Codex bot
                      token between Keychain items without putting it in argv,
                      environment variables, generated files, or logs.
  --monitor           Start the optional read-only tmux monitor (default).
  --no-monitor        Do not start the optional tmux monitor.
  --tmux-session NAME Override the monitor name (default: discoparty-codex).
  --uninstall         Run uninstall.sh --codex and exit.
  -h, --help          Show this help.

Required in --non-interactive mode:
  DISCOPARTY_CODEX_GUILD_ID
  DISCOPARTY_CODEX_CHANNEL_ID
  DISCOPARTY_CODEX_OWNER_USER_ID
  DISCOPARTY_CODEX_BOT_USER_ID
  DISCOPARTY_CODEX_APPLICATION_ID
  DISCOPARTY_CODEX_WORKING_DIRECTORY
  DISCOPARTY_CODEX_CHANNEL_TRUST      public (default) or owner_private
  DISCOPARTY_CODEX_SANDBOX_MODE       workspace-write or danger-full-access

Full computer access:
  DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED
  danger-full-access requires this exact acceptance independently of channel
  trust. public and owner_private may each use either sandbox mode.

Destination trust:
  public relies on best-effort output redaction and is not confidential.
  owner_private requires a private parent channel whose only effective readers
  are the Discord guild owner and the dedicated bridge bot.

Legacy takeover in --non-interactive mode:
  DISCOPARTY_CODEX_LEGACY_MAINTENANCE_ACCEPTED=LEGACY_MAINTENANCE_ACCEPTED

Optional:
  DISCOPARTY_REPO_ROOT
  DISCOPARTY_CODEX_STATE_DIR
  DISCOPARTY_CODEX_BIN
  DISCOPARTY_CODEX_SHARED_SKILLS_ROOT
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --scratch) SCRATCH=1; shift ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --reinstall) REINSTALL=1; shift ;;
    --take-over-legacy) TAKE_OVER_LEGACY=1; shift ;;
    --import-legacy-token) IMPORT_LEGACY_TOKEN=1; shift ;;
    --monitor) START_MONITOR=1; shift ;;
    --no-monitor) START_MONITOR=0; shift ;;
    --tmux-session)
      [ $# -ge 2 ] || die "--tmux-session requires a name."
      TMUX_SESSION="$2"
      shift 2
      ;;
    --uninstall)
      exec "$SCRIPT_DIR/uninstall.sh" --codex --tmux-session "$TMUX_SESSION"
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown flag: $1" ;;
  esac
done

if [ "$IMPORT_LEGACY_TOKEN" = "1" ] && [ "$TAKE_OVER_LEGACY" != "1" ]; then
  die "--import-legacy-token requires --take-over-legacy."
fi
if [ "$TAKE_OVER_LEGACY" = "1" ] && [ "$REINSTALL" = "1" ]; then
  die "--take-over-legacy cannot be combined with --reinstall."
fi

if [ "$SCRATCH" = "1" ]; then
  SECURITY_BIN="${DISCOPARTY_TEST_SECURITY_BIN:-$SECURITY_BIN}"
  LAUNCHCTL_BIN="${DISCOPARTY_TEST_LAUNCHCTL_BIN:-$LAUNCHCTL_BIN}"
  PLUTIL_BIN="${DISCOPARTY_TEST_PLUTIL_BIN:-$PLUTIL_BIN}"
  UNAME_BIN="${DISCOPARTY_TEST_UNAME_BIN:-$UNAME_BIN}"
  SYSCTL_BIN="${DISCOPARTY_TEST_SYSCTL_BIN:-$SYSCTL_BIN}"
fi

cleanup_runtime_temp() {
  [ -n "$RUNTIME_VENV_TEMP" ] || return 0
  [ -n "$STATE_DIR" ] || return 0
  case "$RUNTIME_VENV_TEMP" in
    "$STATE_DIR"/.runtime-venv-*.tmp.*)
      rm -rf -- "$RUNTIME_VENV_TEMP"
      ;;
    *)
      yellow "Refusing to remove an unexpected runtime staging path: $RUNTIME_VENV_TEMP"
      ;;
  esac
  RUNTIME_VENV_TEMP=""
}

cleanup_created_runtime() {
  [ "$RUNTIME_VENV_CREATED" = "1" ] || return 0
  [ "$BOOTSTRAP_MUTATED" = "0" ] || return 0
  [ -n "$RUNTIME_VENV" ] && [ -n "$STATE_DIR" ] || return 0
  [ "$ORIGINAL_PLIST_PYTHON" != "$RUNTIME_VENV/bin/python3" ] || return 0
  case "$RUNTIME_VENV" in
    "$STATE_DIR"/runtime-venv-cpython-*-websockets-*)
      rm -rf -- "$RUNTIME_VENV"
      ;;
    *)
      yellow "Refusing to remove an unexpected runtime path: $RUNTIME_VENV"
      ;;
  esac
}

rollback_legacy_handoff_db() {
  [ "$LEGACY_HANDOFF_DB_CREATED" = "1" ] || return 0
  [ -n "$STATE_DIR" ] || return 1
  local database="$STATE_DIR/jobs.sqlite3"
  case "$database" in
    "$STATE_DIR"/jobs.sqlite3) ;;
    *) return 1 ;;
  esac
  if [ ! -e "$database" ]; then
    LEGACY_HANDOFF_DB_CREATED=0
    return 0
  fi
  if ! env -u PYTHONHOME -u PYTHONPATH -u PYTHONPYCACHEPREFIX -u PYTHONUSERBASE \
      PYTHONSAFEPATH=1 "$PYTHON_BIN" - "$database" <<'PY'
import sqlite3
import sys
from pathlib import Path

path = Path(sys.argv[1])
with sqlite3.connect(f"file:{path}?mode=ro", uri=True) as db:
    jobs = int(db.execute("SELECT COUNT(*) FROM jobs").fetchone()[0])
    manifests = int(db.execute("SELECT COUNT(*) FROM delivery_manifests").fetchone()[0])
    deliveries = int(db.execute("SELECT COUNT(*) FROM deliveries").fetchone()[0])
    sessions = int(db.execute("SELECT COUNT(*) FROM sessions").fetchone()[0])
if jobs or manifests or deliveries or sessions:
    raise SystemExit(
        "the replacement ledger accepted work or routing state; automatic legacy rollback is unsafe"
    )
PY
  then
    return 1
  fi
  rm -f -- "$database" "$database-wal" "$database-shm"
  LEGACY_HANDOFF_DB_CREATED=0
  return 0
}

rollback_skill_bridge() {
  [ "$SKILL_BRIDGE_CREATED" = "1" ] || return 0
  [ -n "$CODEX_HOME_DIR" ] && [ -n "$SHARED_SKILLS_ROOT" ] || return 1
  PYTHONPATH="$REPO_ROOT" "$PYTHON_BIN" - \
    "$CODEX_HOME_DIR" "$SHARED_SKILLS_ROOT" <<'PY'
import sys
from pathlib import Path

from codex_discord_bridge.shared_skills import remove_created_skill_bridge

remove_created_skill_bridge(Path(sys.argv[1]), Path(sys.argv[2]))
PY
  SKILL_BRIDGE_CREATED=0
}

rollback_and_cleanup() {
  local status=$?
  local rollback_safe=1
  local legacy_restored=0
  local restored_keychain=""
  trap - EXIT

  if [ "$status" -ne 0 ]; then
    yellow "Installation failed. Restoring the prior Codex installer state."

    if [ "$BOOTSTRAP_MUTATED" = "1" ] && [ -n "$PLIST_PATH" ]; then
      if ! "$LAUNCHCTL_BIN" bootout "gui/$UID/$LABEL" >/dev/null 2>&1; then
        if "$LAUNCHCTL_BIN" print "gui/$UID/$LABEL" >/dev/null 2>&1; then
          rollback_safe=0
          red "ERROR: Could not stop the failed replacement $LABEL during rollback."
        fi
      fi
    fi

    if ! rollback_legacy_handoff_db; then
      rollback_safe=0
      red "ERROR: The Disco Party ledger contains work or could not be inspected; legacy rollback is unsafe."
    fi

    if [ "$PLIST_MUTATED" = "1" ] && [ -n "$PLIST_PATH" ]; then
      if [ "$PLIST_EXISTED" = "1" ]; then
        if [ -n "$PLIST_BACKUP" ] && cp -p "$PLIST_BACKUP" "$PLIST_PATH"; then
          :
        else
          rollback_safe=0
          red "ERROR: Could not restore the prior Codex LaunchAgent plist."
        fi
      else
        if ! rm -f "$PLIST_PATH"; then
          rollback_safe=0
          red "ERROR: Could not remove the failed Codex LaunchAgent plist."
        fi
      fi
    fi

    if [ "$CONFIG_MUTATED" = "1" ] && [ -n "$CONFIG_PATH" ]; then
      if [ "$CONFIG_EXISTED" = "1" ]; then
        if [ -n "$CONFIG_BACKUP" ] && cp -p "$CONFIG_BACKUP" "$CONFIG_PATH"; then
          :
        else
          rollback_safe=0
          red "ERROR: Could not restore the prior Disco Party config."
        fi
      else
        if ! rm -f "$CONFIG_PATH"; then
          rollback_safe=0
          red "ERROR: Could not remove the failed Disco Party config."
        fi
      fi
    fi

    if [ "$CODEX_CONFIG_MUTATED" = "1" ] && [ -n "$CODEX_HOME_DIR" ]; then
      if [ "$CODEX_CONFIG_EXISTED" = "1" ]; then
        if [ -n "$CODEX_CONFIG_BACKUP" ] && \
            cp -p "$CODEX_CONFIG_BACKUP" "$CODEX_HOME_DIR/config.toml"; then
          :
        else
          rollback_safe=0
          red "ERROR: Could not restore the prior isolated Codex policy."
        fi
      else
        if ! rm -f "$CODEX_HOME_DIR/config.toml"; then
          rollback_safe=0
          red "ERROR: Could not remove the failed isolated Codex policy."
        fi
      fi
    fi

    if [ "$CODEX_HOOKS_MUTATED" = "1" ] && [ -n "$CODEX_HOME_DIR" ]; then
      if [ "$CODEX_HOOKS_EXISTED" = "1" ]; then
        if [ -n "$CODEX_HOOKS_BACKUP" ] && \
            cp -p "$CODEX_HOOKS_BACKUP" "$CODEX_HOME_DIR/hooks.json"; then
          :
        else
          rollback_safe=0
          red "ERROR: Could not restore the prior isolated Codex hooks."
        fi
      else
        if ! rm -f "$CODEX_HOME_DIR/hooks.json"; then
          rollback_safe=0
          red "ERROR: Could not remove the failed isolated Codex hooks."
        fi
      fi
    fi

    if ! rollback_skill_bridge; then
      rollback_safe=0
      red "ERROR: Could not remove the validated Codex shared-skill bridge."
    fi

    if [ "$KEYCHAIN_MUTATED" = "1" ] && [ -n "$SECURITY_BIN" ]; then
      if [ "$OLD_KEYCHAIN_PRESENT" = "1" ]; then
        if ! printf '%s\n' "$OLD_KEYCHAIN_TOKEN" | \
          "$SECURITY_BIN" add-generic-password \
            -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" \
            -U -w >/dev/null 2>&1; then
          rollback_safe=0
          red "ERROR: Could not restore the prior Codex Keychain token."
        else
          restored_keychain="$($SECURITY_BIN find-generic-password \
            -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null || true)"
          if [ "$restored_keychain" != "$OLD_KEYCHAIN_TOKEN" ]; then
            rollback_safe=0
            red "ERROR: The prior Codex Keychain token failed readback verification."
          fi
          restored_keychain=""
        fi
      else
        "$SECURITY_BIN" delete-generic-password \
          -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" >/dev/null 2>&1 || true
        if "$SECURITY_BIN" find-generic-password \
            -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" >/dev/null 2>&1; then
          rollback_safe=0
          red "ERROR: The failed Codex Keychain token still exists after rollback."
        fi
      fi
    fi

    # The prior agent must not see any of the failed installer's policy,
    # configuration, or credentials. Reload it only after every shared input
    # above has been restored.
    if [ "$PRIOR_AGENT_QUIESCED" = "1" ] && [ -n "$PLIST_PATH" ]; then
      if [ "$rollback_safe" != "1" ]; then
        "$LAUNCHCTL_BIN" bootout "gui/$UID/$LABEL" >/dev/null 2>&1 || true
        red "ERROR: The prior $LABEL was not restarted because rollback was incomplete."
      elif "$LAUNCHCTL_BIN" print "gui/$UID/$LABEL" >/dev/null 2>&1; then
        green "  Prior $LABEL was already loaded during rollback."
      elif "$LAUNCHCTL_BIN" bootstrap "gui/$UID" "$PLIST_PATH" >/dev/null 2>&1 && \
          "$LAUNCHCTL_BIN" print "gui/$UID/$LABEL" >/dev/null 2>&1; then
        green "  Restored and restarted the prior $LABEL."
      else
        red "ERROR: Could not restart the prior $LABEL after rollback. Load $PLIST_PATH manually."
      fi
    fi

    if [ "$LEGACY_AGENT_QUIESCED" = "1" ] && [ -n "$LEGACY_PLIST_PATH" ]; then
      if [ "$rollback_safe" != "1" ] || [ "$LEGACY_DESCENDANTS_DRAINED" != "1" ]; then
        "$LAUNCHCTL_BIN" bootout "gui/$UID/$LEGACY_LABEL" >/dev/null 2>&1 || true
        red "ERROR: The legacy $LEGACY_LABEL was not restarted because rollback is incomplete or a descendant may remain."
      elif [ "$LEGACY_PRIOR_LOADED" != "1" ]; then
        if [ "$LEGACY_PRIOR_DISABLED" = "1" ]; then
          if "$LAUNCHCTL_BIN" disable "gui/$UID/$LEGACY_LABEL" >/dev/null 2>&1 && \
              legacy_label_disabled; then
            legacy_restored=1
          fi
        else
          if "$LAUNCHCTL_BIN" enable "gui/$UID/$LEGACY_LABEL" >/dev/null 2>&1 && \
              ! legacy_label_disabled; then
            legacy_restored=1
          fi
        fi
        if [ "$legacy_restored" = "1" ]; then
          green "  Restored the legacy launchd enablement state; it was not running before takeover."
        else
          rollback_safe=0
          red "ERROR: Could not restore the prior legacy launchd enablement state."
        fi
      else
        if ! "$LAUNCHCTL_BIN" enable "gui/$UID/$LEGACY_LABEL" >/dev/null 2>&1; then
          rollback_safe=0
          red "ERROR: Could not enable legacy $LEGACY_LABEL for rollback."
        elif "$LAUNCHCTL_BIN" print "gui/$UID/$LEGACY_LABEL" >/dev/null 2>&1 || \
            { "$LAUNCHCTL_BIN" bootstrap "gui/$UID" "$LEGACY_PLIST_PATH" >/dev/null 2>&1 && \
              "$LAUNCHCTL_BIN" print "gui/$UID/$LEGACY_LABEL" >/dev/null 2>&1; }; then
          if [ "$LEGACY_PRIOR_DISABLED" = "1" ]; then
            if "$LAUNCHCTL_BIN" disable "gui/$UID/$LEGACY_LABEL" >/dev/null 2>&1 && \
                legacy_label_disabled; then
              legacy_restored=1
            fi
          elif ! legacy_label_disabled; then
            legacy_restored=1
          fi
          if [ "$legacy_restored" = "1" ]; then
            green "  Restored and restarted the legacy $LEGACY_LABEL."
          else
            rollback_safe=0
            red "ERROR: Legacy $LEGACY_LABEL restarted, but its prior enablement state was not restored."
          fi
        else
          rollback_safe=0
          red "ERROR: Could not restart legacy $LEGACY_LABEL after rollback."
        fi
      fi
      if [ -n "$LEGACY_HANDOFF_MARKER" ] && [ -n "$LEGACY_ROOT_CURSOR" ]; then
        if [ "$legacy_restored" = "1" ]; then
          write_legacy_handoff_state "rolled_back" || true
        else
          write_legacy_handoff_state "rollback_blocked" || true
        fi
      fi
    fi

    # A newly published runtime can be removed only while launchd has never
    # been changed and the original plist did not reference it. Existing and
    # previously referenced runtime directories are never repaired in place.
    cleanup_created_runtime
  fi

  cleanup_runtime_temp

  [ -z "$CONFIG_BACKUP" ] || rm -f "$CONFIG_BACKUP"
  [ -z "$PLIST_BACKUP" ] || rm -f "$PLIST_BACKUP"
  [ -z "$CODEX_CONFIG_BACKUP" ] || rm -f "$CODEX_CONFIG_BACKUP"
  [ -z "$CODEX_HOOKS_BACKUP" ] || rm -f "$CODEX_HOOKS_BACKUP"
  NEW_CODEX_TOKEN=""
  OLD_KEYCHAIN_TOKEN=""
  LEGACY_KEYCHAIN_TOKEN=""
  unset DISCOPARTY_CODEX_DISCORD_BOT_TOKEN OPENAI_API_KEY || true
  exit "$status"
}
trap rollback_and_cleanup EXIT

prompt_required() {
  local name="$1" label="$2" default_value="${3:-}"
  local current="${!name:-}"

  if [ "$NON_INTERACTIVE" = "1" ]; then
    [ -n "$current" ] || die "$name is required in --non-interactive mode."
    return 0
  fi

  if [ -z "$current" ]; then
    current="$default_value"
  fi
  local input=""
  if [ -n "$current" ]; then
    read -r -p "$label [$current]: " input
    input="${input:-$current}"
  else
    read -r -p "$label: " input
  fi
  [ -n "$input" ] || die "$name cannot be empty."
  printf -v "$name" '%s' "$input"
}

prompt_optional() {
  local name="$1" label="$2" default_value="${3:-}"
  local current="${!name:-$default_value}"
  if [ "$NON_INTERACTIVE" = "1" ]; then
    printf -v "$name" '%s' "$current"
    return 0
  fi
  local input=""
  read -r -p "$label [$current]: " input
  printf -v "$name" '%s' "${input:-$current}"
}

validate_snowflake() {
  local name="$1" value="${!1:-}"
  [[ "$value" =~ ^[0-9]{17,20}$ ]] || \
    die "$name must be an immutable 17 to 20 digit Discord ID."
}

check_no_api_key() {
  if [ "$OPENAI_API_KEY_WAS_SET" = "1" ]; then
    die "OPENAI_API_KEY must be unset. This provider only uses a ChatGPT subscription login."
  fi
  if [ "$CODEX_DISCORD_TOKEN_ENV_WAS_SET" = "1" ]; then
    die "DISCOPARTY_CODEX_DISCORD_BOT_TOKEN is forbidden. Pre-provision the dedicated Keychain entry or use the silent interactive prompt."
  fi
}

check_prerequisites() {
  blue "Checking the Apple M5 Max and provider prerequisites."

  [ -x "$UNAME_BIN" ] || die "The pinned uname command is unavailable."
  [ -x "$SYSCTL_BIN" ] || die "The pinned sysctl command is unavailable."
  [ "$("$UNAME_BIN" -s)" = "Darwin" ] || die "This installer only supports macOS."
  [ "$("$UNAME_BIN" -m)" = "arm64" ] || die "This installer requires Apple Silicon arm64."
  local chip
  chip="$("$SYSCTL_BIN" -n machdep.cpu.brand_string 2>/dev/null || true)"
  [ "$chip" = "Apple M5 Max" ] || \
    die "This installer targets the reviewed Apple M5 Max host (found: ${chip:-unknown})."

  if [ "$SCRATCH" = "1" ] && [ -n "${DISCOPARTY_TEST_PYTHON_BIN:-}" ]; then
    PYTHON_BIN="$DISCOPARTY_TEST_PYTHON_BIN"
  else
    command -v python3 >/dev/null 2>&1 || die "python3 is not on the sanitized PATH."
    PYTHON_BIN="$(command -v python3)"
  fi
  local python_version
  python_version="$($PYTHON_BIN -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
  "$PYTHON_BIN" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' || \
    die "Python 3.11 or newer is required (found $python_version)."
  [ -x "$SECURITY_BIN" ] || die "The pinned macOS security command is unavailable."
  [ -x "$LAUNCHCTL_BIN" ] || die "The pinned launchctl command is unavailable."
  [ -x "$PLUTIL_BIN" ] || die "The pinned plutil command is unavailable."

  CODEX_BIN="${DISCOPARTY_CODEX_BIN:-$(command -v codex || true)}"
  [ -n "$CODEX_BIN" ] && [ -x "$CODEX_BIN" ] || \
    die "The official Codex CLI is not installed or executable."
  case "$CODEX_BIN" in
    /*) ;;
    *) CODEX_BIN="$(cd "$(dirname "$CODEX_BIN")" && pwd -P)/$(basename "$CODEX_BIN")" ;;
  esac

  green "  $chip, Python $python_version, websockets, and local prerequisites: OK"
}

existing_configured_state_dir() {
  env -u PYTHONHOME -u PYTHONPATH -u PYTHONPYCACHEPREFIX -u PYTHONUSERBASE \
    PYTHONSAFEPATH=1 "$PYTHON_BIN" - "$CONFIG_PATH" <<'PY'
import os
import stat
import sys
import tomllib
from pathlib import Path

path = Path(sys.argv[1])
try:
    metadata = path.lstat()
except FileNotFoundError:
    print("")
    raise SystemExit(0)
except OSError as exc:
    raise SystemExit("Could not inspect existing Disco Party config") from exc
if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
    raise SystemExit("Existing Disco Party config must be a real regular file, not a symlink")
if metadata.st_uid != os.getuid():
    raise SystemExit("Existing Disco Party config must be owned by the current user")
if stat.S_IMODE(metadata.st_mode) & 0o022:
    raise SystemExit("Existing Disco Party config must not be group/world writable")
if metadata.st_nlink != 1:
    raise SystemExit("Existing Disco Party config must have exactly one hard link")
try:
    with path.open("rb") as stream:
        parsed = tomllib.load(stream)
except (OSError, tomllib.TOMLDecodeError) as exc:
    raise SystemExit("Existing Disco Party config is not valid TOML") from exc
codex = parsed.get("codex", {})
if not isinstance(codex, dict):
    raise SystemExit("Existing Disco Party [codex] config must be a table")
state_dir = codex.get("state_dir")
if state_dir is None:
    print("")
else:
    if not isinstance(state_dir, str) or not state_dir:
        raise SystemExit("Existing codex.state_dir must be a non-empty path")
    expanded = Path(state_dir).expanduser()
    if not expanded.is_absolute():
        raise SystemExit("Existing codex.state_dir must expand to an absolute path")
    print(expanded)
PY
}

resolve_settings() {
  REPO_ROOT="${DISCOPARTY_REPO_ROOT:-$SCRIPT_DIR}"
  if [ "$NON_INTERACTIVE" != "1" ]; then
    prompt_optional REPO_ROOT "Disco Party repo root" "$SCRIPT_DIR"
  fi
  REPO_ROOT="${REPO_ROOT/#\~/$HOME}"
  [ -d "$REPO_ROOT" ] || die "Disco Party repo root does not exist: $REPO_ROOT"
  REPO_ROOT="$(cd "$REPO_ROOT" && pwd -P)"
  [ -f "$REPO_ROOT/codex_discord_bridge/main.py" ] || \
    die "Codex bridge package is missing from $REPO_ROOT."
  CONFIG_PATH="$REPO_ROOT/config.toml"

  prompt_required DISCOPARTY_CODEX_GUILD_ID "Discord guild ID"
  prompt_required DISCOPARTY_CODEX_CHANNEL_ID "Discord channel ID"
  prompt_required DISCOPARTY_CODEX_OWNER_USER_ID "Discord owner user ID"
  prompt_required DISCOPARTY_CODEX_BOT_USER_ID "Dedicated Discord bot user ID"
  prompt_required DISCOPARTY_CODEX_APPLICATION_ID "Dedicated Discord application ID"
  prompt_required DISCOPARTY_CODEX_WORKING_DIRECTORY \
    "Codex working directory" ""
  DISCOPARTY_CODEX_CHANNEL_TRUST="${DISCOPARTY_CODEX_CHANNEL_TRUST:-public}"
  prompt_optional DISCOPARTY_CODEX_CHANNEL_TRUST \
    "Discord channel trust (public or owner_private)" "public"
  prompt_required DISCOPARTY_CODEX_SANDBOX_MODE \
    "Codex sandbox mode (workspace-write or danger-full-access)" "workspace-write"

  validate_snowflake DISCOPARTY_CODEX_GUILD_ID
  validate_snowflake DISCOPARTY_CODEX_CHANNEL_ID
  validate_snowflake DISCOPARTY_CODEX_OWNER_USER_ID
  validate_snowflake DISCOPARTY_CODEX_BOT_USER_ID
  validate_snowflake DISCOPARTY_CODEX_APPLICATION_ID
  [ "$DISCOPARTY_CODEX_OWNER_USER_ID" != "$DISCOPARTY_CODEX_BOT_USER_ID" ] || \
    die "The owner and Codex bot must be different Discord identities."
  case "$DISCOPARTY_CODEX_CHANNEL_TRUST" in
    public|owner_private) ;;
    *) die "DISCOPARTY_CODEX_CHANNEL_TRUST must be public or owner_private." ;;
  esac

  DISCOPARTY_CODEX_WORKING_DIRECTORY="${DISCOPARTY_CODEX_WORKING_DIRECTORY/#\~/$HOME}"
  [ -d "$DISCOPARTY_CODEX_WORKING_DIRECTORY" ] || \
    die "Codex working directory does not exist: $DISCOPARTY_CODEX_WORKING_DIRECTORY"
  DISCOPARTY_CODEX_WORKING_DIRECTORY="$(cd "$DISCOPARTY_CODEX_WORKING_DIRECTORY" && pwd -P)"

  local default_shared_skills_root="$HOME/TheSystem/x_System/Skills"
  if [ -f "$CONFIG_PATH" ]; then
    default_shared_skills_root="$("$PYTHON_BIN" - "$CONFIG_PATH" "$HOME" <<'PY'
import sys
import tomllib
from pathlib import Path

config = Path(sys.argv[1])
home = Path(sys.argv[2])
with config.open("rb") as stream:
    parsed = tomllib.load(stream)
raw = parsed.get("paths", {}).get("workspace_root")
if raw is None:
    print(home / "TheSystem/x_System/Skills")
elif not isinstance(raw, str) or not raw:
    raise SystemExit("paths.workspace_root must be a non-empty path")
else:
    workspace = Path(raw).expanduser()
    if not workspace.is_absolute():
        raise SystemExit("paths.workspace_root must expand to an absolute path")
    print(workspace / "x_System/Skills")
PY
)"
  fi
  DISCOPARTY_CODEX_SHARED_SKILLS_ROOT="${DISCOPARTY_CODEX_SHARED_SKILLS_ROOT:-$default_shared_skills_root}"
  prompt_optional DISCOPARTY_CODEX_SHARED_SKILLS_ROOT \
    "Canonical shared Vault x_System/Skills directory" \
    "$default_shared_skills_root"
  DISCOPARTY_CODEX_SHARED_SKILLS_ROOT="${DISCOPARTY_CODEX_SHARED_SKILLS_ROOT/#\~/$HOME}"
  SHARED_SKILLS_ROOT="$(PYTHONPATH="$REPO_ROOT" "$PYTHON_BIN" - \
    "$DISCOPARTY_CODEX_SHARED_SKILLS_ROOT" <<'PY'
import sys
from pathlib import Path

from codex_discord_bridge.shared_skills import bind_shared_skills

print(bind_shared_skills(Path(sys.argv[1])).root)
PY
)"

  case "$DISCOPARTY_CODEX_SANDBOX_MODE" in
    workspace-write)
      DISCOPARTY_CODEX_FULL_ACCESS_BOOL="false"
      ;;
    danger-full-access)
      [ "${DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED:-}" = \
        "FULL_COMPUTER_ACCESS_ACCEPTED" ] || \
        die "danger-full-access requires DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED."
      DISCOPARTY_CODEX_FULL_ACCESS_BOOL="true"
      ;;
    *) die "DISCOPARTY_CODEX_SANDBOX_MODE must be workspace-write or danger-full-access." ;;
  esac

  local default_state="$HOME/Library/Application Support/Discoparty/codex-discord"
  if [ -z "${DISCOPARTY_CODEX_STATE_DIR:-}" ]; then
    local configured_state=""
    configured_state="$(existing_configured_state_dir)"
    [ -z "$configured_state" ] || default_state="$configured_state"
  fi
  STATE_DIR="${DISCOPARTY_CODEX_STATE_DIR:-$default_state}"
  if [ "$NON_INTERACTIVE" != "1" ]; then
    prompt_optional STATE_DIR "Codex state directory" "$default_state"
  fi
  STATE_DIR="${STATE_DIR/#\~/$HOME}"
  LOG_DIR="$REPO_ROOT/logs"
  PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"

  # Resolve every writable and control path before creating the state tree,
  # workspace temporary directory, runtime, logs, or a browser login flow.
  STATE_DIR="$(env -u PYTHONHOME -u PYTHONPATH -u PYTHONPYCACHEPREFIX -u PYTHONUSERBASE \
    PYTHONSAFEPATH=1 "$PYTHON_BIN" - \
    "$HOME" "$REPO_ROOT" "$DISCOPARTY_CODEX_WORKING_DIRECTORY" \
    "$SHARED_SKILLS_ROOT" "$STATE_DIR" "$CONFIG_PATH" "$LOG_DIR" "$PLIST_PATH" <<'PY'
import os
import stat
import sys
import tomllib
from pathlib import Path

home_input = Path(sys.argv[1]).absolute()
home = home_input.resolve(strict=True)
repo = Path(sys.argv[2]).resolve(strict=True)
workspace = Path(sys.argv[3]).resolve(strict=True)
shared_skills = Path(sys.argv[4]).resolve(strict=True)
raw_state = Path(os.path.abspath(sys.argv[5]))
config = Path(sys.argv[6])
logs = Path(sys.argv[7])
plist = Path(sys.argv[8])

home_metadata = home.lstat()
if (
    not stat.S_ISDIR(home_metadata.st_mode)
    or home_metadata.st_uid != os.getuid()
    or stat.S_IMODE(home_metadata.st_mode) & 0o022
):
    raise SystemExit(
        "Canonical HOME must be current-user-owned and not group/world writable"
    )

try:
    relative_state = raw_state.relative_to(home_input)
except ValueError:
    try:
        relative_state = raw_state.resolve(strict=False).relative_to(home)
    except ValueError as exc:
        raise SystemExit("Codex state_dir must stay under the current user's home") from exc
approved_relative = ("Library", "Application Support", "Discoparty")
if (
    relative_state.parts[: len(approved_relative)] != approved_relative
    or len(relative_state.parts) <= len(approved_relative)
):
    raise SystemExit(
        "Codex state_dir must stay under canonical ~/Library/Application Support/Discoparty"
    )

state_candidate = home.joinpath(*relative_state.parts)
current = home
for part in relative_state.parts:
    current = current / part
    try:
        metadata = current.lstat()
    except FileNotFoundError:
        break
    except OSError as exc:
        raise SystemExit("Could not inspect the Codex state_dir topology") from exc
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise SystemExit("Codex state_dir components must be real directories, not symlinks")
    if metadata.st_uid != os.getuid():
        raise SystemExit("Existing Codex state_dir components must be owned by the current user")
    if stat.S_IMODE(metadata.st_mode) & 0o022:
        raise SystemExit("Existing Codex state_dir components must not be group/world writable")
state = state_candidate.resolve(strict=False)

def ancestor_identities(path: Path) -> set[tuple[int, int]]:
    identities: set[tuple[int, int]] = set()
    current = path
    while True:
        metadata = current.stat()
        identities.add((metadata.st_dev, metadata.st_ino))
        parent = current.parent
        if parent == current:
            return identities
        current = parent


def overlaps(first: Path, second: Path) -> bool:
    first_resolved = first.resolve(strict=False)
    second_resolved = second.resolve(strict=False)
    if (
        first_resolved == second_resolved
        or first_resolved.is_relative_to(second_resolved)
        or second_resolved.is_relative_to(first_resolved)
    ):
        return True
    try:
        first_metadata = first_resolved.stat()
        second_metadata = second_resolved.stat()
    except OSError:
        return False
    first_identity = (first_metadata.st_dev, first_metadata.st_ino)
    second_identity = (second_metadata.st_dev, second_metadata.st_ino)
    return (
        first_identity in ancestor_identities(second_resolved)
        or second_identity in ancestor_identities(first_resolved)
    )

if overlaps(state, repo):
    raise SystemExit("Codex state_dir must not overlap the Disco Party repository")
if overlaps(state, workspace):
    raise SystemExit("Codex state_dir must not overlap the Codex working_directory")
if overlaps(workspace, repo):
    raise SystemExit("Codex working_directory must not overlap the Disco Party repository")

def inspect_control_path(path: Path, label: str, directory: bool) -> None:
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        return
    except OSError as exc:
        raise SystemExit(f"Could not inspect existing {label}") from exc
    expected_shape = stat.S_ISDIR(metadata.st_mode) if directory else stat.S_ISREG(metadata.st_mode)
    if stat.S_ISLNK(metadata.st_mode) or not expected_shape:
        shape = "directory" if directory else "regular file"
        raise SystemExit(f"Existing {label} must be a real {shape}, not a symlink")
    if metadata.st_uid != os.getuid():
        raise SystemExit(f"Existing {label} must be owned by the current user")
    if stat.S_IMODE(metadata.st_mode) & 0o022:
        raise SystemExit(f"Existing {label} must not be group/world writable")
    if not directory and metadata.st_nlink != 1:
        raise SystemExit(f"Existing {label} must have exactly one hard link")

inspect_control_path(config, "Disco Party config", directory=False)
inspect_control_path(logs, "Codex logs directory", directory=True)
inspect_control_path(plist, "Codex LaunchAgent plist", directory=False)
inspect_control_path(
    logs / "codex-discord-bridge.stdout.log",
    "Codex stdout log",
    directory=False,
)
inspect_control_path(
    logs / "codex-discord-bridge.stderr.log",
    "Codex stderr log",
    directory=False,
)

control_paths = {
    "Disco Party config": config.resolve(strict=False),
    "Codex LaunchAgent plist": plist.resolve(strict=False),
    "Codex logs directory": logs.resolve(strict=False),
    "canonical shared Vault skill root": shared_skills,
}
if config.exists():
    try:
        with config.open("rb") as stream:
            parsed = tomllib.load(stream)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise SystemExit("Existing Disco Party config is not valid TOML") from exc
    codex = parsed.get("codex", {})
    if not isinstance(codex, dict):
        raise SystemExit("Existing Disco Party [codex] config must be a table")
    instructions = codex.get("instructions_file")
    if instructions is not None:
        if not isinstance(instructions, str) or not instructions:
            raise SystemExit("Existing codex.instructions_file must be a non-empty path")
        instructions_path = Path(instructions).expanduser()
        if not instructions_path.is_absolute():
            raise SystemExit("Existing codex.instructions_file must be absolute")
        try:
            instructions_path = instructions_path.resolve(strict=True)
        except OSError as exc:
            raise SystemExit("Existing codex.instructions_file cannot be resolved") from exc
        control_paths["trusted Codex instructions file"] = instructions_path

for label, control_path in control_paths.items():
    if overlaps(workspace, control_path):
        raise SystemExit(f"{label} must not overlap the Codex working_directory")

print(state)
PY
)"
  TOPOLOGY_VALIDATED=1
  if [ "$SCRATCH" = "1" ]; then
    KEYCHAIN_HOME="$HOME"
  else
    KEYCHAIN_HOME="$("$PYTHON_BIN" - <<'PY'
import os
import pwd
from pathlib import Path

home = Path(pwd.getpwuid(os.getuid()).pw_dir)
if not home.is_absolute() or home.resolve(strict=True) != home:
    raise SystemExit("current user's account HOME is not canonical")
print(home)
PY
)"
  fi
  WORKER_HOME="$STATE_DIR/home"
  CODEX_HOME_DIR="$WORKER_HOME/.codex"
  RUNTIME_TMP="$DISCOPARTY_CODEX_WORKING_DIRECTORY/.discoparty-tmp"
  RUNTIME_VENV=""
  if [ "$SCRATCH" = "1" ]; then
    NATIVE_CODEX_BIN="$CODEX_BIN"
  else
    NATIVE_CODEX_BIN="$REVIEWED_NATIVE_CODEX_BIN"
  fi

  if [ -L "$PLIST_PATH" ]; then
    die "Refusing a symlinked existing LaunchAgent plist: $PLIST_PATH"
  fi
  if [ -e "$PLIST_PATH" ]; then
    [ -f "$PLIST_PATH" ] || \
      die "Existing LaunchAgent plist is not a regular file: $PLIST_PATH"
    ORIGINAL_PLIST_PYTHON="$($PYTHON_BIN - "$PLIST_PATH" <<'PY'
import plistlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    with path.open("rb") as stream:
        data = plistlib.load(stream)
    arguments = data["ProgramArguments"]
    executable = arguments[0]
except (KeyError, IndexError, OSError, TypeError, ValueError, plistlib.InvalidFileException) as exc:
    raise SystemExit("existing Codex LaunchAgent has invalid ProgramArguments") from exc
if not isinstance(arguments, list) or not isinstance(executable, str) or not executable.startswith("/"):
    raise SystemExit("existing Codex LaunchAgent has an invalid Python executable")
print(executable)
PY
)"
  fi
}

set_legacy_paths() {
  LEGACY_REPO_ROOT="$HOME/TheSystem/x_System/Assistant/codex-discord-bridge"
  LEGACY_PLIST_PATH="$HOME/Library/LaunchAgents/$LEGACY_LABEL.plist"
  LEGACY_STATE_DIR="$HOME/Library/Application Support/thesystem/codex-discord"
  LEGACY_DATABASE_PATH="$LEGACY_STATE_DIR/jobs.sqlite3"
  LEGACY_HANDOFF_MARKER="$STATE_DIR/legacy-takeover.json"
}

legacy_label_loaded() {
  "$LAUNCHCTL_BIN" print "gui/$UID/$LEGACY_LABEL" >/dev/null 2>&1
}

legacy_label_disabled() {
  "$LAUNCHCTL_BIN" print-disabled "gui/$UID" 2>/dev/null | \
    grep -Fq "\"$LEGACY_LABEL\" => true"
}

validate_legacy_plist() {
  require_topology_validated
  env -u PYTHONHOME -u PYTHONPATH -u PYTHONPYCACHEPREFIX -u PYTHONUSERBASE \
    PYTHONSAFEPATH=1 "$PYTHON_BIN" - \
    "$LEGACY_PLIST_PATH" "$LEGACY_REPO_ROOT" "$HOME" \
    "$DISCOPARTY_CODEX_GUILD_ID" "$DISCOPARTY_CODEX_CHANNEL_ID" \
    "$DISCOPARTY_CODEX_OWNER_USER_ID" "$DISCOPARTY_CODEX_BOT_USER_ID" \
    "$DISCOPARTY_CODEX_APPLICATION_ID" "$DISCOPARTY_CODEX_WORKING_DIRECTORY" \
    "${DISCOPARTY_CODEX_CHANNEL_TRUST:-public}" <<'PY'
import os
import plistlib
import stat
import sys
from pathlib import Path

(
    plist_raw,
    repo_raw,
    home_raw,
    guild_id,
    channel_id,
    owner_id,
    bot_id,
    application_id,
    workspace_raw,
    channel_trust,
) = sys.argv[1:]
plist = Path(plist_raw)
repo = Path(repo_raw)
home = Path(home_raw).resolve(strict=True)
workspace = Path(workspace_raw).resolve(strict=True)

metadata = plist.lstat()
if (
    stat.S_ISLNK(metadata.st_mode)
    or not stat.S_ISREG(metadata.st_mode)
    or metadata.st_uid != os.getuid()
    or stat.S_IMODE(metadata.st_mode) != 0o600
    or metadata.st_nlink != 1
):
    raise SystemExit(
        "legacy LaunchAgent plist must be a current-user-owned, single-link regular file with mode 600"
    )
repo_metadata = repo.lstat()
if (
    stat.S_ISLNK(repo_metadata.st_mode)
    or not stat.S_ISDIR(repo_metadata.st_mode)
    or repo_metadata.st_uid != os.getuid()
    or stat.S_IMODE(repo_metadata.st_mode) & 0o022
):
    raise SystemExit("legacy bridge repository path is unsafe")
with plist.open("rb") as stream:
    data = plistlib.load(stream)

expected_keys = {
    "Label",
    "ProgramArguments",
    "WorkingDirectory",
    "EnvironmentVariables",
    "StandardOutPath",
    "StandardErrorPath",
    "RunAtLoad",
    "KeepAlive",
    "ThrottleInterval",
}
if set(data) != expected_keys:
    raise SystemExit("legacy LaunchAgent has unexpected or missing top-level keys")

expected_arguments = [
    "/opt/homebrew/bin/python3",
    "-m",
    "codex_discord_bridge.main",
]
if data.get("Label") != "com.thesystem.codex-discord-bridge":
    raise SystemExit("legacy LaunchAgent has an unexpected label")
if data.get("ProgramArguments") != expected_arguments:
    raise SystemExit("legacy LaunchAgent has unexpected ProgramArguments")
if Path(str(data.get("WorkingDirectory", ""))).resolve(strict=True) != repo.resolve(strict=True):
    raise SystemExit("legacy LaunchAgent has an unexpected working directory")

expected_environment = {
    "HOME": str(home),
    "PATH": "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    "PYTHONPATH": str(repo.resolve(strict=True)),
    "PYTHONUNBUFFERED": "1",
    "CODEX_DISCORD_GUILD_ID": guild_id,
    "CODEX_DISCORD_CHANNEL_ID": channel_id,
    "CODEX_DISCORD_OWNER_USER_ID": owner_id,
    "CODEX_DISCORD_BOT_USER_ID": bot_id,
    "CODEX_DISCORD_APPLICATION_ID": application_id,
    "CODEX_DISCORD_ENABLE": "FULL_COMPUTER_ACCESS_ACCEPTED",
    "CODEX_DISCORD_USE_SHARED_LOGIN": "1",
    "CODEX_DISCORD_CHANNEL_TRUST": channel_trust,
    "CODEX_DISCORD_WORKSPACE": str(workspace),
}
if data.get("EnvironmentVariables") != expected_environment:
    raise SystemExit(
        "legacy LaunchAgent environment does not match the reviewed channel-trust deployment"
    )
expected_logs = home / "Library/Logs/TheSystem"
if data.get("StandardOutPath") != str(expected_logs / "codex-discord-bridge.stdout.log"):
    raise SystemExit("legacy LaunchAgent has an unexpected stdout path")
if data.get("StandardErrorPath") != str(expected_logs / "codex-discord-bridge.stderr.log"):
    raise SystemExit("legacy LaunchAgent has an unexpected stderr path")
if data.get("RunAtLoad") is not True:
    raise SystemExit("legacy LaunchAgent must declare RunAtLoad")
if data.get("KeepAlive") != {"Crashed": True, "SuccessfulExit": False}:
    raise SystemExit("legacy LaunchAgent has an unexpected KeepAlive policy")
if data.get("ThrottleInterval") != 10:
    raise SystemExit("legacy LaunchAgent has an unexpected throttle interval")
PY
}

validate_legacy_state() {
  require_topology_validated
  local require_quiescent="${1:-0}"
  case "$require_quiescent" in
    0|1) ;;
    *) die "Internal legacy-state validation mode is invalid." ;;
  esac
  LEGACY_ROOT_CURSOR="$(env -u PYTHONHOME -u PYTHONPATH -u PYTHONPYCACHEPREFIX -u PYTHONUSERBASE \
    PYTHONSAFEPATH=1 "$PYTHON_BIN" - \
    "$LEGACY_STATE_DIR" "$LEGACY_DATABASE_PATH" \
    "$DISCOPARTY_CODEX_GUILD_ID" "$DISCOPARTY_CODEX_CHANNEL_ID" \
    "$DISCOPARTY_CODEX_OWNER_USER_ID" "$require_quiescent" <<'PY'
import os
import sqlite3
import stat
import sys
from pathlib import Path

state = Path(sys.argv[1])
database = Path(sys.argv[2])
guild_id, channel_id, owner_id = sys.argv[3:6]
require_quiescent = sys.argv[6] == "1"
state_metadata = state.lstat()
database_metadata = database.lstat()
if (
    stat.S_ISLNK(state_metadata.st_mode)
    or not stat.S_ISDIR(state_metadata.st_mode)
    or state_metadata.st_uid != os.getuid()
    or stat.S_IMODE(state_metadata.st_mode) != 0o700
):
    raise SystemExit("legacy state directory must be a private, owned real directory")
if (
    stat.S_ISLNK(database_metadata.st_mode)
    or not stat.S_ISREG(database_metadata.st_mode)
    or database_metadata.st_uid != os.getuid()
    or stat.S_IMODE(database_metadata.st_mode) != 0o600
    or database_metadata.st_nlink != 1
):
    raise SystemExit("legacy job ledger must be a private, single-link regular file")
for suffix in ("-wal", "-shm"):
    sidecar = Path(f"{database}{suffix}")
    try:
        sidecar_metadata = sidecar.lstat()
    except FileNotFoundError:
        continue
    if (
        stat.S_ISLNK(sidecar_metadata.st_mode)
        or not stat.S_ISREG(sidecar_metadata.st_mode)
        or sidecar_metadata.st_uid != os.getuid()
        or stat.S_IMODE(sidecar_metadata.st_mode) != 0o600
        or sidecar_metadata.st_nlink != 1
    ):
        raise SystemExit(f"legacy SQLite {suffix} sidecar is unsafe")

required = {
    "jobs": {"event_id", "guild_id", "channel_id", "author_id", "state", "ready"},
    "sessions": {"scope", "thread_id"},
    "deliveries": {"event_id", "chunk_index", "state"},
    "delivery_manifests": {"event_id", "state"},
    "channel_cursors": {"channel_id", "event_id"},
}
uri = f"file:{database}?mode=ro"
with sqlite3.connect(uri, uri=True) as db:
    if db.execute("PRAGMA quick_check").fetchone()[0] != "ok":
        raise SystemExit("legacy job ledger failed SQLite quick_check")
    for table, columns in required.items():
        observed = {str(row[1]) for row in db.execute(f"PRAGMA table_info({table})")}
        if not columns.issubset(observed):
            raise SystemExit(f"legacy job ledger has an incompatible {table} schema")
    foreign_jobs = int(
        db.execute(
            "SELECT COUNT(*) FROM jobs WHERE guild_id<>? OR author_id<>?",
            (guild_id, owner_id),
        ).fetchone()[0]
    )
    if foreign_jobs:
        raise SystemExit("legacy job ledger contains a foreign guild or author binding")
    rows = db.execute(
        "SELECT event_id FROM channel_cursors WHERE channel_id=?", (channel_id,)
    ).fetchall()
    root_job_ids = [
        str(row[0])
        for row in db.execute(
            "SELECT event_id FROM jobs WHERE channel_id=?", (channel_id,)
        )
    ]
    if require_quiescent:
        unfinished_jobs = int(
            db.execute(
                "SELECT COUNT(*) FROM jobs WHERE state IN ('queued','running','uncertain')"
            ).fetchone()[0]
        )
        prepared_deliveries = int(
            db.execute(
                "SELECT COUNT(*) FROM deliveries WHERE state='prepared'"
            ).fetchone()[0]
        )
        prepared_manifests = int(
            db.execute(
                "SELECT COUNT(*) FROM delivery_manifests WHERE state='prepared'"
            ).fetchone()[0]
        )
        if unfinished_jobs or prepared_deliveries or prepared_manifests:
            raise SystemExit(
                "legacy ledger is not quiescent: resolve queued, running, uncertain, "
                "or prepared work before cursor handoff"
            )
if len(rows) != 1:
    raise SystemExit("legacy job ledger must contain exactly one root-channel cursor")
cursor = str(rows[0][0])
if (
    not cursor.isascii()
    or not cursor.isdecimal()
    or not 17 <= len(cursor) <= 20
    or str(int(cursor)) != cursor
    or int(cursor) <= 0
):
    raise SystemExit("legacy root-channel cursor is malformed")
for event_id in root_job_ids:
    if (
        not event_id.isascii()
        or not event_id.isdecimal()
        or not 17 <= len(event_id) <= 20
        or str(int(event_id)) != event_id
        or int(event_id) <= 0
        or int(event_id) > int(cursor)
    ):
        raise SystemExit(
            "legacy root cursor does not cover every accepted root-channel job"
        )
print(cursor)
PY
)" || die "Legacy state failed fail-closed validation."
  [ -n "$LEGACY_ROOT_CURSOR" ] || die "Legacy root-channel cursor is unavailable."
}

validate_completed_legacy_takeover() {
  require_topology_validated
  env -u PYTHONHOME -u PYTHONPATH -u PYTHONPYCACHEPREFIX -u PYTHONUSERBASE \
    PYTHONSAFEPATH=1 "$PYTHON_BIN" - \
    "$LEGACY_HANDOFF_MARKER" "$STATE_DIR" "$LEGACY_ROOT_CURSOR" <<'PY'
import hashlib
import json
import os
import stat
import sys
from pathlib import Path

marker = Path(sys.argv[1])
state = Path(sys.argv[2])
cursor = sys.argv[3]


def require_private_file(path: Path, label: str) -> None:
    metadata = path.lstat()
    if (
        stat.S_ISLNK(metadata.st_mode)
        or not stat.S_ISREG(metadata.st_mode)
        or metadata.st_uid != os.getuid()
        or stat.S_IMODE(metadata.st_mode) != 0o600
        or metadata.st_nlink != 1
    ):
        raise SystemExit(f"{label} is not a private, owned single-link file")


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            value.update(chunk)
    return value.hexdigest()


require_private_file(marker, "completed legacy takeover marker")
payload = json.loads(marker.read_text())
if (
    payload.get("version") != 1
    or payload.get("state") != "new_ready"
    or payload.get("legacy_label") != "com.thesystem.codex-discord-bridge"
    or payload.get("replacement_label") != "com.discoparty.codex-discord-bridge"
    or payload.get("root_cursor") != cursor
):
    raise SystemExit("completed legacy takeover marker does not match the legacy ledger")
backup_value = payload.get("backup_dir")
if not isinstance(backup_value, str) or not backup_value:
    raise SystemExit("completed legacy takeover marker has no backup directory")
backup = Path(backup_value)
backup_metadata = backup.lstat()
if (
    stat.S_ISLNK(backup_metadata.st_mode)
    or not stat.S_ISDIR(backup_metadata.st_mode)
    or backup_metadata.st_uid != os.getuid()
    or stat.S_IMODE(backup_metadata.st_mode) != 0o700
):
    raise SystemExit("completed legacy takeover backup directory is unsafe")
migration_path = state / "migration-backups"
migration_metadata = migration_path.lstat()
if (
    stat.S_ISLNK(migration_metadata.st_mode)
    or not stat.S_ISDIR(migration_metadata.st_mode)
    or migration_metadata.st_uid != os.getuid()
    or stat.S_IMODE(migration_metadata.st_mode) != 0o700
):
    raise SystemExit("completed legacy migration backup root is unsafe")
migration_root = migration_path.resolve(strict=True)
if backup.resolve(strict=True).parent != migration_root:
    raise SystemExit("completed legacy takeover backup escaped its migration root")
database = backup / "jobs.sqlite3"
plist = backup / "com.thesystem.codex-discord-bridge.plist"
manifest_path = backup / "manifest.json"
for path, label in (
    (database, "legacy database backup"),
    (plist, "legacy plist backup"),
    (manifest_path, "legacy backup manifest"),
):
    require_private_file(path, label)
manifest = json.loads(manifest_path.read_text())
if (
    manifest.get("version") != 1
    or manifest.get("legacy_label") != "com.thesystem.codex-discord-bridge"
    or manifest.get("root_cursor") != cursor
    or manifest.get("database_sha256") != digest(database)
    or manifest.get("plist_sha256") != digest(plist)
):
    raise SystemExit("completed legacy takeover backup failed integrity validation")
PY
}

detect_and_validate_legacy() {
  set_legacy_paths
  local plist_present=0 loaded=0 replacement_present=0
  if [ -e "$LEGACY_PLIST_PATH" ] || [ -L "$LEGACY_PLIST_PATH" ]; then
    plist_present=1
  fi
  if legacy_label_loaded; then
    loaded=1
  fi
  if [ "$plist_present" = "0" ] && [ "$loaded" = "0" ]; then
    [ "$TAKE_OVER_LEGACY" != "1" ] || \
      die "--take-over-legacy was requested, but the reviewed legacy bridge is absent."
    return 0
  fi

  LEGACY_DETECTED=1
  if detect_existing_install; then
    replacement_present=1
  fi
  if [ "$loaded" = "0" ] && legacy_label_disabled; then
    LEGACY_PRIOR_DISABLED=1
    if { [ -e "$LEGACY_HANDOFF_MARKER" ] || [ -L "$LEGACY_HANDOFF_MARKER" ]; } && \
        validate_legacy_plist && \
        validate_legacy_state 0 && \
        validate_completed_legacy_takeover; then
      LEGACY_ARCHIVED=1
      LEGACY_VALIDATED=1
      LEGACY_DETECTED=0
      green "  Retained legacy service is a disabled, integrity-checked rollback artifact."
      return 0
    fi
  fi
  if [ "$replacement_present" = "1" ]; then
    [ "$loaded" = "0" ] || \
      die "Both legacy and Disco Party Codex providers are loaded or installed. Refusing an ambiguous takeover."
    legacy_label_disabled || \
      die "The retained legacy label is not disabled; refusing to operate the Disco Party provider beside it."
    die "Both legacy and Disco Party Codex provider footprints exist without a valid completed-takeover record."
  fi
  [ "$TAKE_OVER_LEGACY" = "1" ] || \
    die "Legacy $LEGACY_LABEL is installed or loaded. Refusing a dual-run; validate it and re-run with --take-over-legacy."
  [ "$plist_present" = "1" ] || \
    die "Legacy $LEGACY_LABEL is loaded without its rollback plist."
  LEGACY_PRIOR_LOADED="$loaded"
  if legacy_label_disabled; then
    LEGACY_PRIOR_DISABLED=1
  fi
  validate_legacy_plist
  validate_legacy_state 0
  LEGACY_VALIDATED=1
  green "  Exact legacy service, plist, public-channel policy, and root cursor: validated."
}

prepare_log_directory() {
  require_topology_validated
  env -u PYTHONHOME -u PYTHONPATH -u PYTHONPYCACHEPREFIX -u PYTHONUSERBASE \
    PYTHONSAFEPATH=1 PYTHONDONTWRITEBYTECODE=1 \
    "$PYTHON_BIN" - "$LOG_DIR" <<'PY'
import os
import stat
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    os.mkdir(path, 0o700)
except FileExistsError:
    pass
flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
if hasattr(os, "O_NOFOLLOW"):
    flags |= os.O_NOFOLLOW
descriptor = os.open(path, flags)
try:
    metadata = os.fstat(descriptor)
    if (
        not stat.S_ISDIR(metadata.st_mode)
        or metadata.st_uid != os.getuid()
        or stat.S_IMODE(metadata.st_mode) & 0o022
    ):
        raise SystemExit(
            "Codex logs directory must be current-user-owned and not group/world writable"
        )
    os.fchmod(descriptor, 0o700)
finally:
    os.close(descriptor)
PY
}

validate_log_targets() {
  require_topology_validated
  env -u PYTHONHOME -u PYTHONPATH -u PYTHONPYCACHEPREFIX -u PYTHONUSERBASE \
    PYTHONSAFEPATH=1 PYTHONDONTWRITEBYTECODE=1 \
    "$PYTHON_BIN" - "$LOG_DIR" <<'PY'
import os
import stat
import sys
from pathlib import Path

root = Path(sys.argv[1])
metadata = root.lstat()
if (
    stat.S_ISLNK(metadata.st_mode)
    or not stat.S_ISDIR(metadata.st_mode)
    or metadata.st_uid != os.getuid()
    or stat.S_IMODE(metadata.st_mode) != 0o700
):
    raise SystemExit(
        "Codex logs directory must remain a current-user-owned real directory with mode 700"
    )
for name in (
    "codex-discord-bridge.stdout.log",
    "codex-discord-bridge.stderr.log",
):
    path = root / name
    try:
        target = path.lstat()
    except FileNotFoundError:
        continue
    if (
        stat.S_ISLNK(target.st_mode)
        or not stat.S_ISREG(target.st_mode)
        or target.st_uid != os.getuid()
        or stat.S_IMODE(target.st_mode) & 0o022
        or target.st_nlink != 1
    ):
        raise SystemExit(
            f"Codex log target {name} must be a current-user-owned, single-link regular file and not group/world writable"
        )
PY
}

verify_python_runtime() {
  local root="$1"
  local python_mm="$2"
  local websockets_version="$3"
  local lock_sha256="$4"
  if [ -L "$root" ] || [ ! -d "$root" ]; then
    return 1
  fi
  local runtime_python="$root/bin/python3"
  [ -x "$runtime_python" ] || return 1
  env -u PYTHONHOME -u PYTHONPATH -u PYTHONPYCACHEPREFIX -u PYTHONUSERBASE \
    PIP_CONFIG_FILE=/dev/null \
    PYTHONNOUSERSITE=1 \
    PYTHONSAFEPATH=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    "$runtime_python" - \
      "$root" "$python_mm" "$websockets_version" "$lock_sha256" <<'PY'
import base64
import hashlib
import importlib.metadata
import json
import os
import platform
import re
import stat
import sys
from pathlib import Path

requested_root = Path(sys.argv[1])
python_mm, expected_websockets, lock_sha256 = sys.argv[2:]
root_metadata = requested_root.lstat()
if requested_root.is_symlink() or not stat.S_ISDIR(root_metadata.st_mode):
    raise SystemExit("runtime root must be a real directory")
if root_metadata.st_uid != os.getuid() or stat.S_IMODE(root_metadata.st_mode) != 0o700:
    raise SystemExit("runtime root must be user-owned with mode 700")
root = requested_root.resolve(strict=True)
if Path(sys.prefix).resolve(strict=True) != root or sys.prefix == sys.base_prefix:
    raise SystemExit("runtime Python is not isolated in the expected venv")
if platform.python_implementation() != "CPython":
    raise SystemExit("runtime must use CPython")
if ".".join(map(str, sys.version_info[:2])) != python_mm or sys.version_info < (3, 11):
    raise SystemExit("runtime CPython version does not match its identity")
if platform.system() != "Darwin" or platform.machine() != "arm64":
    raise SystemExit("runtime platform must be Apple Silicon macOS")

import websockets

module = Path(websockets.__file__).resolve(strict=True)
if websockets.__version__ != expected_websockets or not module.is_relative_to(root):
    raise SystemExit("runtime websockets package does not match its identity")

allowed = {"pip", "setuptools", "websockets"}
seen: set[str] = set()
for distribution in importlib.metadata.distributions():
    raw_name = distribution.metadata.get("Name", "")
    name = re.sub(r"[-_.]+", "-", raw_name).lower()
    if not name or name not in allowed:
        raise SystemExit(f"unexpected runtime distribution: {raw_name or '<unnamed>'}")
    seen.add(name)
    for entry in distribution.files or ():
        candidate_path = Path(distribution.locate_file(entry))
        if not candidate_path.exists():
            if entry.suffix == ".pyc" and name != "websockets":
                continue
            raise SystemExit(f"runtime distribution file is missing: {entry}")
        candidate = candidate_path.resolve(strict=True)
        if not candidate.is_relative_to(root):
            raise SystemExit(f"runtime distribution file escapes venv: {entry}")
        if not candidate.is_file():
            continue
        recorded_hash = entry.hash
        if recorded_hash is None:
            if str(entry).endswith(".dist-info/RECORD") or (
                entry.suffix == ".pyc" and name != "websockets"
            ):
                continue
            raise SystemExit(f"runtime distribution file has no recorded hash: {entry}")
        digest = hashlib.new(recorded_hash.mode, candidate.read_bytes()).digest()
        actual = base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
        if actual != recorded_hash.value:
            raise SystemExit(f"runtime distribution file failed hash verification: {entry}")
if "pip" not in seen or "websockets" not in seen:
    raise SystemExit("runtime is missing a required distribution")

manifest = root / "discoparty-runtime.json"
manifest_metadata = manifest.lstat()
if (
    manifest.is_symlink()
    or not stat.S_ISREG(manifest_metadata.st_mode)
    or manifest_metadata.st_uid != os.getuid()
    or stat.S_IMODE(manifest_metadata.st_mode) != 0o600
):
    raise SystemExit("runtime manifest must be a private regular file")
expected_manifest = {
    "version": 2,
    "python_implementation": "CPython",
    "python_major_minor": python_mm,
    "platform": "Darwin-arm64",
    "requirements_sha256": lock_sha256,
    "websockets": expected_websockets,
}
if json.loads(manifest.read_text(encoding="utf-8")) != expected_manifest:
    raise SystemExit("runtime manifest does not match its immutable identity")
PY
}

prepare_python_runtime() {
  require_topology_validated
  if [ "$SCRATCH" = "1" ]; then
    "$PYTHON_BIN" -c 'import websockets' >/dev/null 2>&1 || \
      die "Scratch Python fixture cannot import websockets."
    return 0
  fi
  blue "Preparing the private hash-locked Python runtime."
  local lock_file="$REPO_ROOT/requirements-macos-arm64.lock"
  [ -f "$lock_file" ] || die "Missing Apple Silicon runtime lock: $lock_file"
  local identity=""
  identity="$(env -u PYTHONHOME -u PYTHONPATH -u PYTHONPYCACHEPREFIX -u PYTHONUSERBASE \
    PYTHONSAFEPATH=1 "$PYTHON_BIN" - "$lock_file" <<'PY'
import hashlib
import platform
import re
import sys
from pathlib import Path

lock_path = Path(sys.argv[1])
if platform.python_implementation() != "CPython":
    raise SystemExit("the private runtime requires CPython")
if sys.version_info < (3, 11):
    raise SystemExit("the private runtime requires CPython 3.11 or newer")
versions = []
for line in lock_path.read_text(encoding="utf-8").splitlines():
    requirement = line.strip().split(maxsplit=1)[0] if line.strip() else ""
    if requirement.startswith("websockets=="):
        versions.append(requirement.removeprefix("websockets=="))
if len(versions) != 1 or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+!-]*", versions[0]):
    raise SystemExit("runtime lock must contain exactly one safe websockets pin")
print(
    ".".join(map(str, sys.version_info[:2])),
    versions[0],
    hashlib.sha256(lock_path.read_bytes()).hexdigest(),
    sep="\t",
)
PY
)"
  IFS=$'\t' read -r \
    RUNTIME_PYTHON_MM RUNTIME_WEBSOCKETS_VERSION RUNTIME_LOCK_SHA256 <<< "$identity"
  [ -n "$RUNTIME_PYTHON_MM" ] && \
    [ -n "$RUNTIME_WEBSOCKETS_VERSION" ] && \
    [ "${#RUNTIME_LOCK_SHA256}" = "64" ] || \
    die "Could not derive the private runtime identity from the lock file."

  RUNTIME_VENV="$STATE_DIR/runtime-venv-cpython-${RUNTIME_PYTHON_MM}-websockets-${RUNTIME_WEBSOCKETS_VERSION}-${RUNTIME_LOCK_SHA256}"
  local runtime_python="$RUNTIME_VENV/bin/python3"
  if [ -L "$RUNTIME_VENV" ] || { [ -e "$RUNTIME_VENV" ] && [ ! -d "$RUNTIME_VENV" ]; }; then
    die "Refusing an unsafe runtime venv path: $RUNTIME_VENV"
  fi
  if [ -d "$RUNTIME_VENV" ]; then
    verify_python_runtime \
      "$RUNTIME_VENV" "$RUNTIME_PYTHON_MM" \
      "$RUNTIME_WEBSOCKETS_VERSION" "$RUNTIME_LOCK_SHA256" || \
      die "Existing immutable Python runtime failed exact verification. It was not modified."
    PYTHON_BIN="$runtime_python"
    green "  Reused verified CPython $RUNTIME_PYTHON_MM and websockets $RUNTIME_WEBSOCKETS_VERSION runtime."
    return 0
  fi
  if [ -n "$ORIGINAL_PLIST_PYTHON" ] && [ "$ORIGINAL_PLIST_PYTHON" = "$runtime_python" ]; then
    die "The existing LaunchAgent references a missing runtime. Refusing to create or mutate that path."
  fi

  local runtime_basename="${RUNTIME_VENV##*/}"
  RUNTIME_VENV_TEMP="$(mktemp -d "$STATE_DIR/.${runtime_basename}.tmp.XXXXXX")"
  chmod 700 "$RUNTIME_VENV_TEMP"
  env -u PYTHONHOME -u PYTHONPATH -u PYTHONPYCACHEPREFIX -u PYTHONUSERBASE \
    PYTHONSAFEPATH=1 PYTHONDONTWRITEBYTECODE=1 \
    "$PYTHON_BIN" -m venv "$RUNTIME_VENV_TEMP"
  local staged_python="$RUNTIME_VENV_TEMP/bin/python3"
  [ -x "$staged_python" ] || die "Private Python runtime staging failed."
  env -u PYTHONHOME -u PYTHONPATH -u PYTHONPYCACHEPREFIX -u PYTHONUSERBASE \
    PIP_CONFIG_FILE=/dev/null PYTHONNOUSERSITE=1 \
    PYTHONSAFEPATH=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    "$staged_python" -m pip install \
      --isolated \
      --disable-pip-version-check \
      --no-input \
      --no-compile \
      --require-hashes \
      --only-binary=:all: \
      --index-url https://pypi.org/simple \
      -r "$lock_file" >/dev/null
  env -u PYTHONHOME -u PYTHONPATH -u PYTHONPYCACHEPREFIX -u PYTHONUSERBASE \
    PYTHONSAFEPATH=1 "$staged_python" - \
    "$RUNTIME_VENV_TEMP" "$RUNTIME_PYTHON_MM" \
    "$RUNTIME_WEBSOCKETS_VERSION" "$RUNTIME_LOCK_SHA256" <<'PY'
import json
import os
import sys
from pathlib import Path

root = Path(sys.argv[1])
record = {
    "version": 2,
    "python_implementation": "CPython",
    "python_major_minor": sys.argv[2],
    "platform": "Darwin-arm64",
    "requirements_sha256": sys.argv[4],
    "websockets": sys.argv[3],
}
target = root / "discoparty-runtime.json"
payload = (json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n").encode()
flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
if hasattr(os, "O_NOFOLLOW"):
    flags |= os.O_NOFOLLOW
descriptor = os.open(target, flags, 0o600)
with os.fdopen(descriptor, "wb") as stream:
    stream.write(payload)
    stream.flush()
    os.fsync(stream.fileno())
PY
  verify_python_runtime \
    "$RUNTIME_VENV_TEMP" "$RUNTIME_PYTHON_MM" \
    "$RUNTIME_WEBSOCKETS_VERSION" "$RUNTIME_LOCK_SHA256" || \
    die "Staged private Python runtime failed exact verification."

  env -u PYTHONHOME -u PYTHONPATH -u PYTHONPYCACHEPREFIX -u PYTHONUSERBASE \
    PYTHONSAFEPATH=1 "$PYTHON_BIN" - \
    "$RUNTIME_VENV_TEMP" "$RUNTIME_VENV" <<'PY'
import ctypes
import errno
import os
import platform
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])
if source.parent != target.parent:
    raise SystemExit("runtime staging directory must be a sibling of its target")
if target.exists() or target.is_symlink():
    raise SystemExit("immutable runtime target appeared during installation")
if platform.system() != "Darwin":
    raise SystemExit("exclusive runtime publication requires macOS")
libc = ctypes.CDLL(None, use_errno=True)
renamex_np = libc.renamex_np
renamex_np.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
renamex_np.restype = ctypes.c_int
RENAME_EXCL = 0x00000004
if renamex_np(os.fsencode(source), os.fsencode(target), RENAME_EXCL) != 0:
    error = ctypes.get_errno()
    raise OSError(error, os.strerror(error), str(target))
directory = os.open(target.parent, os.O_RDONLY)
try:
    try:
        os.fsync(directory)
    except OSError as exc:
        if exc.errno not in (errno.EINVAL, getattr(errno, "ENOTSUP", errno.EINVAL)):
            raise
finally:
    os.close(directory)
PY
  RUNTIME_VENV_TEMP=""
  RUNTIME_VENV_CREATED=1
  verify_python_runtime \
    "$RUNTIME_VENV" "$RUNTIME_PYTHON_MM" \
    "$RUNTIME_WEBSOCKETS_VERSION" "$RUNTIME_LOCK_SHA256" || \
    die "Published private Python runtime failed exact verification."
  PYTHON_BIN="$runtime_python"
  green "  Published CPython $RUNTIME_PYTHON_MM and websockets $RUNTIME_WEBSOCKETS_VERSION runtime atomically."
}

prepare_isolated_codex() {
  require_topology_validated
  blue "Creating the isolated Codex home and reviewed policy."
  PYTHONPATH="$REPO_ROOT" "$PYTHON_BIN" - \
    "$CODEX_HOME_DIR" "$DISCOPARTY_CODEX_WORKING_DIRECTORY" <<'PY'
import sys
from pathlib import Path

from codex_discord_bridge.codex_policy import (
    prepare_isolated_directories,
    prepare_runtime_tmp,
)

prepare_isolated_directories(Path(sys.argv[1]))
prepare_runtime_tmp(Path(sys.argv[2]))
PY
  if [ -L "$CODEX_HOME_DIR/config.toml" ]; then
    die "Refusing to replace symlinked isolated Codex config."
  fi
  if [ -f "$CODEX_HOME_DIR/config.toml" ]; then
    CODEX_CONFIG_EXISTED=1
    CODEX_CONFIG_BACKUP="$(mktemp "${TMPDIR:-/tmp}/discoparty-codex-home-config.XXXXXX")"
    cp -p "$CODEX_HOME_DIR/config.toml" "$CODEX_CONFIG_BACKUP"
  elif [ -e "$CODEX_HOME_DIR/config.toml" ]; then
    die "Isolated Codex config path is not a regular file."
  fi
  CODEX_CONFIG_MUTATED=1
  local safe_mode="false"
  [ "$DISCOPARTY_CODEX_SANDBOX_MODE" = "workspace-write" ] && safe_mode="true"
  PYTHONPATH="$REPO_ROOT" "$PYTHON_BIN" - \
    "$CODEX_HOME_DIR" "$DISCOPARTY_CODEX_WORKING_DIRECTORY" "$safe_mode" <<'PY'
import sys
from pathlib import Path

from codex_discord_bridge.codex_policy import write_isolated_config

write_isolated_config(
    Path(sys.argv[1]),
    Path(sys.argv[2]),
    sys.argv[3] == "true",
)
PY
  if [ -L "$CODEX_HOME_DIR/hooks.json" ]; then
    die "Refusing to replace symlinked isolated Codex hooks."
  fi
  if [ -f "$CODEX_HOME_DIR/hooks.json" ]; then
    CODEX_HOOKS_EXISTED=1
    CODEX_HOOKS_BACKUP="$(mktemp "${TMPDIR:-/tmp}/discoparty-codex-home-hooks.XXXXXX")"
    cp -p "$CODEX_HOME_DIR/hooks.json" "$CODEX_HOOKS_BACKUP"
  elif [ -e "$CODEX_HOME_DIR/hooks.json" ]; then
    die "Isolated Codex hooks path is not a regular file."
  fi
  CODEX_HOOKS_MUTATED=1
  PYTHONPATH="$REPO_ROOT" "$PYTHON_BIN" - \
    "$CODEX_HOME_DIR" "$SHARED_SKILLS_ROOT" \
    "$DISCOPARTY_CODEX_WORKING_DIRECTORY" <<'PY'
import sys
from pathlib import Path

from codex_discord_bridge.shared_hooks import bind_shared_hooks, write_hook_bridge

codex_home, skills_root, workspace = map(Path, sys.argv[1:])
binding = bind_shared_hooks(
    skills_root.parent.parent,
    workspace=workspace,
)
write_hook_bridge(codex_home, binding)
PY
  green "  Isolated HOME, CODEX_HOME, policy config, and canonical hooks: OK"
}

prepare_shared_skill_bridge() {
  require_topology_validated
  blue "Binding Codex to the canonical shared Vault skills."
  if [ ! -e "$CODEX_HOME_DIR/skills" ] && [ ! -L "$CODEX_HOME_DIR/skills" ]; then
    SKILL_BRIDGE_CREATED=1
  fi
  if ! PYTHONPATH="$REPO_ROOT" "$PYTHON_BIN" - \
    "$CODEX_HOME_DIR" "$SHARED_SKILLS_ROOT" <<'PY'
import sys
from pathlib import Path

from codex_discord_bridge.shared_skills import (
    bind_shared_skills,
    prepare_skill_bridge,
    validate_skill_bridge,
)

codex_home, root = map(Path, sys.argv[1:])
prepare_skill_bridge(codex_home, root)
binding = bind_shared_skills(root)
validate_skill_bridge(codex_home, binding)
PY
  then
    SKILL_BRIDGE_CREATED=0
    die "Canonical shared Vault skill bridge failed validation."
  fi
  green "  ELI5 and vinaytalks canonical skill links: OK"
}

prepare_vault_policy_seal() {
  require_topology_validated
  blue "Sealing the canonical Vault P0 policy for both orchestrators."
  PYTHONPATH="$REPO_ROOT" "$PYTHON_BIN" - \
    "$SHARED_SKILLS_ROOT" "$STATE_DIR" "$DISCOPARTY_CODEX_WORKING_DIRECTORY" <<'PY'
import sys
from pathlib import Path

from conversations.vault_policy import seal_vault_policy

skills_root, state_dir, workspace = map(Path, sys.argv[1:])
seal_vault_policy(
    vault_root=skills_root.parent.parent,
    snapshot_path=state_dir / "policy/vault-p0.md",
    runtime_root=state_dir,
    workspace=workspace,
)
PY
  green "  Canonical Vault P0 policy snapshot and hashes: OK"
}

verify_reviewed_codex_package() {
  blue "Verifying the reviewed official Codex CLI package."
  if [ "$SCRATCH" = "1" ]; then
    local version
    version="$(env -u OPENAI_API_KEY HOME="$KEYCHAIN_HOME" CODEX_HOME="$CODEX_HOME_DIR" \
      TMPDIR="$RUNTIME_TMP" "$NATIVE_CODEX_BIN" --version 2>&1)"
    [ "$version" = "$EXPECTED_CODEX_VERSION" ] || \
      die "Codex CLI must be exactly $EXPECTED_CODEX_VERSION (found: $version)."
  else
    PYTHONPATH="$REPO_ROOT" "$PYTHON_BIN" - \
      "$CODEX_BIN" "$WORKER_HOME" "$CODEX_HOME_DIR" "$RUNTIME_TMP" <<'PY'
import sys
from pathlib import Path

from codex_discord_bridge.codex_auth import (
    require_supported_cli,
    require_supported_protocol,
)

binary, worker_home, codex_home, tmp_dir = map(Path, sys.argv[1:])
require_supported_cli(
    binary, worker_home, codex_home=codex_home, tmp_dir=tmp_dir
)
require_supported_protocol(
    binary, worker_home, codex_home=codex_home, tmp_dir=tmp_dir
)
PY
  fi
  green "  $EXPECTED_CODEX_VERSION native binary and App Server schema: OK"
}

reject_isolated_auth_artifacts() {
  env -u PYTHONHOME -u PYTHONPATH -u PYTHONPYCACHEPREFIX -u PYTHONUSERBASE \
    PYTHONSAFEPATH=1 PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$REPO_ROOT" \
    "$PYTHON_BIN" - "$CODEX_HOME_DIR" <<'PY'
import sys
from pathlib import Path

from codex_discord_bridge.codex_auth import reject_filesystem_credentials

reject_filesystem_credentials(Path(sys.argv[1]))
PY
}

ensure_isolated_chatgpt_login() {
  require_topology_validated
  blue "Checking the isolated ChatGPT subscription login."
  reject_isolated_auth_artifacts || \
    die "Filesystem Codex credentials are forbidden; the installer will not delete or migrate them."
  local login_status=""
  login_status="$(env -u OPENAI_API_KEY HOME="$KEYCHAIN_HOME" CODEX_HOME="$CODEX_HOME_DIR" \
    TMPDIR="$RUNTIME_TMP" "$NATIVE_CODEX_BIN" login status 2>&1 || true)"
  if ! printf '%s\n' "$login_status" | grep -Fq "Logged in using ChatGPT"; then
    if [ "$NON_INTERACTIVE" = "1" ]; then
      die "The isolated CODEX_HOME is not logged in. Run with HOME='$KEYCHAIN_HOME' CODEX_HOME='$CODEX_HOME_DIR' '$NATIVE_CODEX_BIN' login, then retry."
    fi
    say "  Your normal Codex login is intentionally not reused. Complete the official ChatGPT browser login."
    env -u OPENAI_API_KEY HOME="$KEYCHAIN_HOME" CODEX_HOME="$CODEX_HOME_DIR" \
      TMPDIR="$RUNTIME_TMP" "$NATIVE_CODEX_BIN" login
    login_status="$(env -u OPENAI_API_KEY HOME="$KEYCHAIN_HOME" CODEX_HOME="$CODEX_HOME_DIR" \
      TMPDIR="$RUNTIME_TMP" "$NATIVE_CODEX_BIN" login status 2>&1 || true)"
  fi
  printf '%s\n' "$login_status" | grep -Fq "Logged in using ChatGPT" || \
    die "The isolated Codex login is not a managed ChatGPT subscription login."
  reject_isolated_auth_artifacts || \
    die "ChatGPT login created a forbidden filesystem credential artifact. Keyring-only mode is required."
  green "  Isolated CODEX_HOME with macOS Keychain ChatGPT subscription login: OK"
}

detect_existing_install() {
  [ -f "$PLIST_PATH" ] || "$LAUNCHCTL_BIN" print "gui/$UID/$LABEL" >/dev/null 2>&1
}

handle_existing_install() {
  if ! detect_existing_install || [ "$REINSTALL" = "1" ]; then
    return 0
  fi
  if [ "$NON_INTERACTIVE" = "1" ]; then
    die "The Codex provider is already installed. Re-run with --reinstall."
  fi
  local choice=""
  read -r -p "Codex provider already installed. [r]einstall, [s]kip, or [u]ninstall? [r/s/u]: " choice
  case "$choice" in
    r|R) REINSTALL=1 ;;
    s|S) say "Skipping Codex installation."; exit 0 ;;
    u|U) exec "$SCRIPT_DIR/uninstall.sh" --codex --tmux-session "$TMUX_SESSION" ;;
    *) die "Choose r, s, or u." ;;
  esac
}

resolve_bot_token() {
  blue "Resolving the dedicated Codex Discord bot token."
  local existing=""
  existing="$($SECURITY_BIN find-generic-password \
    -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null || true)"
  if [ -n "$existing" ]; then
    OLD_KEYCHAIN_TOKEN="$existing"
    OLD_KEYCHAIN_PRESENT=1
  fi

  if [ "$IMPORT_LEGACY_TOKEN" = "1" ]; then
    [ "$LEGACY_VALIDATED" = "1" ] || \
      die "Legacy Keychain import requires a validated legacy deployment."
    LEGACY_KEYCHAIN_TOKEN="$($SECURITY_BIN find-generic-password \
      -s "$LEGACY_KEYCHAIN_SERVICE" -a "$LEGACY_KEYCHAIN_ACCOUNT" -w 2>/dev/null || true)"
    [ -n "$LEGACY_KEYCHAIN_TOKEN" ] || \
      die "The exact legacy Codex Discord Keychain item is unavailable."
    [[ "$LEGACY_KEYCHAIN_TOKEN" != *[[:space:]]* ]] || \
      die "The legacy Codex Discord token is malformed."
    NEW_CODEX_TOKEN="$LEGACY_KEYCHAIN_TOKEN"
    say "  Importing the validated legacy Codex token directly between Keychain items."
  fi

  if [ -n "$NEW_CODEX_TOKEN" ]; then
    :
  elif [ -n "$existing" ] && [ "$NON_INTERACTIVE" = "1" ]; then
    NEW_CODEX_TOKEN="$existing"
    say "  Reusing $KEYCHAIN_SERVICE/$KEYCHAIN_ACCOUNT."
  elif [ -n "$existing" ]; then
    local reuse=""
    read -r -p "Reuse existing Codex bot token from Keychain? [Y/n]: " reuse
    case "$reuse" in
      n|N|no|No|NO) ;;
      *) NEW_CODEX_TOKEN="$existing" ;;
    esac
  fi

  if [ -z "$NEW_CODEX_TOKEN" ]; then
    [ "$NON_INTERACTIVE" != "1" ] || \
      die "An existing $KEYCHAIN_SERVICE/$KEYCHAIN_ACCOUNT Keychain entry is required in --non-interactive mode."
    read -r -s -p "Paste the dedicated Codex Discord bot token: " NEW_CODEX_TOKEN
    say
  fi
  [ -n "$NEW_CODEX_TOKEN" ] || die "The Codex Discord bot token cannot be empty."
  [[ "$NEW_CODEX_TOKEN" != *[[:space:]]* ]] || \
    die "The Codex Discord bot token cannot contain whitespace."
  local claude_token=""
  claude_token="$($SECURITY_BIN find-generic-password \
    -s "$KEYCHAIN_SERVICE" -a "discord-bot-token" -w 2>/dev/null || true)"
  if [ -n "$claude_token" ] && [ "$NEW_CODEX_TOKEN" = "$claude_token" ]; then
    die "Claude and Codex must use different Discord bot tokens."
  fi
  claude_token=""
}

store_bot_token() {
  require_topology_validated
  blue "Storing the Codex Discord bot token in macOS Keychain."
  KEYCHAIN_MUTATED=1
  printf '%s\n' "$NEW_CODEX_TOKEN" | \
    "$SECURITY_BIN" add-generic-password \
      -s "$KEYCHAIN_SERVICE" \
      -a "$KEYCHAIN_ACCOUNT" \
      -U -w >/dev/null
  local stored=""
  stored="$($SECURITY_BIN find-generic-password \
    -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null || true)"
  [ "$stored" = "$NEW_CODEX_TOKEN" ] || \
    die "The Codex Discord bot token failed Keychain readback verification."
  stored=""
  green "  Stored at service=$KEYCHAIN_SERVICE account=$KEYCHAIN_ACCOUNT."

  # Preflight must prove that the bridge can read Keychain. It must not take
  # the token from the installer environment.
  unset DISCOPARTY_CODEX_DISCORD_BOT_TOKEN || true
}

backup_config() {
  require_topology_validated
  if [ -L "$CONFIG_PATH" ]; then
    die "Refusing to replace symlinked config: $CONFIG_PATH"
  fi
  if [ -e "$CONFIG_PATH" ] && [ ! -f "$CONFIG_PATH" ]; then
    die "Config path is not a regular file: $CONFIG_PATH"
  fi
  if [ -f "$CONFIG_PATH" ]; then
    env -u PYTHONHOME -u PYTHONPATH -u PYTHONPYCACHEPREFIX -u PYTHONUSERBASE \
      PYTHONSAFEPATH=1 PYTHONDONTWRITEBYTECODE=1 \
      "$PYTHON_BIN" - "$CONFIG_PATH" <<'PY'
import os
import stat
import sys
from pathlib import Path

path = Path(sys.argv[1])
metadata = path.lstat()
if (
    stat.S_ISLNK(metadata.st_mode)
    or not stat.S_ISREG(metadata.st_mode)
    or metadata.st_uid != os.getuid()
    or stat.S_IMODE(metadata.st_mode) & 0o022
    or metadata.st_nlink != 1
):
    raise SystemExit(
        "existing Disco Party config must be current-user-owned, single-link, regular, and not group/world writable"
    )
PY
    CONFIG_EXISTED=1
    CONFIG_BACKUP="$(mktemp "${TMPDIR:-/tmp}/discoparty-codex-config.XXXXXX")"
    cp -p "$CONFIG_PATH" "$CONFIG_BACKUP"
  else
    cp "$REPO_ROOT/config.example.toml" "$CONFIG_PATH"
    chmod 600 "$CONFIG_PATH"
  fi
}

update_codex_config() {
  blue "Merging the [codex] table into config.toml without changing Claude settings."
  backup_config
  CONFIG_MUTATED=1

  DISCOPARTY_INSTALL_GUILD_ID="$DISCOPARTY_CODEX_GUILD_ID" \
  DISCOPARTY_INSTALL_CHANNEL_ID="$DISCOPARTY_CODEX_CHANNEL_ID" \
  DISCOPARTY_INSTALL_OWNER_ID="$DISCOPARTY_CODEX_OWNER_USER_ID" \
  DISCOPARTY_INSTALL_BOT_ID="$DISCOPARTY_CODEX_BOT_USER_ID" \
  DISCOPARTY_INSTALL_APPLICATION_ID="$DISCOPARTY_CODEX_APPLICATION_ID" \
  DISCOPARTY_INSTALL_CHANNEL_TRUST="$DISCOPARTY_CODEX_CHANNEL_TRUST" \
  DISCOPARTY_INSTALL_WORKING_DIRECTORY="$DISCOPARTY_CODEX_WORKING_DIRECTORY" \
  DISCOPARTY_INSTALL_STATE_DIR="$STATE_DIR" \
  DISCOPARTY_INSTALL_CODEX_HOME="$CODEX_HOME_DIR" \
  DISCOPARTY_INSTALL_CODEX_BIN="$CODEX_BIN" \
  DISCOPARTY_INSTALL_SANDBOX_MODE="$DISCOPARTY_CODEX_SANDBOX_MODE" \
  DISCOPARTY_INSTALL_FULL_ACCESS="$DISCOPARTY_CODEX_FULL_ACCESS_BOOL" \
  DISCOPARTY_INSTALL_SHARED_SKILLS_ROOT="$SHARED_SKILLS_ROOT" \
  "$PYTHON_BIN" - "$CONFIG_PATH" <<'PY'
import json
import os
import re
import stat
import sys
import tempfile
import tomllib
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
parsed = tomllib.loads(original) if original else {}
existing_codex = parsed.get("codex", {})
if not isinstance(existing_codex, dict):
    raise SystemExit("existing codex config must be a TOML table")
lines = original.splitlines(keepends=True)
header = re.compile(r"^\s*\[([^\]]+)\]\s*(?:#.*)?$")
codex_headers = [
    index
    for index, line in enumerate(lines)
    if (match := header.match(line.rstrip("\r\n"))) and match.group(1).strip() == "codex"
]
if len(codex_headers) > 1:
    raise SystemExit("config.toml contains more than one [codex] table")

def q(name: str) -> str:
    return json.dumps(os.environ[name], ensure_ascii=False)

block_lines = [
        "[codex]",
        "enabled = true",
        f"guild_id = {q('DISCOPARTY_INSTALL_GUILD_ID')}",
        f"channel_id = {q('DISCOPARTY_INSTALL_CHANNEL_ID')}",
        f"owner_user_id = {q('DISCOPARTY_INSTALL_OWNER_ID')}",
        f"bot_user_id = {q('DISCOPARTY_INSTALL_BOT_ID')}",
        f"application_id = {q('DISCOPARTY_INSTALL_APPLICATION_ID')}",
        f"channel_trust = {q('DISCOPARTY_INSTALL_CHANNEL_TRUST')}",
        f"working_directory = {q('DISCOPARTY_INSTALL_WORKING_DIRECTORY')}",
        f"state_dir = {q('DISCOPARTY_INSTALL_STATE_DIR')}",
        f"codex_home = {q('DISCOPARTY_INSTALL_CODEX_HOME')}",
        f"codex_bin = {q('DISCOPARTY_INSTALL_CODEX_BIN')}",
        f"sandbox_mode = {q('DISCOPARTY_INSTALL_SANDBOX_MODE')}",
        f"full_computer_access_accepted = {os.environ['DISCOPARTY_INSTALL_FULL_ACCESS']}",
        f"shared_skills_root = {q('DISCOPARTY_INSTALL_SHARED_SKILLS_ROOT')}",
        'keychain_service = "discoparty-secret"',
        'keychain_account = "discord-bot-token-codex"',
]

if "instructions_file" in existing_codex:
    instructions_file = existing_codex["instructions_file"]
    if not isinstance(instructions_file, str) or not instructions_file:
        raise SystemExit("codex.instructions_file must be a non-empty string")
    block_lines.append(
        "instructions_file = " + json.dumps(instructions_file, ensure_ascii=False)
    )

integer_keys = (
    "max_messages_per_minute",
    "max_messages_per_hour",
    "max_concurrent_workers",
    "max_pending_jobs",
    "max_input_chars",
    "retention_days",
    "max_database_bytes",
)
for key in integer_keys:
    if key not in existing_codex:
        continue
    value = existing_codex[key]
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise SystemExit(f"codex.{key} must be a positive integer")
    if key == "max_concurrent_workers" and not 1 <= value <= 4:
        raise SystemExit("codex.max_concurrent_workers must be between 1 and 4")
    block_lines.append(f"{key} = {value}")

block_lines.append("")
block = "\n".join(block_lines)

if codex_headers:
    start = codex_headers[0]
    end = len(lines)
    for index in range(start + 1, len(lines)):
        if header.match(lines[index].rstrip("\r\n")):
            end = index
            break
    updated = "".join(lines[:start]) + block + "".join(lines[end:])
else:
    separator = "" if not original or original.endswith("\n\n") else ("\n" if original.endswith("\n") else "\n\n")
    updated = original + separator + block

mode = stat.S_IMODE(path.stat().st_mode)
with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as handle:
    temp_path = Path(handle.name)
    handle.write(updated)
    handle.flush()
    os.fsync(handle.fileno())
os.chmod(temp_path, mode)
os.replace(temp_path, path)
PY

  DISCOPARTY_CONFIG="$CONFIG_PATH" PYTHONPATH="$REPO_ROOT" \
    "$PYTHON_BIN" -c 'import tomllib, sys; tomllib.load(open(sys.argv[1], "rb"))' "$CONFIG_PATH"
  green "  Updated only the [codex] provider table in $CONFIG_PATH."
}

run_preflight() {
  blue "Running the Codex provider preflight before launchd bootstrap."
  # The full-access phrase is installer confirmation, not a runtime Boolean.
  # The config now contains the validated true/false value, so do not let the
  # confirmation environment variable override it in conversations.config.
  env -u OPENAI_API_KEY -u CODEX_HOME \
    -u DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED \
    HOME="$HOME" \
    PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    PYTHONPATH="$REPO_ROOT" \
    DISCOPARTY_CONFIG="$CONFIG_PATH" \
    "$PYTHON_BIN" -m codex_discord_bridge.preflight
  green "  Codex subscription, CLI protocol, Discord identity, and channel checks passed."
}

backup_plist() {
  if [ "$PLIST_SNAPSHOTTED" = "1" ]; then
    return 0
  fi
  mkdir -p "$HOME/Library/LaunchAgents"
  if [ -L "$PLIST_PATH" ]; then
    die "Refusing to replace symlinked LaunchAgent plist: $PLIST_PATH"
  fi
  if [ -f "$PLIST_PATH" ]; then
    PLIST_EXISTED=1
    PLIST_BACKUP="$(mktemp "${TMPDIR:-/tmp}/discoparty-codex-plist.XXXXXX")"
    cp -p "$PLIST_PATH" "$PLIST_BACKUP"
  fi
  PLIST_SNAPSHOTTED=1
}

quiesce_existing_agent() {
  if [ "$SCRATCH" = "1" ]; then
    return 0
  fi
  if ! "$LAUNCHCTL_BIN" print "gui/$UID/$LABEL" >/dev/null 2>&1; then
    return 0
  fi

  [ -f "$PLIST_PATH" ] || \
    die "$LABEL is loaded but its prior plist is unavailable; refusing a reinstall without a rollback source."
  backup_plist

  blue "Quiescing the existing $LABEL before changing shared Codex state."
  if ! "$LAUNCHCTL_BIN" bootout "gui/$UID/$LABEL" >/dev/null 2>&1; then
    if "$LAUNCHCTL_BIN" print "gui/$UID/$LABEL" >/dev/null 2>&1; then
      die "Could not quiesce the existing $LABEL; no Codex state was changed."
    fi
    PRIOR_AGENT_QUIESCED=1
    die "launchctl reported a quiesce failure after $LABEL stopped; reinstall aborted so the prior agent can be restarted."
  fi
  PRIOR_AGENT_QUIESCED=1
  if "$LAUNCHCTL_BIN" print "gui/$UID/$LABEL" >/dev/null 2>&1; then
    die "$LABEL remained loaded after launchctl bootout; refusing to mutate shared Codex state."
  fi
  green "  Existing $LABEL is stopped and its prior plist is snapshotted."
}

render_plist() {
  validate_log_targets
  blue "Rendering the dedicated Codex LaunchAgent."
  local template="$REPO_ROOT/launchd/templates/com.discoparty.codex-discord-bridge.plist.template"
  [ -r "$template" ] || die "LaunchAgent template not found: $template"
  backup_plist
  PLIST_MUTATED=1

  DISCOPARTY_INSTALL_LABEL="$LABEL" \
  DISCOPARTY_INSTALL_REPO_ROOT="$REPO_ROOT" \
  DISCOPARTY_INSTALL_HOME="$HOME" \
  DISCOPARTY_INSTALL_PYTHON_BIN="$PYTHON_BIN" \
  DISCOPARTY_INSTALL_CONFIG_PATH="$CONFIG_PATH" \
  DISCOPARTY_INSTALL_LOG_DIR="$LOG_DIR" \
  "$PYTHON_BIN" - "$template" "$PLIST_PATH" <<'PY'
import os
import re
import sys
import tempfile
from pathlib import Path
from xml.sax.saxutils import escape

template = Path(sys.argv[1])
target = Path(sys.argv[2])
data = template.read_text()
replacements = {
    "__LABEL__": os.environ["DISCOPARTY_INSTALL_LABEL"],
    "__REPO_ROOT__": os.environ["DISCOPARTY_INSTALL_REPO_ROOT"],
    "__HOME__": os.environ["DISCOPARTY_INSTALL_HOME"],
    "__PYTHON_BIN__": os.environ["DISCOPARTY_INSTALL_PYTHON_BIN"],
    "__CONFIG_PATH__": os.environ["DISCOPARTY_INSTALL_CONFIG_PATH"],
    "__LOG_DIR__": os.environ["DISCOPARTY_INSTALL_LOG_DIR"],
}
for placeholder, value in replacements.items():
    data = data.replace(placeholder, escape(value))
remaining = sorted(set(re.findall(r"__[A-Z_]+__", data)))
if remaining:
    raise SystemExit(f"unresolved plist placeholders: {remaining}")
with tempfile.NamedTemporaryFile("w", dir=target.parent, delete=False) as handle:
    temp_path = Path(handle.name)
    handle.write(data)
    handle.flush()
    os.fsync(handle.fileno())
os.chmod(temp_path, 0o600)
os.replace(temp_path, target)
PY

  "$PLUTIL_BIN" -lint "$PLIST_PATH" >/dev/null
  if printf '%s\n' "$NEW_CODEX_TOKEN" | "$PYTHON_BIN" -c '
import sys
from pathlib import Path

secret = sys.stdin.buffer.readline().rstrip(b"\n")
if not secret:
    raise SystemExit(2)
raise SystemExit(0 if any(secret in Path(name).read_bytes() for name in sys.argv[1:]) else 1)
' "$CONFIG_PATH" "$PLIST_PATH"; then
    die "The Discord token was found in a generated plaintext file."
  fi
  if grep -Fq "OPENAI_API_KEY" "$PLIST_PATH"; then
    die "The generated Codex LaunchAgent must not reference OPENAI_API_KEY."
  fi
  green "  Rendered and validated $PLIST_PATH with mode 600."
}

write_legacy_handoff_state() {
  local state="$1"
  [ "$LEGACY_DETECTED" = "1" ] || return 0
  [ -n "$LEGACY_HANDOFF_MARKER" ] && [ -n "$LEGACY_ROOT_CURSOR" ] || return 1
  case "$LEGACY_HANDOFF_STATE:$state" in
    none:maintenance_accepted|\
    maintenance_accepted:legacy_quiesced|\
    legacy_quiesced:backup_complete|\
    backup_complete:cursor_reconciled|\
    cursor_reconciled:new_ready|\
    maintenance_accepted:rolled_back|\
    maintenance_accepted:rollback_blocked|\
    legacy_quiesced:rolled_back|\
    legacy_quiesced:rollback_blocked|\
    backup_complete:rolled_back|\
    backup_complete:rollback_blocked|\
    cursor_reconciled:rolled_back|\
    cursor_reconciled:rollback_blocked|\
    new_ready:rolled_back|\
    new_ready:rollback_blocked) ;;
    *)
      red "ERROR: Invalid legacy takeover state transition: $LEGACY_HANDOFF_STATE -> $state"
      return 1
      ;;
  esac
  env -u PYTHONHOME -u PYTHONPATH -u PYTHONPYCACHEPREFIX -u PYTHONUSERBASE \
    PYTHONSAFEPATH=1 "$PYTHON_BIN" - \
    "$LEGACY_HANDOFF_MARKER" "$state" "$LEGACY_ROOT_CURSOR" \
    "$LEGACY_BACKUP_DIR" "$LEGACY_PRIOR_LOADED" <<'PY'
import json
import os
import stat
import sys
import tempfile
import time
from pathlib import Path

path = Path(sys.argv[1])
state = sys.argv[2]
allowed = {
    "maintenance_accepted",
    "legacy_quiesced",
    "backup_complete",
    "cursor_reconciled",
    "new_ready",
    "rolled_back",
    "rollback_blocked",
}
if state not in allowed:
    raise SystemExit("invalid legacy takeover state")
root = path.parent
metadata = root.lstat()
if (
    stat.S_ISLNK(metadata.st_mode)
    or not stat.S_ISDIR(metadata.st_mode)
    or metadata.st_uid != os.getuid()
    or stat.S_IMODE(metadata.st_mode) != 0o700
):
    raise SystemExit("legacy takeover marker parent is unsafe")
if path.exists() or path.is_symlink():
    current = path.lstat()
    if (
        stat.S_ISLNK(current.st_mode)
        or not stat.S_ISREG(current.st_mode)
        or current.st_uid != os.getuid()
        or stat.S_IMODE(current.st_mode) != 0o600
        or current.st_nlink != 1
    ):
        raise SystemExit("legacy takeover marker path is unsafe")
payload = {
    "version": 1,
    "state": state,
    "legacy_label": "com.thesystem.codex-discord-bridge",
    "replacement_label": "com.discoparty.codex-discord-bridge",
    "root_cursor": sys.argv[3],
    "backup_dir": sys.argv[4] or None,
    "legacy_was_loaded": sys.argv[5] == "1",
    "updated_at": int(time.time()),
}
with tempfile.NamedTemporaryFile("w", dir=root, prefix=".legacy-takeover.", delete=False) as stream:
    temporary = Path(stream.name)
    json.dump(payload, stream, sort_keys=True, separators=(",", ":"))
    stream.write("\n")
    stream.flush()
    os.fsync(stream.fileno())
try:
    temporary.chmod(0o600)
    os.replace(temporary, path)
    descriptor = os.open(root, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
finally:
    temporary.unlink(missing_ok=True)
PY
  LEGACY_HANDOFF_STATE="$state"
}

accept_legacy_maintenance_window() {
  [ "$LEGACY_VALIDATED" = "1" ] || \
    die "Legacy maintenance requires an exact validated legacy deployment."
  local acceptance="${DISCOPARTY_CODEX_LEGACY_MAINTENANCE_ACCEPTED:-}"
  if [ "$NON_INTERACTIVE" != "1" ]; then
    say
    yellow "Stop posting in the Codex Discord channel or any of its existing threads. The legacy Gateway will now be stopped."
    yellow "Any message accepted after this boundary would make automatic rollback unsafe."
    read -r -p "Type LEGACY_MAINTENANCE_ACCEPTED to continue: " acceptance
  fi
  [ "$acceptance" = "LEGACY_MAINTENANCE_ACCEPTED" ] || \
    die "Legacy takeover requires the exact phrase LEGACY_MAINTENANCE_ACCEPTED."
  unset DISCOPARTY_CODEX_LEGACY_MAINTENANCE_ACCEPTED || true
  write_legacy_handoff_state "maintenance_accepted"
}

capture_legacy_process_tree() {
  LEGACY_PROCESS_PIDS=""
  [ "$LEGACY_PRIOR_LOADED" = "1" ] || return 0
  local root_pid=""
  root_pid="$($LAUNCHCTL_BIN print "gui/$UID/$LEGACY_LABEL" 2>/dev/null | \
    awk '/^[[:space:]]*pid = [0-9]+/ {print $3; exit}')"
  [ -n "$root_pid" ] || \
    die "Loaded legacy $LEGACY_LABEL did not expose a process PID."
  [[ "$root_pid" =~ ^[0-9]+$ ]] || \
    die "Legacy launchd PID is malformed."
  LEGACY_PROCESS_PIDS="$("$PYTHON_BIN" - "$root_pid" <<'PY'
import subprocess
import sys

root = int(sys.argv[1])
result = subprocess.run(
    ["/bin/ps", "-axo", "pid=,ppid="],
    text=True,
    capture_output=True,
    timeout=10,
    check=True,
)
children: dict[int, list[int]] = {}
for line in result.stdout.splitlines():
    fields = line.split()
    if len(fields) != 2:
        continue
    pid, parent = (int(field) for field in fields)
    children.setdefault(parent, []).append(pid)
pending = [root]
seen: set[int] = set()
while pending:
    pid = pending.pop()
    if pid in seen:
        continue
    seen.add(pid)
    pending.extend(children.get(pid, ()))
print(" ".join(str(pid) for pid in sorted(seen)))
PY
)"
}

verify_legacy_descendants_stopped() {
  local attempt pid alive
  for attempt in $(seq 1 20); do
    alive=""
    for pid in $LEGACY_PROCESS_PIDS; do
      if kill -0 "$pid" >/dev/null 2>&1; then
        alive="$alive $pid"
      fi
    done
    if [ -z "$alive" ]; then
      LEGACY_DESCENDANTS_DRAINED=1
      return 0
    fi
    sleep 0.5
  done
  return 1
}

quiesce_legacy_agent() {
  [ "$LEGACY_VALIDATED" = "1" ] || die "Legacy service was not validated."
  capture_legacy_process_tree
  blue "Quiescing the validated legacy $LEGACY_LABEL at the maintenance boundary."
  if [ "$LEGACY_PRIOR_LOADED" = "1" ]; then
    if ! "$LAUNCHCTL_BIN" bootout "gui/$UID/$LEGACY_LABEL" >/dev/null 2>&1; then
      if legacy_label_loaded; then
        die "Could not stop legacy $LEGACY_LABEL; Disco Party was not bootstrapped."
      fi
    fi
  fi
  LEGACY_AGENT_QUIESCED=1
  if legacy_label_loaded; then
    die "Legacy $LEGACY_LABEL remained loaded after bootout."
  fi
  if ! verify_legacy_descendants_stopped; then
    die "A captured legacy bridge or App Server descendant survived quiesce."
  fi
  if ! "$LAUNCHCTL_BIN" disable "gui/$UID/$LEGACY_LABEL" >/dev/null 2>&1 || \
      ! legacy_label_disabled; then
    die "Could not disable legacy $LEGACY_LABEL against a future login dual-run."
  fi
  LEGACY_DISABLED=1
  write_legacy_handoff_state "legacy_quiesced"
  green "  Legacy bridge and captured descendants are stopped; its label is disabled."
}

backup_legacy_state() {
  [ "$LEGACY_HANDOFF_STATE" = "legacy_quiesced" ] || \
    die "Legacy state backup requires a quiesced service."
  # Re-read the cursor only after the old Gateway and worker have drained. This
  # is the authoritative no-gap boundary, not the earlier validation snapshot.
  validate_legacy_plist
  validate_legacy_state 1
  local backup_root="$STATE_DIR/migration-backups"
  env -u PYTHONHOME -u PYTHONPATH -u PYTHONPYCACHEPREFIX -u PYTHONUSERBASE \
    PYTHONSAFEPATH=1 "$PYTHON_BIN" - "$STATE_DIR" "$backup_root" <<'PY'
import os
import stat
import sys
from pathlib import Path

state = Path(sys.argv[1])
backup_root = Path(sys.argv[2])
if backup_root != state / "migration-backups":
    raise SystemExit("legacy migration backup path escaped the state directory")
state_metadata = state.lstat()
if (
    stat.S_ISLNK(state_metadata.st_mode)
    or not stat.S_ISDIR(state_metadata.st_mode)
    or state_metadata.st_uid != os.getuid()
    or stat.S_IMODE(state_metadata.st_mode) != 0o700
):
    raise SystemExit("legacy migration state directory is unsafe")
try:
    os.mkdir(backup_root, 0o700)
except FileExistsError:
    pass
backup_metadata = backup_root.lstat()
if (
    stat.S_ISLNK(backup_metadata.st_mode)
    or not stat.S_ISDIR(backup_metadata.st_mode)
    or backup_metadata.st_uid != os.getuid()
    or stat.S_IMODE(backup_metadata.st_mode) != 0o700
):
    raise SystemExit("legacy migration backup root is unsafe")
PY
  LEGACY_BACKUP_DIR="$(mktemp -d "$backup_root/legacy.XXXXXX")"
  chmod 700 "$LEGACY_BACKUP_DIR"
  env -u PYTHONHOME -u PYTHONPATH -u PYTHONPYCACHEPREFIX -u PYTHONUSERBASE \
    PYTHONSAFEPATH=1 "$PYTHON_BIN" - \
    "$LEGACY_DATABASE_PATH" "$LEGACY_PLIST_PATH" "$LEGACY_BACKUP_DIR" \
    "$LEGACY_ROOT_CURSOR" <<'PY'
import hashlib
import json
import os
import shutil
import sqlite3
import stat
import sys
import time
from pathlib import Path

source_path = Path(sys.argv[1])
plist_path = Path(sys.argv[2])
root = Path(sys.argv[3])
cursor = sys.argv[4]
root_metadata = root.lstat()
if (
    stat.S_ISLNK(root_metadata.st_mode)
    or not stat.S_ISDIR(root_metadata.st_mode)
    or root_metadata.st_uid != os.getuid()
    or stat.S_IMODE(root_metadata.st_mode) != 0o700
):
    raise SystemExit("legacy migration backup directory is unsafe")
database_copy = root / "jobs.sqlite3"
with sqlite3.connect(f"file:{source_path}?mode=ro", uri=True) as source:
    with sqlite3.connect(database_copy) as destination:
        source.backup(destination)
        if destination.execute("PRAGMA quick_check").fetchone()[0] != "ok":
            raise SystemExit("legacy SQLite backup failed quick_check")
database_copy.chmod(0o600)
database_descriptor = os.open(database_copy, os.O_RDONLY)
try:
    os.fsync(database_descriptor)
finally:
    os.close(database_descriptor)
plist_copy = root / "com.thesystem.codex-discord-bridge.plist"
with plist_path.open("rb") as source, plist_copy.open("xb") as destination:
    shutil.copyfileobj(source, destination)
    destination.flush()
    os.fsync(destination.fileno())
plist_copy.chmod(0o600)

def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            value.update(chunk)
    return value.hexdigest()

manifest = {
    "version": 1,
    "created_at": int(time.time()),
    "legacy_label": "com.thesystem.codex-discord-bridge",
    "root_cursor": cursor,
    "database_sha256": digest(database_copy),
    "plist_sha256": digest(plist_copy),
}
manifest_path = root / "manifest.json"
with manifest_path.open("x") as stream:
    json.dump(manifest, stream, sort_keys=True, separators=(",", ":"))
    stream.write("\n")
    stream.flush()
    os.fsync(stream.fileno())
manifest_path.chmod(0o600)
for directory in (root, root.parent, root.parent.parent):
    descriptor = os.open(directory, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
PY
  write_legacy_handoff_state "backup_complete"
  green "  Private SQLite and plist migration backup: $LEGACY_BACKUP_DIR"
}

current_policy_binding() {
  env -u OPENAI_API_KEY -u CODEX_HOME \
    -u DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED \
    HOME="$HOME" PYTHONPATH="$REPO_ROOT" DISCOPARTY_CONFIG="$CONFIG_PATH" \
    "$PYTHON_BIN" - <<'PY'
from codex_discord_bridge.config import Config
from codex_discord_bridge.main import probe_account_binding
import asyncio

config = Config.from_discoparty()
instructions = config.instructions_digest()
shared_skills = config.shared_skills_digest()
shared_hooks = config.shared_hooks_digest()
vault_policy = config.seal_vault_policy()
account = asyncio.run(
    probe_account_binding(
        config, instructions, shared_skills, shared_hooks, vault_policy
    )
)
print(
    config.policy_fingerprint(
        instructions,
        account,
        shared_skills,
        vault_policy,
        shared_hooks,
    )
)
PY
}

reconcile_legacy_root_cursor() {
  [ "$LEGACY_HANDOFF_STATE" = "backup_complete" ] || \
    die "Root cursor handoff requires a completed private legacy backup."
  local database="$STATE_DIR/jobs.sqlite3"
  if [ -e "$database" ] || [ -e "$database-wal" ] || [ -e "$database-shm" ]; then
    die "Legacy takeover requires an empty Disco Party job ledger; refusing to merge histories implicitly."
  fi
  local binding=""
  binding="$(current_policy_binding)"
  [[ "$binding" =~ ^[0-9a-f]{64}$ ]] || die "Current Codex policy binding is malformed."
  LEGACY_HANDOFF_DB_CREATED=1
  env -u PYTHONHOME -u PYTHONPATH -u PYTHONPYCACHEPREFIX -u PYTHONUSERBASE \
    PYTHONSAFEPATH=1 PYTHONPATH="$REPO_ROOT" "$PYTHON_BIN" - \
    "$database" "$binding" "$DISCOPARTY_CODEX_CHANNEL_ID" "$LEGACY_ROOT_CURSOR" <<'PY'
import sys
from pathlib import Path

from codex_discord_bridge.store import JobStore

path = Path(sys.argv[1])
binding, channel_id, cursor = sys.argv[2:]
store = JobStore(path, policy_binding=binding)
store.save_cursor(channel_id, cursor)
if store.cursor_for(channel_id) != cursor:
    raise SystemExit("Disco Party root cursor handoff did not persist")
with store.connect() as db:
    if int(db.execute("SELECT COUNT(*) FROM jobs").fetchone()[0]) != 0:
        raise SystemExit("Disco Party takeover ledger unexpectedly contains jobs")
PY
  write_legacy_handoff_state "cursor_reconciled"
  green "  Root cursor reconciled into the current policy scope."
}

verify_legacy_cursor_handoff() {
  [ "$LEGACY_HANDOFF_STATE" = "cursor_reconciled" ] || return 1
  local binding=""
  binding="$(current_policy_binding)" || return 1
  [[ "$binding" =~ ^[0-9a-f]{64}$ ]] || return 1
  env -u PYTHONHOME -u PYTHONPATH -u PYTHONPYCACHEPREFIX -u PYTHONUSERBASE \
    PYTHONSAFEPATH=1 PYTHONPATH="$REPO_ROOT" "$PYTHON_BIN" - \
    "$STATE_DIR/jobs.sqlite3" "$LEGACY_HANDOFF_MARKER" "$binding" \
    "$DISCOPARTY_CODEX_CHANNEL_ID" "$LEGACY_ROOT_CURSOR" "$LEGACY_BACKUP_DIR" <<'PY'
import json
import os
import sqlite3
import stat
import sys
from pathlib import Path

database = Path(sys.argv[1])
marker = Path(sys.argv[2])
binding, channel_id, cursor, backup = sys.argv[3:]
metadata = marker.lstat()
if (
    stat.S_ISLNK(metadata.st_mode)
    or not stat.S_ISREG(metadata.st_mode)
    or metadata.st_uid != os.getuid()
    or stat.S_IMODE(metadata.st_mode) != 0o600
    or metadata.st_nlink != 1
):
    raise SystemExit("legacy takeover marker is unsafe")
payload = json.loads(marker.read_text())
if (
    payload.get("version") != 1
    or payload.get("state") != "cursor_reconciled"
    or payload.get("root_cursor") != cursor
    or payload.get("backup_dir") != backup
    or payload.get("legacy_label") != "com.thesystem.codex-discord-bridge"
):
    raise SystemExit("legacy takeover marker does not authorize bootstrap")
scope = f"policy:{binding}:{channel_id}"
with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as db:
    row = db.execute(
        "SELECT event_id FROM channel_cursors WHERE channel_id=?", (scope,)
    ).fetchone()
    jobs = int(db.execute("SELECT COUNT(*) FROM jobs").fetchone()[0])
if not row or str(row[0]) != cursor or jobs:
    raise SystemExit("legacy root cursor is not reconciled into an empty replacement ledger")
PY
}

perform_legacy_handoff() {
  [ "$LEGACY_DETECTED" = "1" ] || return 0
  if [ "$SCRATCH" = "1" ]; then
    # A successful scratch run must not leave a replacement LaunchAgent
    # footprint that makes the later real takeover look like a dual install.
    # The rendered plist has already passed lint and secret checks.
    if [ "$PLIST_MUTATED" = "1" ]; then
      if [ "$PLIST_EXISTED" = "1" ]; then
        [ -n "$PLIST_BACKUP" ] && cp -p "$PLIST_BACKUP" "$PLIST_PATH" || \
          die "Could not restore the pre-scratch Disco Party plist."
      else
        rm -f "$PLIST_PATH" || \
          die "Could not remove the validated scratch Disco Party plist."
      fi
      PLIST_MUTATED=0
    fi
    yellow "  --scratch validated the exact legacy footprint; its rendered replacement plist was removed, and service quiesce and cursor handoff were skipped."
    return 0
  fi
  accept_legacy_maintenance_window
  quiesce_legacy_agent
  backup_legacy_state
  reconcile_legacy_root_cursor
}

authorize_provider_bootstrap() {
  [ "$LEGACY_DETECTED" = "1" ] || return 0
  [ "$SCRATCH" = "0" ] || return 0
  if legacy_label_loaded; then
    die "Legacy $LEGACY_LABEL became loaded before replacement bootstrap."
  fi
  [ "$LEGACY_DISABLED" = "1" ] || \
    die "Legacy launchd label is not disabled against a future dual-run."
  verify_legacy_cursor_handoff || \
    die "Legacy root cursor is not durably reconciled; replacement bootstrap is forbidden."
}

complete_legacy_takeover() {
  [ "$LEGACY_DETECTED" = "1" ] || return 0
  [ "$SCRATCH" = "0" ] || return 0
  write_legacy_handoff_state "new_ready"
  green "  Legacy takeover state is new_ready; the old label remains disabled for rollback."
}

bootstrap_agent() {
  if [ "$SCRATCH" = "1" ]; then
    yellow "  --scratch mode: launchd bootstrap skipped."
    return 0
  fi
  validate_log_targets
  blue "Bootstrapping $LABEL."
  local ready_path="$STATE_DIR/ready.json"
  local ready_after
  ready_after="$(date +%s)"
  if [ -L "$ready_path" ] || { [ -e "$ready_path" ] && [ ! -f "$ready_path" ]; }; then
    die "Refusing an unsafe Codex readiness marker path: $ready_path"
  fi
  rm -f "$ready_path"
  BOOTSTRAP_MUTATED=1
  if "$LAUNCHCTL_BIN" print "gui/$UID/$LABEL" >/dev/null 2>&1; then
    die "$LABEL became loaded during installation; refusing to replace it after shared state changed."
  fi
  "$LAUNCHCTL_BIN" bootstrap "gui/$UID" "$PLIST_PATH"
  "$LAUNCHCTL_BIN" enable "gui/$UID/$LABEL" >/dev/null 2>&1 || true
  "$LAUNCHCTL_BIN" print "gui/$UID/$LABEL" >/dev/null
  local attempt
  for attempt in $(seq 1 45); do
    if "$PYTHON_BIN" - "$ready_path" "$ready_after" <<'PY'
import json
import os
import stat
import sys
from pathlib import Path

path = Path(sys.argv[1])
threshold = int(sys.argv[2])
try:
    metadata = path.lstat()
    data = json.loads(path.read_text())
except (FileNotFoundError, OSError, ValueError, json.JSONDecodeError):
    raise SystemExit(1)
valid = (
    stat.S_ISREG(metadata.st_mode)
    and stat.S_IMODE(metadata.st_mode) == 0o600
    and metadata.st_uid == os.getuid()
    and data.get("version") == 1
    and data.get("ready") is True
    and isinstance(data.get("pid"), int)
    and data["pid"] > 0
    and isinstance(data.get("instance_id"), str)
    and len(data["instance_id"]) == 32
    and isinstance(data.get("started_at"), int)
    and data["started_at"] >= threshold
)
raise SystemExit(0 if valid else 1)
PY
    then
      green "  $LABEL is loaded, reconciled, and ready."
      return 0
    fi
    "$LAUNCHCTL_BIN" print "gui/$UID/$LABEL" >/dev/null || \
      die "$LABEL stopped before it became ready. Check $LOG_DIR/codex-discord-bridge.stderr.log."
    sleep 1
  done
  die "$LABEL did not become ready within 45 seconds. Check $LOG_DIR/codex-discord-bridge.stderr.log."
}

start_monitor() {
  if [ "$SCRATCH" = "1" ]; then
    yellow "  --scratch mode: tmux monitor start skipped."
    return 0
  fi
  if [ "$START_MONITOR" != "1" ]; then
    say "  Read-only tmux monitor not requested."
    return 0
  fi
  if ! command -v tmux >/dev/null 2>&1; then
    yellow "  tmux is unavailable. The bridge is running without the optional monitor."
    return 0
  fi
  local launcher="$REPO_ROOT/launchd/codex-monitor.sh"
  if [ ! -x "$launcher" ]; then
    yellow "  Monitor launcher is not executable: $launcher"
    return 0
  fi
  if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    if [ "$REINSTALL" = "1" ]; then
      tmux kill-session -t "$TMUX_SESSION" || true
    else
      say "  Read-only tmux monitor '$TMUX_SESSION' is already running."
      return 0
    fi
  fi
  local monitor_command=""
  printf -v monitor_command '%q' "$launcher"
  if ! tmux new-session -d -s "$TMUX_SESSION" -c "$REPO_ROOT" "$monitor_command"; then
    yellow "  Could not start the optional tmux monitor. The bridge is still running."
    return 0
  fi
  green "  Started read-only tmux monitor '$TMUX_SESSION'."
}

main() {
  say "Disco Party Codex provider installer"
  say "LaunchAgent: $LABEL"
  say

  check_no_api_key
  check_prerequisites
  resolve_settings
  require_topology_validated
  detect_and_validate_legacy
  handle_existing_install
  quiesce_existing_agent
  prepare_log_directory
  prepare_isolated_codex
  prepare_shared_skill_bridge
  prepare_vault_policy_seal
  prepare_python_runtime
  verify_reviewed_codex_package
  ensure_isolated_chatgpt_login
  resolve_bot_token
  store_bot_token
  update_codex_config
  run_preflight
  render_plist
  perform_legacy_handoff
  authorize_provider_bootstrap
  bootstrap_agent
  complete_legacy_takeover
  start_monitor

  green
  green "Codex provider installation complete."
  say
  say "Codex provider:"
  say "  Config:           $CONFIG_PATH ([codex] only)"
  say "  Working dir:      $DISCOPARTY_CODEX_WORKING_DIRECTORY"
  say "  Isolated home:    $WORKER_HOME"
  say "  Isolated CODEX_HOME: $CODEX_HOME_DIR"
  say "  Shared skills:    $SHARED_SKILLS_ROOT"
  say "  Channel trust:    ${DISCOPARTY_CODEX_CHANNEL_TRUST:-public}"
  say "  Sandbox:          $DISCOPARTY_CODEX_SANDBOX_MODE"
  say "  Keychain:         service=$KEYCHAIN_SERVICE account=$KEYCHAIN_ACCOUNT"
  say "  LaunchAgent:      $LABEL"
  say "  Plist:            $PLIST_PATH"
  say "  Monitor:          tmux attach -t $TMUX_SESSION"
  say "  Uninstall Codex:  $SCRIPT_DIR/uninstall.sh --codex"
  say
  say "Claude services and Claude configuration were left unchanged."
}

main "$@"
