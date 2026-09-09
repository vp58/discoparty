# Disco Party architecture

Disco Party supports two Discord orchestrators with separate transport and state paths. They must not share bot identities, channels, or model sessions. They do share one macOS account, so this design is not hard operating-system isolation.

The Claude provider preserves the original interactive listener design. The Codex provider is a headless, event-driven bridge built on OpenAI's official [Codex App Server](https://learn.chatgpt.com/docs/app-server).

## The orchestration layer

Disco Party is the control plane around the agents. Discord is the remote interface. Claude Code and Codex are the workers.

The orchestrator owns the parts a model session should not have to improvise: exact ingress authorization, provider and machine routing, durable task identity, concurrency, conversation resumption, delivery evidence, retries, and crash recovery. That is what lets one front door stay responsive while longer tasks run elsewhere.

```text
Discord event
    -> authorize owner and immutable route
    -> persist task before execution
    -> dispatch to the correct provider worker
    -> preserve per-thread ordering
    -> freeze and deliver the result
    -> resume the same conversation on the next reply
```

Claude and Codex use different worker implementations. Claude's listener launches a background Agent subagent for each dispatched turn. Codex uses a bounded pool of App Server processes, with one active job per Discord thread. Codex subagents remain disabled because the bridge cannot attest their descendant lifecycle and policy events.

The durable orchestration state is shared in purpose, not format. Claude uses append-only Markdown plus a JSON registry. Codex uses SQLite plus persisted Codex thread IDs. Provider credentials and model sessions stay separate. A deliberately shared working directory can carry artifacts between providers, and Discord can carry the human-visible handoff.

## Machine topology

One Discord server may coordinate several computers, but each provider and machine needs a dedicated bot, channel, runtime, and state path. Several machines consuming one bot and channel could accept the same event and duplicate side effects. The safe current topology is one server with routes such as `#claude-work-mac` and `#chatgpt-home-m5`, not several workers racing on one route.

## Provider boundary

| Boundary | Claude | Codex |
| --- | --- | --- |
| Discord application | Dedicated Claude application | Dedicated Codex application installed for one server |
| Bot token | Keychain account `discord-bot-token` | Keychain account `discord-bot-token-codex` |
| Listen channel | `[discord].chat_channel_id`, recommended `#claude` | `[codex].channel_id`, recommended `#chatgpt`, must differ |
| Who may start work | Exact configured owner only | Exact configured owner only |
| Local control plane | Interactive Claude Code tmux | Headless Python LaunchAgent |
| Model connection | Claude Code Discord plugin and Agent tool | Codex App Server over local stdio JSONL |
| Conversation state | Markdown and JSON registry | Codex thread IDs and SQLite ledger |
| Human view | Live `discoparty-chat` tmux | Optional read-only `discoparty-codex` monitor |
| Approval path | Native buttons produce owner-verified review evidence; no outbound adapter is installed | App Server requests denied, exact later owner message required |

Separate Keychain accounts reduce accidental credential crossover. They do not prevent a same-user process from attempting to access both entries. Preflight compares tokens only when it can discover the standard Claude token source.

## Component map

```text
                              PUBLIC DISCORD SERVER

  #claude                                             #chatgpt
        |                                                    |
        v                                                    v
+--------------------+                              +--------------------+
| Claude Discord     |                              | Dedicated Discord  |
| plugin             |                              | Gateway connection |
+---------+----------+                              +---------+----------+
          |                                                   |
          v                                                   v
+----------------------------+                     +----------------------------+
| Interactive Claude listener|                     | Exact ingress authorization|
| in discoparty-chat tmux     |                     | guild, channel, owner, bot,|
|                            |                     | app, event and message type|
+-----------+----------------+                     +-------------+--------------+
            |                                                        |
            v                                                        v
+----------------------------+                     +----------------------------+
| dispatch.py                |                     | jobs.sqlite3               |
| markdown transcript        |                     | jobs, sessions, cursors,   |
| JSON thread registry       |                     | leases, manifests, nonces  |
+-----------+----------------+                     +-------------+--------------+
            |                                                        |
            v                                                        v
+----------------------------+                     +----------------------------+
| Claude Agent worker        |                     | Codex App Server           |
| background subagent        |                     | local stdio, headless      |
+-----------+----------------+                     +-------------+--------------+
            |                                                        |
            v                                                        v
      Discord thread                                  public-output filter
                                                               |
                                                               v
                                                        Discord thread

Claude outbound draft -> button gateway -> verified review reference
                                                  -> no automatic sender
```

## Claude provider

### Listener tmux session

`discoparty-chat` contains one Claude Code session with the Discord plugin. Its identity comes from `cx-chat-listener/CLAUDE.md`, with PreCompact and UserPromptSubmit hooks as additional anchors.

The listener does not perform the requested work inline. For a top-level message it calls `conversations/dispatch.py`, creates a Discord thread and markdown conversation, then starts a background Agent worker. For a reply it appends the user turn and starts another worker with the stored transcript.

`launchd/cx-chat-healthcheck.sh` checks the tmux session every five minutes and restarts it when missing. The tmux session is both runtime and local observability surface.

### Conversation state

Claude conversations live at `<workspace_root>/conversations/active/<session_id>.md`. YAML frontmatter contains the Discord channel and thread IDs, timestamps, message count, status, and the local session ID. The body is append-only markdown.

A small `_registry.json` maps a Discord thread ID to a conversation ID. `python3 conversations/cli.py regen-index` rebuilds it from the files.

### Claude approval review lifecycle

The button flow is separate from normal Discord replies:

1. A worker freezes the exact outbound draft and computes its SHA-256 digest.
2. `request_approval.py` posts the exact draft with native Approve and Reject buttons and waits locally.
3. The persistent `discord-gateway/client.py` receives the Discord interaction.
4. `router.py` verifies the application, guild, bot, channel, message, action, target, draft digest, binding digest, and exact `[discord].owner_user_id`.
5. `request_approval_responder.py` writes a private bound approval or rejection marker and acknowledges the interaction inside Discord's deadline.
6. The waiting `request_approval.py` process validates that marker against its private binding, removes the buttons, consumes the marker and binding, and returns a `channel_id:message_id` review reference.

The current installer deliberately removes the obsolete marker-watcher service. It does not install a Slack, email, or other third-party sender. The returned reference proves that the exact Discord review completed during that request, but it is not a durable, one-time authorization capability and must not be treated as permission to send.

A future production outbound gate must atomically mint and consume a short-lived one-time receipt under a lock. The receipt must bind the complete draft SHA-256, exact action, target, owner, application, guild, bot, channel, message, interaction, binding digest, and expiry. The gate must recompute the exact draft and destination before the side effect, reject replay, and receive content through a private exchange rather than process arguments. A stronger isolation boundary also places that gate and its outbound credential under a separate operating-system identity that the full-access model process cannot read or invoke directly.

## Codex provider

### Service topology

`com.discoparty.codex-discord-bridge` runs `PYTHONPATH=. python3 -m codex_discord_bridge.main` under launchd. One process owns:

- a persistent Discord Gateway WebSocket
- one durable SQLite store
- one sequential job worker
- one local Codex App Server child process

The bridge holds an exclusive file lock so a second process cannot become another worker against the same state directory.

The installer derives an immutable runtime path from the CPython major and minor version, the pinned `websockets` version, and the SHA-256 of `requirements-macos-arm64.lock`. It builds a new venv in a private sibling staging directory with required hashes and binary-only wheels, verifies installed-distribution records and a private manifest, then publishes it atomically to `state_dir/runtime-venv-cpython-<major.minor>-websockets-<version>-<lock-sha256>`. An existing exact path is verified and reused rather than modified. The LaunchAgent runs that venv's Python. This removes ambient user-site packages from the service dependency path, but it is not a same-user tamper boundary under full access.

The optional `discoparty-codex` tmux session runs only `codex_discord_bridge.monitor`. It opens SQLite read-only and never talks to Discord or App Server. The LaunchAgent continues after the monitor is detached or closed.

The bridge owns a private `ready.json` marker. It is written atomically only while the Gateway has passed READY or RESUMED identity and permission checks and the worker has a verified App Server process. It is removed when either readiness event clears or the bridge exits. The installer requires a fresh mode `0600` marker with a current PID, instance ID, and start time within 45 seconds. `launchctl print` proves only that launchd loaded the job.

### Event-driven ingress

The Codex adapter is not a cron job. Discord pushes Gateway events over WebSocket. The bridge heartbeats, reconnects with exponential backoff capped at 60 seconds, and uses Gateway RESUME when it still has a valid in-memory session and sequence.

Socket reading and heartbeats run independently from event processing. The read loop handles Discord control opcodes and places dispatches into a bounded `asyncio.Queue` with capacity 1,000. One serial dispatch worker performs READY reconciliation, permission verification, message admission, Discord REST calls, and SQLite writes. A full queue raises immediately, aborts the socket, and reconnects from durable cursors. Slow REST or storage work therefore cannot silently block the heartbeat loop.

Gateway READY must match the configured bot and application and list exactly one unique guild, the configured guild. Empty, duplicate, malformed, or additional guild entries fail closed. This requires the Codex bot to remain dedicated to one server before reconciliation starts.

On a new IDENTIFY, the adapter first reserves from `identify-ledger.json`. The ledger survives launchd restarts and defaults to 20 IDENTIFY operations per rolling hour and 400 per rolling day. RESUME does not consume it. An unreadable ledger records a full 24-hour block instead of assuming zero prior usage. A crash loop therefore cannot reset the budget by resetting an in-memory counter.

Before the first Gateway connection begins, the bridge bootstraps the root channel cursor to the newest existing message without executing channel history. Only messages sent after that activation boundary are eligible. After READY, the bridge reconciles later messages through Discord REST. Each managed channel has a durable snowflake cursor in SQLite, and the cursor advances only after processing. This closes the gap between a socket disconnect and reconnect without turning normal operation into polling.

### Exact authorization

For a top-level Codex message, every check must pass:

1. Event ID is a numeric Discord snowflake.
2. Event type is `MESSAGE_CREATE`.
3. Gateway receiving bot ID equals `[codex].bot_user_id`.
4. Gateway application ID equals `[codex].application_id`.
5. Ingress policy version is exactly supported.
6. Discord message type is a supported default or thread reply type.
7. Guild ID equals `[codex].guild_id`.
8. Channel ID equals `[codex].channel_id`.
9. Author ID equals `[codex].owner_user_id`.
10. The author is not a bot.
11. The event did not come from a webhook.
12. Content is not empty.

A reply is accepted only in a thread recorded as managed by this bridge, then receives the same checks with that exact thread ID. Human-readable names and Discord roles are not authorization inputs.

### Discord identity, permissions, and public baseline

Preflight and runtime verification fetch these official Discord REST resources with the dedicated bot token:

1. `GET /users/@me`
2. `GET /oauth2/applications/@me`
3. `GET /channels/{channel_id}`
4. `GET /guilds/{guild_id}`
5. `GET /guilds/{guild_id}/members/{bot_id}`
6. `GET /guilds/{guild_id}/channels`
7. `GET /guilds/{guild_id}/threads/active`

Parsing is strict and fail closed. The verifier requires the exact configured bot, application, channel, and guild; a `GUILD_TEXT` channel; no `CHANNEL_OBFUSCATED` flag; known roles and overwrite types; canonical snowflakes and permission bitfields; and an active bot membership that is neither pending nor timed out.

The parser implements Discord's documented base `@everyone` and assigned-role union, channel `@everyone` overwrite, combined role overwrites, member overwrite, and owner or Administrator semantics. Disco Party then applies a stricter least-authority rule. The bot must not own the guild. Its guild roles may not grant administrative, moderation, audit, analytics, role, webhook, expression, event, thread-management, voice-moderation, or related management capabilities. The configured channel's effective permissions are checked against that same forbidden set plus Create Instant Invite, Send TTS Messages, Attach Files, Mention Everyone, Create Private Threads, Send Voice Messages, Send Polls, Use External Apps, and Pin Messages.

Its effective channel permissions must include required mask `0x0000004800010c40`, which contains View Channel, Read Message History, Add Reactions, Send Messages, Create Public Threads, and Send Messages in Threads. The `@everyone` channel overwrite must explicitly deny Manage Threads, Create Public Threads, and Create Private Threads. Only the configured bot's member overwrite may restore Create Public Threads. Role overwrites and other member overwrites may not restore any of the three thread capabilities, and the bot member overwrite may not restore management or private-thread authority. In `public` mode, View Channel remains effective for `@everyone`. In `owner_private`, the parent channel must explicitly deny `@everyone` View Channel, grant it through exact member allows only to the configured guild owner and dedicated bridge, contain no other role or member View allow, and have no other effective reader. See Discord's official [permission hierarchy](https://docs.discord.com/developers/topics/permissions), [channel resource](https://docs.discord.com/developers/resources/channel), and [thread behavior](https://docs.discord.com/developers/topics/threads).

The bridge verifies this state before its first Gateway connection, at READY, at RESUMED, and every 300 seconds. It also rechecks after `CHANNEL_CREATE`, `CHANNEL_UPDATE`, `CHANNEL_DELETE`, `THREAD_CREATE`, `THREAD_UPDATE`, `THREAD_DELETE`, `THREAD_LIST_SYNC`, `GUILD_CREATE`, `GUILD_UPDATE`, `GUILD_DELETE`, `GUILD_ROLE_CREATE`, `GUILD_ROLE_UPDATE`, `GUILD_ROLE_DELETE`, `GUILD_MEMBER_ADD`, `GUILD_MEMBER_REMOVE`, and `GUILD_MEMBER_UPDATE`. Each security event must carry the configured guild ID; a foreign-guild event fails closed. Owner-private mode repeats its exact private-channel reader proof at the same boundaries. A permission or audience proof failure terminates the Gateway task, clears readiness, and causes the service supervisor to cancel every App Server worker. Launchd may retry the whole bridge, which cannot become ready until the checks pass. Public baseline does not guarantee visibility for a member who has a special deny.

The verifier also enumerates the guild's channels and active threads. The bot must have effective View Channel only on the configured `#chatgpt` channel, its exact declared `GUILD_CATEGORY` parent when present, and active `PUBLIC_THREAD` children whose parent is that exact channel. The parent-category exception exposes category metadata and cannot carry messages. A visible unrelated category, other guild channel, private thread, announcement thread, or public thread under another parent fails verification. This limits the payloads available to the Gateway's `GUILDS`, `GUILD_MESSAGES`, and privileged `MESSAGE_CONTENT` intents. See Discord's official [Gateway intents](https://docs.discord.com/developers/events/gateway#gateway-intents) and [Guild resource](https://docs.discord.com/developers/resources/guild).

### Root message transaction

A top-level message crosses several systems, so the order limits half-created work:

1. Store an immutable SQLite job reservation with `ready=0`.
2. Add the eyes reaction.
3. Find or create the public Discord response thread.
4. Save both the event-to-thread and managed-thread mappings.
5. Set the job to `ready=1`.
6. Let the worker claim it.

If the process stops before step 5, startup reconciliation fetches the reserved source message and completes the thread mapping. A duplicate event ID with changed guild, channel, author, or content is rejected as a replay conflict.

Admission is also bounded in the same SQLite transaction. Defaults are 5 accepted messages per minute, 30 per hour, 100 queued, running, or uncertain jobs, and 12,000 input characters. Completed, failed, cancelled, and eligible old uncertain jobs older than 30 days are pruned during admission, together with related SQLite routing and delivery state. A root and thread mapping stays while a recent or active child job still depends on it. New jobs are rejected when logical database usage reaches 268,435,456 bytes. These values are configurable under `[codex]`.

Those retention and capacity rules govern Disco Party's SQLite ledger. App Server persists non-ephemeral Codex thread and rollout state separately under the isolated `CODEX_HOME`. Disco Party does not currently prune that provider-managed state or count it toward `max_database_bytes`, so it can outlive the corresponding SQLite mapping and grow independently.

### Durable job ownership

Each worker slot claims a ready queued job in a SQLite `BEGIN IMMEDIATE` transaction. The default pool has three independently supervised App Server processes and may be configured from one through four. A claim records:

- a unique process owner string
- a monotonically increasing fencing generation
- a renewable lease
- the running state

The claim transaction excludes any destination that already has a running or uncertain job. This keeps one Discord thread strictly ordered while allowing jobs for different threads to run concurrently. The lease is renewed during the App Server turn. Completion succeeds only when event ID, process owner, and fencing generation still match. If a worker disappears or the lease expires, the next service instance moves the job to `uncertain` instead of rerunning it automatically. That unresolved destination stays blocked until reconciliation or review. This avoids repeating local or external effects whose result was lost during the crash.

Every durable job, managed Discord thread mapping, Codex session scope, and delivery manifest is bound to a policy fingerprint. The fingerprint covers immutable Discord identities, the resolved workspace, sandbox mode, model, OpenAI provider, Ultra effort, rendered thread policy, built-in Disco Party base-instruction hash, reviewed Codex version, native binary hash, experimental schema hash, the domain-separated ChatGPT `account/read` binding, the sealed canonical Vault P0 source and snapshot hashes, the exact shared-skill closure, and optional trusted-instruction path and content hash. A queued job from another fingerprint is cancelled, a running job becomes uncertain, and old managed threads, Codex sessions, and prepared deliveries are not resumed under the new policy. A login-principal change therefore crosses the same durable policy boundary without writing the reported email to the ledger or logs.

### App Server lifecycle

OpenAI describes App Server as the interface used to power rich Codex clients, with authentication, conversation history, approvals, and streamed agent events. Disco Party starts it as a child process over local stdio with `--strict-config`.

The client sends:

1. `initialize` with `experimentalApi: true`
2. the `initialized` notification
3. `thread/start` for a new Discord thread or `thread/resume` for a saved Codex thread
4. `turn/start` with the owner message
5. `turn/interrupt` if a turn must be stopped

The App Server docs state that experimental methods and fields require explicit capability opt-in and that generated schema artifacts are version-specific. Disco Party pins Codex CLI `0.153.4`, the launcher, native arm64 binary, full generated schema bundle, expected server request method set, `gpt-5.6-sol`, provider `openai`, and Ultra reasoning. See the official [App Server protocol documentation](https://learn.chatgpt.com/docs/app-server) and [ChatGPT and Codex changelog](https://learn.chatgpt.com/docs/changelog).

The current online App Server documentation describes `perCwdExtraUserRoots` for `skills/list`, but the installed `0.151.0` generated schema does not expose that request field and silently ignores it. The installed schema instead exposes `skills/extraRoots/set`. Disco Party avoids relying on either behavior by creating a private, exact four-link skill bridge inside the isolated `CODEX_HOME` and requiring `skills/list` to return only the canonical skill-finder, ELI5, VinayTalks, and triage paths. Skill-finder is injected on every turn. In full mode it can read the broader live Vault through ordinary shell access, but those discovered files are outside the four-skill policy manifest. A live `0.151.0` probe previously accepted explicit `{type: "skill"}` turn items for the ELI5 and VinayTalks paths; the four-skill runtime remains a live release canary. The schema also advertises `thread/items/list`, but the installed server returns `-32601` for that method, so Disco Party does not claim post-turn item pagination as verification evidence.

Unknown server requests fail closed. Known approval, tool, elicitation, and permission requests receive explicit deny, abort, empty, or unsuccessful responses. The LaunchAgent keeps descendants in its managed process group. The bridge also starts App Server in a dedicated process session and signals that group during shutdown so tools are not left behind and stale descendant PID snapshots cannot target reused PIDs.

### Authentication boundary

The installer keeps the real canonical macOS `HOME` because the official keyring backend needs the user's default Keychain. It creates a private `CODEX_HOME` at `state_dir/home/.codex`, writes the only user config App Server may load, requires the exact `keyring` credential backend, disables filesystem secret storage, and performs the official ChatGPT browser login in that `CODEX_HOME` scope. Normal `~/.codex` credentials and config are intentionally not reused.

For Codex CLI `0.151.0`, effective-config verification requires the exact reviewed session-flags layer first, followed only by zero or more disabled project layers whose canonical `.codex` folders are valid ancestors inside the untrusted Git root, then the exact isolated user layer, and finally an empty `/etc/codex/config.toml` system layer. Active project, MDM, enterprise, legacy managed, packaged, duplicate, reordered, or unknown layers fail closed. The verifier also requires an inert effective shell environment policy with no injected `set` values and rechecks the expanded permission profile, including root deny and network disabled.

Before App Server starts, Disco Party rejects `auth.json` and sibling credential artifacts without reading them, then requires the isolated `codex login status` to report a ChatGPT login. The same filesystem-credential rejection runs after the status command, after App Server initialization, around principal reads and refresh handling, and before and after turns.

After protocol initialization, Disco Party calls `account/read` and requires exactly a ChatGPT account with a nonempty email and supported plan value. It creates a domain-separated hash of those nonsecret facts, never logs the email, and rechecks that binding before and after work. The child environment is rebuilt from a small allowlist containing locale, terminal, timezone, path, the canonical user home, isolated Codex home, and workspace-local temporary-directory values. It does not inherit the Codex Discord token, `OPENAI_API_KEY`, proxy credentials, or unrelated launchd secrets.

This uses the user's Codex access through their ChatGPT plan. It is not a proxy that extracts OAuth material and turns it into an OpenAI-compatible API key. The `account/read` comparison binds Disco Party state to the principal reported by the authenticated official client. The official Codex client, macOS Keychain, and OpenAI connection perform credential storage and upstream authentication. See OpenAI's official [Codex authentication documentation](https://learn.chatgpt.com/docs/auth).

Environment allowlisting reduces accidental propagation of launchd secrets. Isolated `CODEX_HOME` prevents normal Codex authentication scope from being reused, but it is not a separate operating-system account. Full access therefore requires an explicit risk acknowledgment, independently of destination trust. The reviewed isolated config forces ChatGPT authentication and direct Keychain storage, pins the OpenAI provider, [`gpt-5.6-sol`](https://developers.openai.com/api/docs/models/gpt-5.6-sol), and Ultra reasoning, disables model fallback, keeps verified Git roots untrusted, and runs with `--strict-config`.

The optional trusted instruction file is loaded by Disco Party and embedded into App Server base instructions. It must be a current-user-owned, single-link regular UTF-8 file, no larger than 256,000 bytes, and outside the writable workspace by lexical, canonical, and filesystem-identity comparison. The identity check covers macOS data-volume aliases that path canonicalization does not collapse. Disco Party opens each path component without following symlinks, requires trusted root-owned or current-user-owned ancestry, and rechecks the file identity, link count, and ancestry after each read. Both modes disable project documents and require `instructionSources: []`. Danger-full-access mode automatically selects, hashes, and injects the canonical Vault `CLAUDE.md` through this external trusted-instruction path. Files from the working directory remain untrusted task content.

### Sandbox policy

Disco Party sets permissions at both thread and turn creation:

- The compatibility setting `workspace-write` selects custom profile `discoparty-workspace-only`. It extends `:workspace`, denies filesystem `:root`, keeps the minimal read set, denies both temporary-directory aliases, disables agent-tool network, and uses exactly one configured runtime workspace root with no added writable roots.
- The profile still permits command execution allowed by the profile and modification inside that workspace. It contains authority to that root; it does not protect workspace contents from a mistaken or injected task.
- Workspace-write mode disables project config layers, MCP servers, apps, web search, Browser, Computer Use, plugins, every unreviewed hook, image generation, multi-agent, local automation, skill search, skill dependency installation, and every skill except the exact canonical bound Vault closures. It enables only the isolated canonical Vault security, em dash, and deny-only outbound hook set. `thread/start` sends an empty `dynamicTools` list. Empty `environments` and `selectedCapabilityRoots` are intentionally omitted because they break Codex CLI `0.151.0` runtime-root resolution.
- The canonical bridge hash-binds ELI5, VinayTalks, triage, and skill-finder. ELI5 requests inject ELI5 and VinayTalks, artifact creation injects VinayTalks, and triage requests inject triage. Danger-full-access mode also injects the hash-bound canonical `CLAUDE.md` bootstrap. Skill-finder can route through `x_System/Skills/_index.md` using full shell access, but the broader live Vault library is not sealed by the four-skill manifest. Disco Party verifies only the four named canonical paths and closures before each turn and again immediately after the turn starts.
- Full mode also keeps `multi_agent` and `skill_search` disabled. A live child-agent canary did not produce an attestable child lifecycle, and the bridge cannot yet bind descendant hook events. Project configuration, ambient MCP servers, apps, plugins, bundled skills, client dynamic tools, desktop Browser, and Computer Use remain disabled.
- `danger-full-access` is accepted only with the exact acknowledgment. It may be paired with either `public` or `owner_private`; execution authority and destination trust are independent. It removes filesystem and agent-tool network containment. The exact official Hooks cannot restore that boundary because framework and process failures can fail open.

The installer reads the reviewed canonical Vault hook closure through stable descriptors and publishes a content-addressed private runtime snapshot outside every writable root. Snapshot directories are mode `0500`, files are single-link mode `0400`, and hook commands invoke absolute `/usr/bin/python3 -I -S` paths so the working directory, Python environment, user site, and shell startup files cannot supply code. The private user-level `CODEX_HOME/hooks.json` points only to that snapshot. App Server receives the official one-invocation hook-trust bypass only after Disco Party validates the exact definitions, source closure, runtime snapshot, and metadata. Startup and turn checks require `hooks/list` to report the exact source, matcher, command, enabled state, definition hash, timeout, and empty warnings and errors. Script bytes and helper dependencies are hashed independently because Codex's hook hash covers the definition rather than referenced file contents. Hook completion events are checked for failures, blocks, stops, and unexpected sources.

OpenAI documents that hosted tools are outside the local hook path and that specialized paths may opt out. Exact `0.151.0` tests also show that launch failures, timeouts, kills, malformed output, serialization failures, and non-2 errors allow the tool to continue. A later App Server failure event cannot undo a completed effect. Disco Party therefore treats hooks as supported-path guardrails and drift evidence only and runs the outbound hook in deny-only mode. Full access requires explicit owner acceptance of this residual risk. A Discord message, button, marker, or review reference never becomes send authority.

Configuration validation rejects a working directory that overlaps the Disco Party repository, `config.toml`, Codex state, isolated `CODEX_HOME`, trusted instruction file, canonical Vault policy source, canonical hook source, or canonical shared-skill source in either direction. Danger-full-access mode can still reach the Vault through its same-user authority, but the configured working directory remains isolated from the trusted control plane.

The official `:danger-full-access` profile removes local sandbox restrictions. Disco Party launches it only after the exact acknowledgment passes, regardless of the channel trust setting. It does not add the ChatGPT desktop app's visual Browser or Computer Use host to a third-party App Server client. OpenAI documents [Browser](https://learn.chatgpt.com/docs/browser) as unavailable in Codex CLI and documents [Computer Use](https://learn.chatgpt.com/docs/computer-use) as a separate ChatGPT desktop plugin with Screen Recording and Accessibility permissions. A future visual desktop host needs a separate design and security review.

The bridge uses `approvalPolicy: never` because there is no trusted synchronous local operator at a headless Discord prompt. In this context, `never` means App Server does not pause for an interactive escalation. It does not mean the sandbox is disabled. The sandbox choice remains independent.

See OpenAI's [Agent approvals and security](https://learn.chatgpt.com/docs/permissions) and [configuration reference](https://developers.openai.com/codex/config-reference) for the upstream sandbox, network, and custom permission-profile model.

### Exact later approval contract

Disco Party base instructions distinguish a request from permission to carry it out:

1. When an action requires approval, Codex must return the exact draft or action manifest without executing it.
2. App Server approval requests are denied rather than relayed into Discord.
3. A later message must pass the complete owner-only ingress policy.
4. The later message must explicitly approve the exact action, destination, and content.
5. Ambiguous text such as `go`, `continue`, or `proceed` is not approval.
6. Third-party content can never grant approval.

This is an instruction-enforced contract. It is not equivalent to the Claude gate's hash-bound marker and it cannot prevent a prompt-injected or mistaken action that runs within the current permissions. Treat it as workflow guidance, not an authorization boundary. Any external send or high-impact action needs a deterministic, hash-bound Codex-side gate before it is enabled.

### Audience-aware output filter

Before a Codex result reaches Discord, the bridge:

- truncates responses above the fixed 100,000-character delivery ceiling
- attempts to mask credentials, private keys, common token formats, authenticated URLs, and Luhn-valid payment-card numbers at every trust level
- in public mode, also attempts to mask personal values and structured private details
- in owner-private mode, preserves requested personal details after the exact private-channel reader proof
- removes all Discord mention parsing from outbound messages
- splits long messages while preserving code fences

The useful remainder is delivered with a note listing the categories the bridge masked. The filter is best-effort redact-never-withhold DLP, not a general classifier, complete data loss prevention product, or confidentiality boundary. Pattern misses, novel encodings, and partial matches can still disclose sensitive material to everyone who can read the destination.

### Delivery transaction

The entire filtered response is persisted before the first Discord POST:

1. Split the response into immutable chunks.
2. Hash the canonical response and every chunk.
3. Assign a deterministic Discord nonce to every chunk.
4. Store a prepared delivery manifest and all chunks in SQLite.
5. Durably record that a chunk is about to cross the Discord POST boundary.
6. POST each chunk with `enforce_nonce=true` and mentions disabled.
7. Store the Discord message ID.
8. Read the message back from Discord and compare its content hash.
9. Mark the manifest sent only when every chunk is confirmed.

If the HTTP response is lost after Discord accepted the message, a retry inside Discord's documented short nonce window uses the same nonce. After that window, Disco Party exhaustively scans the destination history and accepts only one exact message from the configured bot with the recorded nonce and content hash. An exact match is confirmed without another POST. No match, multiple matches, malformed pagination, or changed bot content quarantines the chunk as ambiguous and prevents an automatic repost. This chooses at-most-once public delivery when Discord cannot prove the outcome. If a crashed job has a complete delivery, it can move from `uncertain` to `completed` without rerunning Codex.

## Storage layout

```text
discoparty/
  agent/
    cx-chat.md
  approval/
    create_thread.py
    react.py
    request_approval.py
    request_approval_responder.py
    send_message.py
  conversations/
    cli.py
    config.py
    dispatch.py
    lib.py
  cx-chat-listener/
    CLAUDE.md
    hooks/
  discord-gateway/
    client.py
    router.py
    marker-watcher.py        # retired standalone code; not installed
    approvals/
    pending/
    completed/
    failed/
    processed-markers/
    logs/
  codex_discord_bridge/
    appserver.py
    codex_auth.py
    config.py
    discord_io.py
    identify_budget.py
    ingress.py
    main.py
    monitor.py
    preflight.py
    shared_hooks.py
    store.py
  codex-discord/
    tests/
    evals/
  launchd/
    cx-chat-healthcheck.sh
    templates/
  cx-launcher.sh
  install.sh
  install-codex.sh
  config.example.toml
```

New Codex installations default runtime state to `~/Library/Application Support/Discoparty/codex-discord/`, outside the normal `~/.discoparty` repository clone. An explicit state override or reused path must remain below the canonical `~/Library/Application Support/Discoparty` root. The installer and runtime loader independently canonicalize the path and reject a wrong owner, group or world write access, symlinks, and non-directory components from the user's canonical home through the state directory. This keeps ChatGPT auth and App Server rollouts from being redirected into another Git checkout or synced working tree. The state contains:

```text
codex-discord/
  bridge.lock
  home/
    .codex/
      config.toml
  identify-ledger.json
  jobs.sqlite3
  jobs.sqlite3-wal
  jobs.sqlite3-shm
  policy/
    vault-p0.md              # mechanically derived mode 0400 snapshot
  ready.json                 # present only while both runtime sides are ready
  workers/
    slot-1/
    slot-2/
    slot-3/
```

The state directory, `state_dir/home`, isolated `CODEX_HOME`, and per-slot worker directories use mode `0700`. The policy config, database, lock, and IDENTIFY ledger use mode `0600`; the derived Vault P0 snapshot uses mode `0400`. ChatGPT credentials live in the macOS Keychain item selected by official Codex keyring mode and the isolated `CODEX_HOME` namespace. Any filesystem credential artifact below `CODEX_HOME` is a startup and runtime failure.

## Failure behavior

| Failure | Claude behavior | Codex behavior |
| --- | --- | --- |
| Interactive listener exits | Five-minute healthcheck recreates tmux | Not applicable |
| Headless worker exits | Not applicable | LaunchAgent restarts service |
| Discord socket drops | Plugin or approval Gateway reconnects | Gateway RESUME when possible, then cursor reconciliation |
| Gateway dispatch queue fills | Provider-specific behavior | Socket is aborted, then reconnect and cursor reconciliation recover accepted events |
| Discord permission drifts | Provider-specific behavior | Runtime verification terminates the bridge and cancels every worker; a restarted service cannot become ready until exact public, bot, and owner-audience checks pass |
| Repeated process crashes | Healthcheck cadence limits restarts | Persistent IDENTIFY budget limits new sessions |
| Admission or database limit is reached | Provider-specific behavior | New event or delivery is rejected without starting extra work |
| Worker dies during task | Transcript state remains for next dispatch | Lease fencing marks job uncertain, no automatic rerun |
| Discord accepts reply but HTTP response is lost | Provider-specific behavior | Same nonce inside the server window; exhaustive history proof or quarantine after it |
| New App Server request appears | Not applicable | Unknown request returns an error and stops the App Server session |
| CLI or schema changes | Claude path unaffected | Preflight blocks until reviewed pins are updated |
| Sensitive result | Depends on Claude worker and gate rules | Best-effort redact-never-withhold masking preserves the useful remainder; public delivery is not a confidentiality boundary |
