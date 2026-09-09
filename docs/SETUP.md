# Disco Party setup guide

This guide installs the original Claude provider and the optional Codex provider on macOS. You can run either provider or both.

## Choose the topology first

| Choice | Discord resources | Local runtime |
| --- | --- | --- |
| Claude only | One Claude bot in `#claude` | Interactive `discoparty-chat` tmux listener |
| Codex only | One Codex bot in `#chatgpt` | Headless `com.discoparty.codex-discord-bridge` LaunchAgent |
| Both | Two applications, two bots, and two channels | Both independent runtimes |

Think of each row as one orchestrator route. A route binds one Discord bot and channel to one provider runtime and its durable state. You can place several routes in the same Discord server to reach a work Mac and a home Mac from one command center, but each machine and provider needs its own route.

Do not point Claude and Codex at the same channel. Do not reuse one bot token for both. Dedicate the Codex application and bot to this integration and install that bot in exactly one Discord server. Gateway READY fails unless its guild inventory is exactly the configured guild. The Codex configuration loader rejects a channel that matches the Claude listen channel. Preflight compares the Codex token with standard discoverable Claude token sources. A custom Claude token source may not be discoverable, so the operator remains responsible for token separation.

A Discord channel can remain public to server members. Public controls who can read it. The Codex ingress policy separately controls who can trigger work and accepts only the configured owner user ID.

## Prerequisites

### Common

- A Discord server you own or administer
- Python 3.11 or newer
- `websockets`, installed through `requirements.txt`
- macOS Keychain access
- `tmux`, `curl`, and `jq` for the existing Claude install path
- Immutable Discord IDs copied with Discord Developer Mode, never display names

### Claude provider

- Claude Code CLI installed and signed in to the intended subscription
- The official Claude Discord plugin available
- A Discord application and bot for Claude
- A Claude listen channel and an errors channel, which may be the same channel

### Codex provider

- The reviewed Apple M5 Max host. The provider installer checks the exact reported chip and refuses other models.
- Official OpenAI Codex CLI `0.153.4` installed through the reviewed `/opt/homebrew` npm package layout
- Access to the intended ChatGPT subscription for a separate browser sign-in during installation
- A second Discord application and bot for Codex
- The Codex application and bot are dedicated to this integration, and the bot belongs only to the configured Discord server
- A separate Codex channel
- An existing Codex working directory that does not overlap the Disco Party repository, config, state, logs, LaunchAgent plist, trusted instruction file, or canonical Vault policy, hook, and shared-skill sources
- Your Discord guild ID, owner user ID, Codex channel ID, Codex bot user ID, and Codex application ID

OpenAI documents both ChatGPT subscription and API-key sign-in for Codex. Disco Party deliberately supports only the ChatGPT path. See the official [OpenAI authentication documentation](https://learn.chatgpt.com/docs/auth), [Codex App Server documentation](https://learn.chatgpt.com/docs/app-server), and [`gpt-5.6-sol` model page](https://developers.openai.com/api/docs/models/gpt-5.6-sol).

## 1. Create the Discord applications

If you are running both providers, complete this section twice and give the applications distinct names such as `Disco Party Claude` and `Disco Party Codex`.

1. Open the [Discord Developer Portal](https://discord.com/developers/applications).
2. Create an application.
3. Open the Bot tab and create its bot user.
4. Enable the Message Content Intent if that bot's runtime receives message bodies through the Gateway. For Codex `owner_private`, also enable the Server Members privileged intent so Disco Party can prove the channel has no effective reader other than the guild owner and dedicated bridge.
5. Copy the bot token once. Treat it as a password and provide it only to the appropriate installer prompt.
6. Invite the bot to the server.
7. Grant only the channel permissions the provider needs.
8. In Discord, enable Developer Mode and copy the immutable IDs.

### Claude bot permissions

Use OAuth scopes `bot` and `applications.commands`. The existing approval buttons and Discord plugin path need the application scope. Required channel permissions are:

- View Channel
- Read Message History
- Send Messages
- Send Messages in Threads
- Create Public Threads
- Manage Threads
- Add Reactions

### Codex bot permissions

The Codex bridge does not require administrator permission. Its normal message flow needs:

- View Channel
- Read Message History
- Send Messages
- Send Messages in Threads
- Create Public Threads
- Add Reactions

Keep the bot confined to the Codex channel and threads created beneath it. Record the bot user ID and application ID separately. Disco Party checks both at Gateway READY and on every accepted event.

Use Discord role, category, and channel overwrites to deny the Codex bot View Channel everywhere except the configured Codex channel, its declared parent category when present, and active public child threads beneath it. The parent-category exception is limited to the exact `GUILD_CATEGORY` named by the configured channel and exposes category metadata rather than messages. The verifier calls Discord's guild-channel and active-thread list endpoints and fails if the bot can view any other channel, category, private thread, announcement thread, or unrelated public thread. Exact ingress still rejects every event outside the configured channel tree. Discord documents event and content scope in [Gateway intents](https://docs.discord.com/developers/events/gateway#gateway-intents) and the list endpoints in the [Guild resource](https://docs.discord.com/developers/resources/guild).

The configured Codex channel must be a normal `GUILD_TEXT` channel. Its `@everyone` channel overwrite must explicitly deny Manage Threads, Create Public Threads, and Create Private Threads. Restore Create Public Threads only through an explicit member overwrite for the configured bot. No role overwrite, including the bot role, and no other member overwrite may allow any of those three thread permissions. The bot must have the six permissions above after Discord's base-role, `@everyone`, role-overwrite, and member-overwrite precedence is applied. It must not own the guild.

For `public`, leave View Channel effective for `@everyone`. For optional `owner_private`, explicitly deny `@everyone` View Channel, add exact member View Channel allows for the configured guild owner and dedicated bridge, and remove every other role or member View allow. The configured owner must own the guild, and no other guild member may have effective View Channel through roles, Administrator, ownership, or member overwrites. A public channel in a currently small server does not qualify because a new member could immediately read retained history.

Its guild roles must not grant Kick Members, Ban Members, Administrator, Manage Channels, Manage Guild, View Audit Log, Manage Messages, View Guild Insights, Mute Members, Deafen Members, Move Members, Manage Nicknames, Manage Roles, Manage Webhooks, Manage Guild Expressions, Manage Events, Manage Threads, Moderate Members, View Creator Monetization Analytics, Create Guild Expressions, or Create Events. Effective permissions in `#chatgpt` must also exclude those bits plus Create Instant Invite, Send TTS Messages, Attach Files, Mention Everyone, Create Private Threads, Send Voice Messages, Send Polls, Use External Apps, and Pin Messages. Because the bot inherits `@everyone` and role permissions, use explicit bot-role or member overwrites where necessary. Disco Party follows Discord's official [permission hierarchy](https://docs.discord.com/developers/topics/permissions) and [channel types](https://docs.discord.com/developers/resources/channel). A special member deny may still hide an otherwise public channel from that member.

## 2. Clone the repository and install Python dependencies

```sh
git clone https://github.com/vp58/discoparty.git ~/.discoparty
cd ~/.discoparty
python3 -m pip install -r requirements.txt
```

## 3. Install the Claude provider

```sh
cd ~/.discoparty
bash install.sh
```

This is the original installer and remains backward compatible. It:

1. Checks the Claude prerequisites.
2. Collects the workspace root, Claude channel IDs, owner user ID, and timezone.
3. Stores the Claude Discord bot token in macOS Keychain under service `discoparty-secret`, account `discord-bot-token`.
4. Writes the shared and Claude sections of `config.toml`.
5. Installs the Claude listener healthcheck and Discord gateway client plists. It removes the obsolete marker-watcher service if an older installation left one behind.
6. Starts the interactive Claude listener in a tmux session named `discoparty-chat`.

The Codex provider is disabled unless you configure and install it separately.

### Take over the reviewed legacy Claude orchestrator

An ordinary Claude install refuses to run beside the older `com.thesystem`
jobs or the `cx-chat` tmux listener. Use the takeover path only for the exact
legacy deployment and only during a Discord maintenance window:

```sh
bash install.sh --take-over-legacy
```

Stop posting in the Claude root channel and all of its threads first. The
installer requires the exact maintenance phrase:

```text
I HAVE STOPPED POSTING AND AUTHORIZE LEGACY CLAUDE TAKEOVER
```

It then reads the live queue without changing it and shows separate counts for
legacy `claimed` rows that have no new operation ledger, legacy `dispatched`
rows, and `spawned` blockers. Any `spawned` row stops takeover and requires
manual side-effect and response reconciliation. For the other two ambiguous
states, the installer requires a second phrase with the exact observed counts:

```text
QUARANTINE <claimed-count> CLAIMED-WITHOUT-LEDGER AND <dispatched-count> DISPATCHED ROWS FOR MANUAL REVIEW
```

In non-interactive mode, pass those exact values through
`DISCOPARTY_LEGACY_MAINTENANCE_PHRASE` and
`DISCOPARTY_LEGACY_QUARANTINE_ACK`. The values are accepted only for the queue
snapshot whose SHA-256 digest was shown by the same plan. Any queue change
before quiescence invalidates the acknowledgment and restores the legacy
runtime without quarantining a row.

After both acknowledgments, the installer performs this sequence:

1. Validate the exact five legacy labels, their private plists, the one-pane
   `cx-chat` listener, its reviewed Claude command, workspace, process group,
   and descendant tree.
2. Stop `com.thesystem.cx-chat-healthcheck` first, then stop legacy Gateway,
   marker, queue-monitor, and archive-sync jobs. Stop the exact tmux process
   group and prove every known legacy process is gone.
3. Preserve `x_System/Assistant/conversations` as the configured conversation
   root. Create a private SQLite API snapshot plus raw database, WAL, and SHM
   copies. Back up the registry, active and archived transcripts, state,
   approval files, and all five legacy plists. Verify every backup file against
   its SHA-256 manifest before continuing.
4. Recompute the acknowledged queue snapshot. Quarantine only `claimed` rows
   without an operation ledger and `dispatched` rows. Their complete original
   rows remain in the pre-mutation backup and reversible quarantine table. They
   are unresolved manual-review items and are never replayed or described as
   migrated work.
5. Capture one global lower Discord snowflake, enumerate the root channel and
   every registered public thread, capture a maintenance upper boundary, and
   enqueue only owner messages in that closed window. Full Discord payloads are
   preserved, queue inserts are idempotent by `message_id`, and eyes reactions
   are confirmed.
6. Delete any replacement Gateway session and sequence state so the new client
   performs a fresh connection. Freeze the queue acceptance baseline, install
   the replacement, and prove its exact launchd labels, tmux identity, listener
   contract, and readiness token.
7. Repeat the bounded root-and-thread Discord scan through a fresh upper bound.
   The overlap is safe because the queue message ID is unique.
8. Persist a private, random, 256-bit, 15-minute drain challenge before sending
   its bare local prompt to the exact tmux listener. Discord content is always
   wrapped in a channel envelope and cannot invoke this local-only contract. The
   listener resumes safe work through the normal queue protocol and returns the
   exact challenge-bound completion token.
9. Prove that no row remains in `received`, `claimed`, or `dispatched`, prove the
   exact listener again, consume the single-use challenge, and commit takeover.

If installation fails before the replacement admits work, the trap restores
the reversible queue states and replacement Gateway file, stops the exact new
services, and reloads the original five jobs with healthcheck last. If any new
row appears or any prior nonterminal row changes after replacement start,
automatic legacy restart is permanently refused. Keep both sides stopped and
review the private receipt under
`x_System/Assistant/conversations/state/takeover/`. A committed takeover can
never automatically restart the old runtime. The receipt is written before the
first legacy stop and advances through validation, quiescence, backup,
quarantine authorization, gap reconciliation, Gateway reset, replacement
start, final reconciliation, drain challenge, and commit. After a power loss
or killed installer, do not guess from
process presence. Run the receipt through `claude_takeover.py abort` only after
reviewing its phase. The abort command reloads legacy only when its durable
acceptance gate still proves that is safe.

### Verify Claude

Attach to the listener:

```sh
tmux attach -t discoparty-chat
```

You should see Claude Code running with the Discord plugin and the `cx-chat` listener identity. Detach with `Ctrl-b d`.

Check the approval Gateway process:

```sh
launchctl print gui/$UID/com.discoparty.discord-gateway-client | head -20
```

Post a test message in `#claude`. Verify the eyes reaction, public thread, markdown transcript, and worker reply in Discord. A running process alone does not prove the workflow reached Discord.

## 4. Understand the isolated ChatGPT sign-in

Confirm the reviewed CLI before running the installer:

```sh
codex --version
```

It must report `codex-cli 0.153.4`. Disco Party verifies the npm launcher path and hash, then executes the reviewed native arm64 binary directly. An unreviewed launcher, binary, version, schema, or App Server request set blocks installation.

Do not rely on a normal `~/.codex` login for this service. The installer retains the real canonical macOS `HOME` so the official keyring backend can use the default Keychain. It creates a mode `0700` `CODEX_HOME` at `state_dir/home/.codex` with a mode `0600` reviewed config. If that isolated scope is not authenticated, the installer launches the official browser flow and requires **Sign in with ChatGPT**. In non-interactive mode, run the exact isolated login command printed by the installer, then retry.

The isolated config forces ChatGPT login, requires exact macOS Keychain credential storage, disables filesystem secret storage, pins `gpt-5.6-sol` with the OpenAI provider and Ultra reasoning, disables model fallback, and refuses `OPENAI_API_KEY`. Normal `~/.codex/config.toml`, credentials, MCP servers, and plugins are not loaded. Disco Party rejects `auth.json` and related filesystem credential artifacts throughout startup and turn execution. It requires official `codex login status` plus App Server `account/read`, hashes the returned nonsecret email and plan facts without logging the email, and binds that digest into durable policy state. The official Codex client, Keychain, and OpenAI service remain responsible for credential storage and upstream authentication.

The isolated `CODEX_HOME` is still part of the same macOS account. The default remains the reviewed restricted workspace profile. `danger-full-access` exposes same-user files, Keychain queries, processes, and command-network destinations. Disco Party accepts it only after the exact operator acknowledgment described below. This execution choice is independent of whether the Discord destination is `public` or `owner_private`.

## 5. Install the Codex provider

Run the provider-specific installer after the Claude installer, or against a clone where the shared configuration already exists:

```sh
cd ~/.discoparty
bash install-codex.sh
```

The Codex installer collects the five immutable Discord IDs, the working directory, state directory, and sandbox choice. It stores the second bot token in macOS Keychain under service `discoparty-secret`, account `discord-bot-token-codex`, without replacing the Claude token.

For normal installation, it derives an immutable path named `state_dir/runtime-venv-cpython-<major.minor>-websockets-<version>-<lock-sha256>` from the current CPython and versioned `requirements-macos-arm64.lock`. It creates a new runtime in a private staging directory with isolated pip mode, required hashes, and binary-only wheels, verifies arm64 macOS, the exact Python and `websockets` versions, installed-distribution hashes, and a mode `0600` manifest, then publishes the directory atomically. An existing exact path is verified and reused, never cleared or repaired in place. The LaunchAgent executes that private Python instead of an ambient user-site package set.

The writable working directory must not contain, equal, or sit above the Disco Party repository, `config.toml`, Codex state directory, service logs, LaunchAgent plist, or trusted instruction file. The reverse overlap is also unsafe. Otherwise a workspace-scoped agent could rewrite its bridge, policy, future job ledger, or launch configuration. Installer and preflight validation reject these overlaps.

The installer and daemon independently require `state_dir` to be an explicit descendant of the canonical `~/Library/Application Support/Discoparty` root. They reject arbitrary paths elsewhere under the home directory, including another Git checkout or synced working tree, so ChatGPT auth and App Server rollout state cannot be placed there by configuration. Every existing path component from the canonical home through the selected state directory must be a real current-user-owned directory, must not be a symlink, and must not be group or world writable. Generated state directories use mode `0700`; generated config, readiness, manifest, plist, and SQLite files use private modes appropriate to their type.

An optional `[codex].instructions_file` is the only additional instruction source. Keep it outside the writable workspace. Disco Party embeds its content into App Server base instructions only after verifying that it is a current-user-owned, single-link regular UTF-8 file, no larger than 256,000 bytes and not group or world writable. Its lexical and canonical paths must not overlap the workspace, and filesystem-identity comparison also rejects macOS data-volume aliases into the workspace. Every path component must be a real directory, never a symlink, with stable root-owned or current-user-owned ancestry that is not group or world writable. A root-owned sticky temporary-directory boundary is the narrow exception. Disco Party rechecks the file and ancestry after each read. Project roots stay untrusted, `project_doc_max_bytes` is zero, project fallback filenames are empty, and App Server must report `instructionSources: []`. Workspace `AGENTS.md` and fallback project documents are not auto-loaded. Files explicitly read during a task remain untrusted content.

The resulting `[codex]` configuration follows this shape:

```toml
[codex]
enabled = true
guild_id = "000000000000000000"
channel_id = "000000000000000000"
owner_user_id = "000000000000000000"
bot_user_id = "000000000000000000"
application_id = "000000000000000000"
working_directory = "~/path/to/your-workspace"
state_dir = "~/Library/Application Support/Discoparty/codex-discord"
codex_home = "~/Library/Application Support/Discoparty/codex-discord/home/.codex"
codex_bin = "/opt/homebrew/bin/codex"
sandbox_mode = "workspace-write"
full_computer_access_accepted = false
keychain_service = "discoparty-secret"
keychain_account = "discord-bot-token-codex"
max_messages_per_minute = 5
max_messages_per_hour = 30
max_concurrent_workers = 3
max_pending_jobs = 100
max_input_chars = 12000
retention_days = 30
max_database_bytes = 268435456
```

On a new install, the state directory defaults to the Application Support path shown above. `DISCOPARTY_CODEX_STATE_DIR` may select another explicit subpath below `~/Library/Application Support/Discoparty`; a path elsewhere is rejected. Reinstall may reuse an existing configured state path only when it satisfies that same canonical-root policy, and always derives `codex_home` beneath it. If an older configured path is outside the approved subtree, reinstall fails closed. Migrate by rerunning with an explicit approved state override and completing the isolated ChatGPT login in the new `<state>/home/.codex`; Disco Party does not silently move credentials or rollout history. Provider identity, workspace, sandbox, and Keychain fields come from the current install inputs. The installer also preserves an existing `instructions_file` and all seven validated limit overrides. Claude tables remain unchanged.

The installer creates the `com.discoparty.codex-discord-bridge` LaunchAgent. The bridge is the worker. It does not need a persistent interactive Codex terminal.

### Take over the reviewed legacy Codex bridge

`install-codex.sh` detects the earlier `com.thesystem.codex-discord-bridge` label and its plist at `~/Library/LaunchAgents/com.thesystem.codex-discord-bridge.plist`. An ordinary installation stops before staging when either legacy footprint exists. It also refuses a takeover when both the legacy and Disco Party provider footprints exist. This prevents two Codex bots from reading the same channel during an accidental parallel install.

The migration path is deliberately narrow. It accepts only the reviewed legacy repository at `~/TheSystem/x_System/Assistant/codex-discord-bridge`, exact Python module launch arguments, Discord identity and workspace fields matching the new install inputs, and `CODEX_DISCORD_CHANNEL_TRUST=public`. It also requires a private current-user-owned legacy plist and SQLite ledger, compatible tables, one valid root-channel cursor, and no foreign guild or author binding. Resolve any validation error in the old deployment and verify it again before attempting takeover. Do not weaken the validator or rename an unrelated service to make it pass.

First stage and validate without stopping the old service:

```sh
bash install-codex.sh --scratch --take-over-legacy
```

Scratch mode can stage the new private state, config, and credential inputs. It renders and validates the replacement plist, then removes that plist so the later maintenance run cannot mistake it for a second installed provider. It does not stop or disable the legacy label, copy the root cursor, or bootstrap Disco Party. The legacy bridge remains the only running provider.

For the real maintenance window, stop posting in `#chatgpt` and every existing legacy Codex thread, then run:

```sh
bash install-codex.sh --take-over-legacy --import-legacy-token
```

`--import-legacy-token` is a separate opt-in. It reads only Keychain service `thesystem-secret`, account `discord-bot-token-admin`, keeps the value in a non-exported shell variable, and writes the new `discoparty-secret/discord-bot-token-codex` item through standard input. The token is not placed in child arguments, the environment, generated files, or logs. If a Disco Party token already exists, the installer snapshots it and restores it on a safe rollback. The legacy Keychain item is retained. You may omit this flag and provide a separate dedicated token instead.

The old shared Codex login is never imported. Complete the official Sign in with ChatGPT browser flow for Disco Party's isolated `state_dir/home/.codex` before the maintenance boundary. The old service stays live while Disco Party prepares its runtime, isolated login, token, config, provider preflight, and replacement plist.

The installer then requires the exact maintenance phrase `LEGACY_MAINTENANCE_ACCEPTED`. In non-interactive mode, set `DISCOPARTY_CODEX_LEGACY_MAINTENANCE_ACCEPTED=LEGACY_MAINTENANCE_ACCEPTED` for that one install. After acceptance it performs this fail-closed sequence:

1. Capture the legacy bridge and App Server descendant process IDs.
2. Boot out the exact legacy label, verify the label is absent and every captured descendant has exited, then disable the old label against a login or reboot dual-run.
3. Reopen the legacy SQLite ledger after shutdown. Any queued, running, uncertain, or prepared job or delivery blocks handoff and restarts the old service when rollback remains safe.
4. Create a private SQLite backup and plist copy under `state_dir/migration-backups/legacy.*`, with a hash manifest and the final root cursor.
5. Create an otherwise empty Disco Party ledger and store that cursor in the current policy fingerprint scope.
6. Verify the marker, backup path, policy-scoped cursor, empty job table, disabled old label, and absent old process before bootstrapping Disco Party.
7. Wait for fresh Gateway and App Server readiness, then mark the takeover `new_ready`.

The private `state_dir/legacy-takeover.json` marker records `maintenance_accepted`, `legacy_quiesced`, `backup_complete`, `cursor_reconciled`, and `new_ready`. A safe automatic rollback records `rolled_back`. `rollback_blocked` means Disco Party could not prove that restarting the old service was safe. The replacement is never authorized while the marker or durable cursor is missing or inconsistent.

Only the final root-channel cursor crosses the boundary. Legacy jobs, Discord thread mappings, Codex session IDs, delivery history, and shared-login state are not imported into the new schema. Treat existing legacy Discord threads as frozen and start a new root message after Disco Party is live.

On an ordinary installer failure, rollback restores staged Disco Party config, plist, policy, and Keychain snapshots before reloading the old label in its prior enablement state. It deletes the replacement ledger only if it can prove there are no jobs or delivery manifests. Once the replacement has accepted work, automatic legacy restart is forbidden because that could duplicate effects. A power loss cannot run the shell rollback trap. After any interrupted takeover, inspect both launchd labels, `legacy-takeover.json`, the private backup, and both ledgers before taking action. The installer refuses an ambiguous old-plus-new footprint instead of guessing. Keep the legacy plist, state directory, Keychain item, and disabled label until the live Discord acceptance checks have passed and a separate rollback decision has been made. Later Disco Party reinstalls, including a reinstall after `uninstall.sh --codex` removed the replacement plist, accept that retained footprint only when the old label is unloaded and disabled and the `new_ready` marker plus backup hashes still match the exact legacy ledger.

## 6. Run the Codex preflight

From the repository root:

```sh
PYTHONPATH=. python3 -m codex_discord_bridge.preflight
```

A successful preflight confirms:

- the Codex configuration is complete and the two providers use different channels
- the isolated `CODEX_HOME` reports ChatGPT authentication through both `codex login status` and App Server `account/read`
- the effective credential backend is exactly `keyring`, filesystem secret storage is disabled, and no `auth.json` or sibling credential artifact exists
- App Server `account/read` reports a ChatGPT account with a nonempty email and supported plan; only a domain-separated digest is retained in policy state
- `OPENAI_API_KEY` is absent from the service environment
- Codex CLI `0.153.4`, the launcher, native arm64 binary, generated experimental schema bundle, and server request methods match the reviewed pins
- App Server reports `gpt-5.6-sol`, provider `openai`, Ultra reasoning, and the requested permission profile without fallback, and reports no administrator configuration requirements
- the dedicated Discord token resolves to the exact configured bot and application
- Discord returns the exact configured guild and a non-obfuscated `GUILD_TEXT` channel
- the bot is a current, non-pending, non-timed-out, non-owner member whose effective permissions include required mask `0x0000004800010c40`, whose guild roles contain none of the forbidden guild capabilities, and whose configured-channel permissions contain none of the forbidden extra capabilities
- the `@everyone` channel overwrite explicitly denies Manage Threads, Create Public Threads, and Create Private Threads; only the configured bot's member overwrite restores Create Public Threads; no other role or member overwrite restores any of those bits; and the bot has all six required permissions
- public trust keeps `@everyone` View Channel effective; owner-private trust instead proves an explicit `@everyone` View deny, exact owner and bridge member View allows, no other role or member View allow, and no other effective reader
- `GET /guilds/{guild_id}/channels` and `GET /guilds/{guild_id}/threads/active` expose only the configured channel, its exact declared parent category when present, and its active public child threads to the bot; any unrelated channel, category, or active thread fails preflight
- the working directory exists
- the requested permission profile is exact; `danger-full-access` requires the exact acknowledgment independently of channel trust
- the canonical Vault P0 source and private mode `0400` snapshot match their bound hashes
- the canonical hook source closure, private read-only runtime snapshot, manifest, and isolated hook file match their bound hashes, and `hooks/list` reports exactly the three reviewed definitions with no warning, error, or extra entry
- the configured Codex worker count is between one and four

Preflight and runtime derive a domain-separated hash from the email and plan reported by official App Server `account/read`. The email is not logged. The digest joins the policy fingerprint, so changing the isolated ChatGPT principal cancels stale queued work, marks stale running work uncertain, and prevents old managed-thread and Codex-session routing from resuming under the new login. This binds durable state to the principal reported by the official authenticated client; it does not replace Keychain or OpenAI authentication.

Preflight also prints warnings that still need human review, including Discord account MFA and public-channel visibility when public trust is selected.

The same Discord permission calculation runs at daemon startup, Gateway READY, Gateway RESUMED, every five minutes, and after `CHANNEL_CREATE`, `CHANNEL_UPDATE`, `CHANNEL_DELETE`, `THREAD_CREATE`, `THREAD_UPDATE`, `THREAD_DELETE`, `THREAD_LIST_SYNC`, `GUILD_CREATE`, `GUILD_UPDATE`, `GUILD_DELETE`, `GUILD_ROLE_CREATE`, `GUILD_ROLE_UPDATE`, `GUILD_ROLE_DELETE`, `GUILD_MEMBER_ADD`, `GUILD_MEMBER_REMOVE`, or `GUILD_MEMBER_UPDATE`. Owner-private mode repeats its exact private-channel reader proof at those same boundaries. Every security event must identify the configured guild; a foreign-guild event fails closed. A permission or audience proof failure terminates the bridge, clears readiness, and cancels every worker. Launchd may retry the complete service, but the bridge cannot become ready until the checks pass.

## 7. Verify the Codex service in Discord

Inspect the LaunchAgent:

```sh
launchctl print gui/$UID/com.discoparty.codex-discord-bridge | head -30
```

A loaded LaunchAgent is not enough. The installer waits up to 45 seconds for a fresh, private `state_dir/ready.json` marker that contains the current process and instance identity. Before publishing it, Gateway READY must match the configured bot and application and report exactly one guild, the configured guild. The bridge publishes the marker only when the Gateway has passed READY or RESUMED permission verification and every configured App Server worker slot has passed initialization, account, model, permission-profile, shared-skill, and sealed-policy checks. Installer preflight has already performed the deeper ephemeral-thread policy probe. The bridge removes the marker if either side or any worker slot stops being ready. Live Discord verification is still required.

Post a message from the configured owner account in the Codex channel:

```text
Report your current working directory and do not modify anything.
```

Send this only after installation and service bootstrap. On first activation, Disco Party records the newest existing root-channel message as its baseline without executing history. This prevents old owner messages from becoming new jobs.

Verify the end result in Discord:

1. The Codex bot adds an eyes reaction.
2. A public thread is created beneath the message.
3. The reply appears in that thread.
4. A later owner reply in the thread receives a context-aware answer.
5. A message from a different Discord account receives no reaction, thread, or worker run.

The last check is part of the security acceptance test. Use a harmless prompt and verify that no job was created for it.

### Read-only local monitor

Attach to the optional monitor:

```sh
tmux attach -t discoparty-codex
```

The monitor reads the private SQLite ledger and shows recent owner messages, job states, and delivery states. It cannot submit turns or control the App Server. Closing the monitor does not stop the LaunchAgent. Detach with `Ctrl-b d`.

You can also render one snapshot directly:

```sh
PYTHONPATH=. python3 -m codex_discord_bridge.monitor --once
```

## 8. Choose the Codex authority level

Disco Party's configuration names are compatibility settings. OpenAI explains the upstream security model in [Agent approvals and security](https://learn.chatgpt.com/docs/permissions), and the [Codex configuration reference](https://developers.openai.com/codex/config-reference) documents custom permission profiles.

### Safer default

```toml
sandbox_mode = "workspace-write"
full_computer_access_accepted = false
```

The compatibility value `workspace-write` selects Disco Party's custom `discoparty-workspace-only` profile. It extends `:workspace`, denies filesystem `:root`, allows only the profile's minimal read set and configured runtime workspace, denies both temporary-directory aliases, and disables agent-tool network access. Use the narrowest working directory that contains the required work.

This profile still lets Codex execute permitted commands and modify content inside the configured workspace. A prompt injection can therefore damage or rewrite that workspace even when it cannot reach the separated Disco Party control plane. Use version control and recoverable backups.

Workspace-write mode requires project config layers to remain disabled, all verified Git roots to remain untrusted, App Server instruction sources to be empty, and administrator configuration requirements to be absent. The exact allowed layer order is reviewed session flags, optional disabled project layers from canonical `.codex` ancestors inside the untrusted Git root, the isolated user layer, and an empty `/etc/codex/config.toml` system layer. Active project, MDM, enterprise, legacy managed, packaged, duplicate, reordered, or unknown layers fail. The effective shell environment policy must not inject variables, and the expanded safe permission profile must still deny root reads and network access. Workspace-write mode disables MCP servers, apps, web search, Browser, Computer Use, plugins, every unreviewed hook, image generation, multi-agent, local automation, skill search, skill dependency installation, and every skill except the exact canonical bound Vault closures. It keeps only the exact canonical Vault security, em dash, and deny-only outbound hooks enabled. `thread/start` sends `dynamicTools: []`. It deliberately omits empty `environments` and `selectedCapabilityRoots` fields because those empty fields break Codex CLI `0.151.0` runtime-root resolution.

The installer creates an isolated skill bridge with canonical links for ELI5, VinayTalks, triage, and skill-finder. It never copies skill content. Disco Party hashes those four closures and rechecks them before and immediately after each turn starts. ELI5 requests inject ELI5 and VinayTalks, asset or artifact creation injects VinayTalks, triage requests inject triage, and skill-finder supports general routing. Danger-full-access mode also injects the hash-bound canonical Vault `CLAUDE.md` bootstrap. Skill-finder can read the broader live Vault library through full shell access, but those additional files are not included in the four-skill policy manifest.

### Explicit full computer access

```toml
sandbox_mode = "danger-full-access"
full_computer_access_accepted = true
```

For non-interactive installation, also set the exact acknowledgment:

```sh
export DISCOPARTY_CODEX_SANDBOX_MODE=danger-full-access
export DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED
```

This selects the official `:danger-full-access` profile and gives the headless Codex process uncontained authority as the logged-in macOS user. It may be used with either `public` or `owner_private`; the channel setting controls destination visibility rather than execution authority. Owner-private deployments separately require the exact private-channel topology and Server Members privileged intent described above.

Disco Party still validates the exact canonical Vault Hooks. They are guardrails for supported paths, not a replacement sandbox. In Codex CLI `0.151.0`, a hook launch failure, timeout, kill, malformed output, serialization failure, or other non-2 error can let the tool continue. App Server can stop later work after observing the failed hook event, but it cannot undo an effect that already happened.

Danger-full-access mode automatically hashes and injects the canonical Vault `CLAUDE.md` from outside the isolated working directory and injects skill-finder on every turn. Project configuration, ambient MCP servers, apps, plugins, bundled skills, skill search, multi-agent, and client-supplied `dynamicTools` remain disabled. A live child-agent canary did not produce a child lifecycle the bridge could attest, so descendants stay off pending a reviewed lifecycle and hook-event design. OpenAI's [Browser documentation](https://learn.chatgpt.com/docs/browser) says Browser is unavailable in Codex CLI, and [Computer Use](https://learn.chatgpt.com/docs/computer-use) is a separate ChatGPT desktop plugin. This headless App Server bridge does not receive those visual hosts.

The acknowledgment is a risk-acceptance gate, not an operating-system sandbox. It records that the owner accepts the remaining same-user and hook-failure risk.

A separate macOS identity, dedicated machine, or independent capability broker remains the stronger design when same-user containment is required.

### Admission and storage limits

The defaults shown in the configuration example are enforced before work is accepted or delivered:

- `max_messages_per_minute = 5` and `max_messages_per_hour = 30` limit accepted owner events. They inherit `[runtime]` when omitted.
- `max_concurrent_workers = 3` runs independent Discord destinations in parallel. The accepted range is 1 through 4. One destination remains strictly ordered, and an uncertain job blocks later work in that same destination.
- `max_pending_jobs = 100` counts queued, running, and uncertain jobs.
- `max_input_chars = 12000` rejects oversized message content before job creation.
- `retention_days = 30` prunes completed, failed, cancelled, and eligible old uncertain jobs plus their related SQLite session, cursor, and delivery state. A root mapping is retained while a recent or active child job still needs its Discord thread.
- `max_database_bytes = 268435456` blocks new admission and new delivery manifests when the logical SQLite capacity is reached.

Limit rejection is quiet in Discord and recorded in service logs. Do not raise a limit without reviewing destination exposure, database growth, model cost, and backlog risk.

These two storage controls apply only to Disco Party's logical SQLite ledger. `max_database_bytes` is not a filesystem quota and does not count the WAL, service logs, or other state files. Codex App Server threads are persisted separately under the isolated `CODEX_HOME`; their rollout and transcript state is not pruned by `retention_days` and is not counted by `max_database_bytes`. Inspect and manage that private state separately, especially when full-access tool results may contain sensitive data.

## 9. Understand Codex approvals

The headless bridge cannot safely relay an App Server approval prompt into a public Discord channel and wait indefinitely. Its policy is:

1. App Server command, file, tool, elicitation, and permission approval requests are declined or aborted.
2. For an action covered by workspace or personal approval rules, Codex replies with the exact draft or action manifest and stops.
3. A later message must come through the same exact owner-only Discord ingress.
4. That message must explicitly approve the exact action, target, and content.
5. `go`, `continue`, `proceed`, third-party page text, and messages from other users do not qualify.

This is a model and instruction contract, not a cryptographic approval token or an authorization boundary. It cannot prevent a prompt-injected or mistaken action that runs within the active permissions. Require a deterministic hash-bound gate for every external send and other high-impact action. Claude's owner-bound button flow provides stronger review evidence, but its returned Discord reference is also not a one-time send capability.

## 10. Claude identity persistence

The Claude listener loads its protocol from `cx-chat-listener/CLAUDE.md`. The tmux session starts with that directory as its working directory so Claude Code discovers the identity at startup and after `/compact` or `/clear`.

Two user-scoped hooks reinforce it:

1. `cx-chat-listener/hooks/precompact-identity.sh` injects the identity before compaction.
2. `cx-chat-listener/hooks/userpromptsubmit-anchor.sh` adds a short listener reminder to each inbound prompt.

Register them in `~/.claude/settings.local.json` as described below, replacing the repository placeholder with an absolute path:

```json
{
  "hooks": {
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "<absolute-path-to-repo>/cx-chat-listener/hooks/precompact-identity.sh"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "<absolute-path-to-repo>/cx-chat-listener/hooks/userpromptsubmit-anchor.sh"
          }
        ]
      }
    ]
  }
}
```

These two listener-identity hooks apply to Claude only. Codex separately derives the shared canonical Vault security, em dash, deny-only outbound, and helper closure into a private read-only runtime snapshot outside every writable root. Its isolated `CODEX_HOME/hooks.json` points only to that snapshot. Disco Party validates the hook definitions with App Server `hooks/list`, binds source and snapshot hashes, and checks synchronous hook results. Codex still receives base instructions through App Server and resumes persisted Codex thread IDs from SQLite.

The Codex App Server launch uses `--dangerously-bypass-hook-trust` only for this mechanically generated, independently hashed hook set. Do not add another user, project, plugin, or session hook. OpenAI documents hooks as a guardrail for supported local tool paths, not a complete enforcement boundary. Hosted tools and some specialized paths may not invoke them. Disco Party's outbound hook is deny-only, and external send credentials remain outside the supported design.

## 11. Claude approval review and outbound sends

The installed Claude flow can post an exact draft with native Discord buttons and return an owner-authenticated review reference. It does not install a Slack, email, or other outbound adapter. The installer removes the obsolete marker-watcher because its polling lifecycle raced the request that owns the approval marker.

Do not treat the returned `channel_id:message_id` value as authorization to send. It is not durable, one-time, or replay-resistant after `request_approval.py` consumes the marker and binding. External sends remain disabled unless you separately implement and review a gate that atomically mints and consumes a short-lived private receipt bound to the full draft SHA-256, exact operation, exact target, every Discord identity, interaction, binding digest, and expiry. The gate must recompute content and destination before the side effect and keep its outbound credential unavailable to the model process.

The retained `discord-gateway/marker-watcher.py`, service templates, and `examples/slack_gate.py` are standalone legacy reference material. They are not installed, not part of the production security boundary, and not a supported way to enable outbound sends. Codex does not inherit any Claude approval path.

## 12. Upgrade the pinned Codex CLI and experimental protocol

The official [Codex App Server documentation](https://learn.chatgpt.com/docs/app-server) explains that generated schemas are specific to the installed Codex version and that some methods and fields require `experimentalApi`. Disco Party opts in because the user has explicitly chosen the provider, then compensates by pinning and fail-closed validation. The reviewed baseline is Codex CLI `0.153.4`, `gpt-5.6-sol`, provider `openai`, and Ultra reasoning.

Do not point production at a freshly released CLI without review. Use this process:

1. Read the official [ChatGPT and Codex changelog](https://learn.chatgpt.com/docs/changelog) and the linked release notes.
2. Record the current `SUPPORTED_CODEX_VERSION`, launcher path and hash, native binary path and hash, schema bundle hash, expected server request method set, model, provider, effort, and custom permission profile.
3. Stop the Codex LaunchAgent before changing its binary.
4. Install an explicit candidate version, not an unpinned moving target.
5. Generate the candidate schema bundle with `codex app-server generate-json-schema --experimental --out <review-directory>`.
6. Review every schema change, especially new server-to-client request methods, approval shapes, permission fields, sandbox fields, authentication behavior, model fallback, and feature defaults.
7. Update the request handler so every new server request has an explicit safe response. Unknown requests must continue to fail closed.
8. Update the version and cryptographic pins only after the review.
9. Run both unit suites, the Codex preflight, and the opt-in approval evaluation on a non-production destination.
10. Restart the LaunchAgent and repeat the owner, non-owner, resume, public-output, and delivery-reconciliation acceptance tests in Discord.

A CLI update that makes preflight fail is expected. It means the safety pin worked. Do not bypass the check just to restore service.

## 13. Remove one provider

Remove only the Codex LaunchAgent, monitor, and dedicated Keychain entry:

```sh
bash uninstall.sh --codex
```

The Codex removal leaves the Claude services, shared `config.toml`, Codex noncredential state directory, and repository service logs in place. This preserves audit and reinstall information. By default it stops the service and runs the official logout scoped to Disco Party's isolated `CODEX_HOME`, then verifies that the CLI reports no login, no filesystem credential artifact exists, and the scoped Keychain item is absent. Use `--keep-chatgpt-login` only when you explicitly intend to retain that ChatGPT login. Use `--keep-keychain` separately when rotating the service without deleting the Codex Discord bot credential. Delete retained state and logs manually only when you intend to remove the ledger and log history.

Remove the original Claude services with:

```sh
bash uninstall.sh
```

That command does not remove Codex. Remove each provider explicitly before deleting the shared repository.

## Troubleshooting

### Claude listener does not pick up messages

Confirm `discoparty-chat` exists and that Claude Code has the Discord plugin attached. Verify the configured Claude channel ID and inspect `discord-gateway/logs/client.log`.

### Codex message gets no eyes reaction

Check these in order:

1. The message came from the exact configured owner user ID.
2. It is in the exact Codex channel or a thread the bridge created.
3. The dedicated bot can view the channel, read history, add reactions, create public threads, and send in threads.
4. Message Content Intent is enabled for the Codex bot.
5. `launchctl print gui/$UID/com.discoparty.codex-discord-bridge` shows the service.
6. Codex preflight passes.

The rendered LaunchAgent writes to `logs/codex-discord-bridge.stdout.log` and `logs/codex-discord-bridge.stderr.log` under the repository root.

### Codex preflight blocks after a CLI update

The installed CLI no longer matches the reviewed binary or schema pin. Follow the upgrade process above. Reinstalling or restarting does not make protocol drift safe.

### Codex monitor is empty

The monitor is read-only and waits for `jobs.sqlite3`. Confirm the state directory matches `[codex].state_dir`, then send a valid owner message through Discord.

### Gateway reconnects repeatedly

Check the bot token, Message Content Intent, and Discord permissions. The Codex bridge prefers Gateway RESUME and stores a conservative IDENTIFY budget on disk. If that ledger is corrupt, it refuses a new IDENTIFY instead of resetting the counter in memory.

### A Codex response was redacted

Disco Party preserves the useful response and attempts to mask matching spans. It tries to mask credentials and valid payment-card numbers in every mode; public mode also tries to mask personal values and structured private details. Owner-private mode may return requested personal information after the exact private-channel reader proof. This is best-effort redact-never-withhold DLP, not a confidentiality boundary. A long response is truncated at the delivery ceiling with a visible note.

### Keychain prompts repeatedly

macOS may ask when a new executable context first reads an entry. Approve only the expected Disco Party launcher or service. The two bot tokens must remain in their separate accounts.

## Tests

```sh
python3 -m unittest discover -s discord-gateway/tests -t discord-gateway -v
PYTHONPATH=. python3 -m unittest discover -s codex-discord/tests -v
bash codex-discord/tests/test_install_codex.sh
```

These are mocked or local tests. They do not prove that a live Discord bot, ChatGPT login, or public thread works. Complete the end-to-end Discord verification separately.

## Linux status

The Python components and original systemd templates are portable, but the install scripts are macOS-first. The Claude path depends on tmux and needs a Linux secret manager. The Codex installer currently requires the reviewed Apple M5 Max host, a macOS LaunchAgent, and Keychain, so it does not have a supported Linux install path.
