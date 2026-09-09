# Disco Party FAQ

## What is Disco Party?

Disco Party is a local Discord conversation orchestrator for Claude Code and OpenAI Codex. It turns top-level channel messages into public Discord threads and keeps enough durable state to route later replies to the correct agent conversation.

It is the control plane around the agents. Discord is the remote interface, and Claude Code or Codex does the work. Disco Party authorizes the request, persists it, selects the correct provider and machine, dispatches it, keeps each thread ordered, resumes the right model conversation, and delivers or reconciles the result.

## Why call it an orchestrator instead of a Discord bot?

A basic bot receives a message and sends a reply. Disco Party manages the full lifecycle around the work: identity, routing, durable state, concurrency, provider sessions, recovery, and delivery evidence. The listener can remain available while background work continues.

Claude implements that worker layer with background Agent subagents. Codex uses a bounded pool of official App Server workers. Codex subagents are disabled because Disco Party cannot yet prove their complete child lifecycle and policy events.

## Why use Discord instead of SSH or a remote desktop?

SSH and remote desktop expose a machine. Discord gives the orchestration layer a mobile interface, notifications, durable threads, and searchable history. You can start a task from a phone, follow it from another laptop, and return to the exact conversation later without keeping a terminal open in front of you.

Discord is not a replacement for terminal access when you need direct control. It is the command and coordination surface for agent-owned tasks.

## Can I use one Discord server with several computers?

Yes, with a dedicated route for each provider and machine. For example, a server could contain `#claude-work-mac` and `#chatgpt-home-m5`, each with its own bot, runtime, and state.

Do not attach several machines to the same bot and channel. They could consume the same event and perform the work twice. Same server is supported as an orchestration pattern. Same bot and channel across several runtimes is not.

## Can Claude and Codex hand work to each other?

Yes, through explicit durable context. Their credentials and model sessions remain separate, but both can work in the same intentional local workspace. Claude can create a plan or artifact, then Codex can inspect and continue it, or the other way around. Discord threads can also remain the complete human-visible handoff record.

Disco Party does not silently merge a Claude session with a Codex session. The handoff is through files, artifacts, and instructions you can inspect.

## Can I run Claude and Codex at the same time?

Yes. They are separate providers with separate bots, channels, tokens, model logins, runtimes, and state. The recommended public channels are Claude `#claude` and Codex `#chatgpt`. Install Claude with `bash install.sh`, then add Codex with `bash install-codex.sh`.

## Can both providers use the same Discord bot or channel?

No. Reusing either would blur routing and credential boundaries. The Codex application and bot must also be dedicated to this integration and one server. Gateway READY fails unless the bot's guild set is exactly the configured guild. The Codex configuration rejects a channel ID that equals the Claude listen channel ID. Preflight compares the Codex token with standard Claude token sources it can discover. If Claude uses a custom credential source, the operator must verify that the tokens differ.

## Does the Codex provider use my ChatGPT subscription?

Yes. The installer keeps the canonical macOS `HOME` so official Codex keyring mode can use the default Keychain. It creates an isolated `CODEX_HOME` below the Codex state directory, then opens the official browser flow in that scope. Choose Sign in with ChatGPT. Disco Party refuses API-key authentication and does not require a manually supplied OpenAI API key. It verifies both the isolated CLI login status and App Server `account/read`. OpenAI documents the upstream choices in [Codex authentication](https://learn.chatgpt.com/docs/auth).

Normal `~/.codex` is intentionally not reused. The private config forces ChatGPT login and exact macOS Keychain storage, disables filesystem secret storage, and prevents normal credentials, MCP servers, plugins, and custom providers from loading. Disco Party rejects any `auth.json` or related credential artifact. This is not OS isolation. Full computer access can still read other same-user files and query Keychain.

Disco Party requires App Server `account/read` to report a ChatGPT account with a nonempty email and supported plan. It hashes those nonsecret facts without logging the email and includes the digest in the durable policy fingerprint. This binds routing state to the principal reported by the official authenticated client. The official Codex client, macOS Keychain, and OpenAI service perform credential storage and upstream authentication.

The installer derives a private immutable venv path from the CPython version, pinned `websockets` version, and requirements-lock hash. It builds new contents in a private staging directory, verifies installed-distribution hashes and a private manifest, publishes the result atomically, and reuses an existing exact path only after verification. The LaunchAgent points at that Python. Full computer access can still modify same-user files, including this venv.

## Can Disco Party replace the older `com.thesystem` Codex bridge?

Yes, but only through the explicit takeover path in [the setup guide](SETUP.md#take-over-the-reviewed-legacy-codex-bridge). An ordinary install refuses to coexist with the legacy label or plist. `--take-over-legacy` validates the exact old service, public-channel policy, private ledger, identity, and root cursor before staging. `--import-legacy-token` separately authorizes a direct Keychain-to-Keychain copy; it never imports the old shared Codex login, so Disco Party still requires a fresh official ChatGPT sign-in in its isolated `CODEX_HOME` scope.

The old service remains live through replacement preflight. At the acknowledged maintenance boundary, the installer stops it, verifies its captured App Server descendants exited, disables the old label, rejects unfinished or ambiguous old work, takes a private backup, and writes only the final root cursor into an empty policy-scoped Disco Party ledger. Missing or mismatched cursor state forbids replacement bootstrap. Old jobs, sessions, delivery records, and Discord thread mappings do not migrate, so start a new root message after cutover. The old plist, ledger, disabled label, and Keychain item remain available for a controlled rollback.

## Does Codex call an unofficial proxy?

No. It starts the installed OpenAI Codex CLI's official App Server as a local child process and communicates over stdio JSONL. OpenAI documents this interface in [Codex App Server](https://learn.chatgpt.com/docs/app-server).

## What happens if I switch the isolated ChatGPT account?

The `account/read` email and plan binding produces a different policy fingerprint. Disco Party cancels stale queued jobs, marks stale running jobs uncertain, and does not reuse the prior login's managed-thread routing, Codex session scopes, or prepared deliveries. Send a new root message after the new principal passes preflight.

Disco Party performs this comparison against the nonsecret account facts returned by the official authenticated App Server and never logs the email. It does not read or parse the Keychain credential and does not replace the official Codex client's authentication with OpenAI.

## Which Codex model and reasoning level does it use?

Disco Party pins [`gpt-5.6-sol`](https://developers.openai.com/api/docs/models/gpt-5.6-sol), provider `openai`, and Ultra reasoning, with provider-model fallback disabled. App Server model listing, effective config, thread creation, resume, and turn creation are checked against that policy.

## Does it follow workspace `AGENTS.md` automatically?

No. Project roots stay untrusted, project-document byte allowance is zero, fallback project filenames are empty, and App Server must report no instruction sources. The optional `[codex].instructions_file` outside the workspace is the only additional instruction source. Disco Party requires a single-link, current-user-owned file and stable trusted ancestry, rejects all symlink components plus lexical, canonical, and filesystem-identity workspace overlap, and rechecks the path after each read. Files Codex explicitly reads to perform a task are still untrusted content.

## Does Codex use the same Vault skills as Claude?

Yes. The Vault remains the only maintained source. Disco Party exposes exactly the canonical `skill-finder`, `eli5`, `marketing/websites/vinaytalks`, and `triage` closures through four validated links in the isolated `CODEX_HOME`. It does not copy them into a Codex-specific fork. Skill-finder is injected on every turn, ELI5 requests also inject ELI5 and VinayTalks, asset or artifact creation also injects VinayTalks, and triage requests also inject triage.

The complete four-skill closure is hashed into the policy fingerprint and revalidated before and immediately after each turn starts. Full mode also selects and hashes the canonical Vault `CLAUDE.md` as its trusted bootstrap when no separate instruction file is configured. Skill-finder may read other live Vault skills through full shell access, but those additional files are not in the four-skill manifest and are not attested by this bridge. The working directory may not overlap the shared-skill or bootstrap source. These controls detect drift, but a full-access process running as the same macOS user is not isolated from the Vault during an active turn.

Disco Party also derives a private mode `0400` snapshot of the six canonical Vault P0 sections directly from `CLAUDE.md`. It binds the source and snapshot hashes into policy state and revalidates both around every Codex turn. It keeps no second prose copy. Claude receives the same derived snapshot at launcher startup and in its listener and subagent prompts, although Claude's broad Vault access means that startup check is detection and instruction inheritance rather than OS containment.

## Is App Server stable?

OpenAI currently classifies `codex app-server` as experimental in the [Codex CLI reference](https://developers.openai.com/codex/cli/reference). Disco Party opts in to the official experimental capability, then pins Codex CLI `0.153.4`, the launcher and native arm64 binary hashes, generated schema bundle, server request method set, `gpt-5.6-sol`, OpenAI provider, and Ultra reasoning. An unreviewed update makes preflight fail closed.

## Should I always install the newest Codex CLI?

Do not auto-upgrade the service blindly. Read the official [ChatGPT and Codex changelog](https://learn.chatgpt.com/docs/changelog), review the candidate's generated experimental schema and server requests, update the pins, run tests and preflight, then repeat the live Discord acceptance checks.

If you already updated and preflight now fails, the pin is working as designed.

## Is the adapter a cron job?

No. Both message paths are event driven. The Codex bot maintains a Discord Gateway WebSocket and receives `MESSAGE_CREATE` events. It uses REST only to reconcile a gap after READY or reconnect, starting after a durable channel cursor.

The Gateway read loop and heartbeat task do not wait on REST, SQLite, or model work. Events enter a bounded queue of 1,000 items and one serial ingress dispatcher handles them. If the queue fills, the bridge aborts the socket and recovers from durable cursors after reconnect. A separate pool runs three App Server workers by default, configurable from one through four. Different Discord threads may run concurrently; messages within one thread remain ordered.

The Claude listener receives messages through the Claude Discord plugin. A five-minute healthcheck only ensures its interactive tmux session still exists. It does not poll Discord for normal messages.

## Do I need to keep an open tmux session for Codex?

No. The Codex worker runs headlessly under the `com.discoparty.codex-discord-bridge` LaunchAgent.

The optional `discoparty-codex` tmux session is observation only. Closing it does not stop the service. Claude is different: `discoparty-chat` contains the actual interactive Claude listener.

## Can I see Codex requests locally?

Yes. Attach to the read-only monitor:

```sh
tmux attach -t discoparty-codex
```

It shows recent accepted owner messages, job states, and delivery states from SQLite. It is not a live Codex terminal and does not expose hidden reasoning. For one snapshot, run:

```sh
PYTHONPATH=. python3 -m codex_discord_bridge.monitor --once
```

## Can the Codex channel be public?

Yes. Public server members may read the channel and its threads. Only the exact configured owner ID can trigger Codex work, and non-owner messages should receive no reaction, thread, or job.

Preflight requires a normal `GUILD_TEXT` channel, no obfuscated flag, effective `@everyone` View Channel, an active non-owner bot membership, no forbidden guild-management or extra configured-channel capability, and the bot's six required effective channel permissions after Discord's official overwrite calculation. The `@everyone` channel overwrite must explicitly deny Manage Threads, Create Public Threads, and Create Private Threads. Create Public Threads must be restored only by the configured bot's exact member overwrite; any role or other-member restoration fails. Extra capabilities such as invites, attachments, private threads, broad mentions, polls, external apps, and pinning are rejected. It repeats the check at startup, READY, RESUMED, every five minutes, and after channel create, update, or delete; thread create, update, delete, or list sync; guild create, update, or delete; guild-role create, update, or delete; and guild-member update. Each event must belong to the configured guild. A member-specific deny may still hide an otherwise public channel from that member. Guild owners and Administrator members bypass channel overwrites and remain trusted server operators.

Preflight and runtime verification enumerate the guild's visible channels and active threads. The bot may View only configured `#chatgpt`, its exact declared `GUILD_CATEGORY` parent when present, and active public threads whose parent is that exact channel. The parent-category exception exposes metadata, not messages. Visibility into any unrelated category or channel, private thread, announcement thread, or unrelated public thread fails closed. Configure Discord role, category, and channel overwrites accordingly. See Discord's [Gateway intents](https://docs.discord.com/developers/events/gateway#gateway-intents) and [Guild resource](https://docs.discord.com/developers/resources/guild).

Public visibility still means public visibility. Do not post secrets, confidential work, private records, or regulated data there. The redact-never-withhold output filter is best effort, may miss sensitive material, and is not a confidentiality boundary.

## What does `owner_private` mean?

It means the configured parent channel is mechanically private to exactly two readers: the configured Discord guild owner and the dedicated Codex bridge bot. The channel must explicitly deny `@everyone` View Channel, grant View Channel through exact member allows for those two identities, contain no other role or member View allow, and produce no other effective reader after Discord's overwrite calculation. A currently small or single-human public server does not qualify because a newly invited member could read retained history immediately.

Owner-private verification requires the Server Members privileged intent. Disco Party checks the private topology at preflight, startup, READY, RESUMED, every five minutes, and on relevant channel, role, guild, thread, or member events. A proof failure terminates the bridge, clears readiness, and cancels every worker. This destination setting is optional and does not select the Codex sandbox.

## Can multiple people use the Codex channel?

Not in the current owner-only design. One immutable owner user ID is authorized. Multi-owner support would need explicit identities, per-action policy, revocation, and approval semantics.

Claude is also owner-only. Its official Discord plugin receives an exact per-channel `allowFrom` list containing only the configured owner, and its global direct-message allowlist is empty. Public visibility controls who can read the channels, not who can start either agent.

## Why does a Codex message get ignored?

The common reasons are:

- wrong Discord user
- wrong guild or channel
- reply in a thread the bridge did not create
- wrong bot or application identity
- bot or webhook author
- unsupported message type
- empty content
- content above `max_input_chars`
- per-minute, per-hour, pending-job, or database limit reached
- missing Message Content Intent
- public baseline or bot permission verification failed
- LaunchAgent or preflight failure

Ignored unauthorized messages are intentionally quiet.

## What happens after I send a valid Codex message?

The bridge first reserves a root event with `ready=0`, adds an eyes reaction, creates or recovers a public response thread, durably saves the mappings, then changes the job to `ready=1`. Workers claim only ready jobs. The filtered result is frozen in a delivery manifest, each POST attempt is recorded before it crosses the network, deterministic nonces are used, Discord messages are read back, and the manifest is marked complete only after every chunk is confirmed. An old unresolved POST needs an exact history match or it is quarantined instead of being posted again.

## How does conversation memory work?

Claude stores an append-only markdown transcript and maps its Discord thread to a local session ID.

Codex stores the mapping from each managed Discord thread to a persisted Codex thread ID in SQLite. A later accepted reply resumes that Codex thread before starting the next turn.

Those mappings are namespaced by a policy fingerprint covering the Discord IDs, workspace, sandbox, model and Ultra policy, built-in Disco Party base instructions, reviewed binary and schema hashes, ChatGPT `account/read` binding, sealed canonical Vault P0 source and snapshot, exact shared-skill closure, and optional trusted instructions. Changing that authority creates a new scope instead of resuming old Codex context.

## What happens if the Codex worker crashes halfway through?

Running jobs have renewable leases and fencing generations. A new process marks abandoned or expired work `uncertain` rather than rerunning it. If the Discord output was fully delivered, the bridge reconciles it and marks the job complete. Otherwise it posts an uncertainty notice when possible and waits for human review.

This avoids common duplicate effects but cannot undo something that already happened before the crash.

## Why store Discord channel cursors?

A Gateway disconnect can hide messages between the last socket event and the next READY. The bridge stores the last processed message snowflake for the root channel and every managed thread, then fetches messages after that cursor during reconciliation.

On first activation, it records the newest existing root-channel message as a baseline without executing history. Send the acceptance test only after the service has started.

## What is the IDENTIFY budget?

Discord RESUME is preferred when possible. A new Gateway IDENTIFY consumes a separate local budget, defaulting to 20 per rolling hour and 400 per rolling day. Disco Party stores reservations in `identify-ledger.json`, so a launchd crash loop cannot reset the counter by restarting the process. If the ledger is corrupt, the bridge persists a 24-hour block rather than assuming zero prior use.

## What limits stop a Discord flood or runaway backlog?

Codex defaults to 5 accepted messages per minute, 30 per hour, 3 concurrent workers, 100 pending jobs, 12,000 input characters, 30 days of retention for completed, failed, cancelled, and eligible old uncertain jobs, and 268,435,456 bytes of logical SQLite capacity. The first two inherit `[runtime]` when omitted. Worker concurrency accepts 1 through 4. Pending means queued, running, or uncertain. A root mapping is retained while a recent or active child still needs its thread. New admission or delivery state fails closed at its applicable limit.

The exact `[codex]` keys are `max_messages_per_minute`, `max_messages_per_hour`, `max_concurrent_workers`, `max_pending_jobs`, `max_input_chars`, `retention_days`, and `max_database_bytes`.

`retention_days` and `max_database_bytes` cover Disco Party's logical SQLite ledger, not all Codex state or disk usage. The capacity calculation excludes the WAL, logs, and other state files. Persisted App Server thread, rollout, and transcript state under the isolated `CODEX_HOME` is not pruned by those settings and can outlive the SQLite mapping or grow independently. Review and delete that private state separately when local retention matters.

## What does `workspace-write` allow?

The compatibility setting selects Disco Party's custom `discoparty-workspace-only` profile. It extends `:workspace`, denies filesystem root and both temporary-directory aliases, preserves the minimal read set, uses only the configured runtime workspace root, adds no writable roots, and disables agent-tool network. Use the smallest useful working directory and keep it separate from Disco Party's repository, config, state, isolated `CODEX_HOME`, logs, LaunchAgent plist, canonical Vault P0 source, shared skills, and trusted instruction file.

It can still run permitted commands and modify or delete files inside that workspace. Keep those files under version control with recoverable backups.

Workspace-write mode also disables project config layers, MCP servers, apps, web search, Browser, Computer Use, plugins, every unreviewed hook, image generation, multi-agent, local automation, skill search, and skill dependency installation. It retains only Disco Party's exact canonical Vault security, em dash, and deny-only outbound hooks plus the bound ELI5, VinayTalks, triage, and skill-finder closures. A disabled project layer may appear only for a canonical `.codex` ancestor inside the untrusted Git root. Exact layer-order checks reject active project, managed, MDM, enterprise, legacy, packaged, duplicate, reordered, or unknown configuration sources. Live checks also reject shell environment injection, an unexpected skill, hook, or MCP server, and any weakened effective permission profile or sandbox. App Server still needs its own network connection to OpenAI for model execution.

OpenAI's upstream model is described in [Agent approvals and security](https://learn.chatgpt.com/docs/permissions).

## Is full computer access supported?

Yes, after explicit risk acceptance:

```toml
sandbox_mode = "danger-full-access"
full_computer_access_accepted = true
```

The installer additionally requires `DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED`. This sandbox authority is independent of `channel_trust`: both `public` and `owner_private` may select danger-full-access. The mode removes the Codex command sandbox and gives the headless agent uncontained same-user shell, filesystem, process, and command-network authority.

The exact canonical Hooks remain valuable guardrails, but hook launch failures, timeouts, kills, malformed output, serialization failures, and other framework failures can allow a tool to continue. The acknowledgment records acceptance of that risk; it does not create containment. A separate operating-system identity, dedicated machine, or capability broker remains the stronger design.

## Do Codex hooks match the shared Vault controls?

Yes, for the reviewed supported-path guardrails. Disco Party derives the canonical Vault security validator, em dash write validator, outbound-send guard, and helper closure into a private read-only content-addressed snapshot outside every writable root. The isolated `hooks.json` points only to that snapshot, uses Python isolated mode, and never imports from the workspace. Disco Party uses the outbound guard in deny-only mode, verifies exact `hooks/list` metadata, binds source and snapshot hashes separately, and rejects failed or unexpected synchronous hook events.

This is not containment. OpenAI says hosted tools are not covered by local tool hooks and specialized paths may opt out. Tested framework and hook-process failures can also fail open. No hook can make a same-user worker safe to hold outbound credentials or treat a Discord review marker as authorization. Disco Party therefore installs no automatic third-party sender; danger-full-access remains an explicit risk acceptance.

The bridge does not provide the ChatGPT desktop app's first-class visual Browser or Computer Use host. OpenAI says [Browser is unavailable in Codex CLI](https://learn.chatgpt.com/docs/browser), while [Computer Use](https://learn.chatgpt.com/docs/computer-use) is a separate desktop plugin.

## Does `approvalPolicy: never` mean full access?

No. Approval policy, sandbox authority, and destination trust are separate. Disco Party uses `never` so the headless App Server never waits on an unsafe or unreachable interactive prompt. Either `public` or `owner_private` can use the reviewed workspace profile or select `danger-full-access` after the exact acknowledgment.

## How do Codex approvals work?

App Server approval requests are denied. For a gated action, Codex must return the exact draft or action manifest and stop. A later message from the exact owner must explicitly approve that exact action, destination, and content. `go`, `continue`, `proceed`, and third-party text are not approval.

This is an instruction-enforced contract, not a hash-bound approval token or an enforcement boundary. It cannot stop a prompt-injected or mistaken action that is already permitted. Add a deterministic gate before using Codex for any external send, irreversible action, or high-impact operation.

## Does Codex inherit Claude's approval buttons and outbound adapters?

No. Claude's button, marker, and adapter path is provider-specific. A Codex integration must be enabled and gated explicitly. Sharing the adapter silently would defeat the provider boundary.

## Why was a Codex response redacted?

Disco Party no longer discards the whole useful response for one match. It attempts to mask credentials and Luhn-valid payment-card numbers in every mode, and public mode also attempts to mask personal values and structured private details. Owner-private mode can preserve requested personal information after the exact private-channel reader proof. This is best-effort redact-never-withhold DLP, not a confidentiality boundary; a pattern miss can still expose sensitive text. A long response is truncated with a visible note.

## Where is state stored?

Claude transcripts usually live at `~/.discoparty/conversations/`.

New Codex installations default state to `~/Library/Application Support/Discoparty/codex-discord/`, outside the normal `~/.discoparty` repository clone. Any override or reused path must be an explicit descendant of `~/Library/Application Support/Discoparty`; arbitrary home-directory paths are rejected so config and rollouts cannot land in another Git or synced working tree. The installer and daemon each reject unsafe ownership, modes, symlinks, and non-directory ancestry. Reinstall fails closed on an older path outside that root. Use an explicit approved override and complete the isolated login there to migrate; Disco Party does not silently move rollout history. State includes `jobs.sqlite3`, `identify-ledger.json`, the derived `policy/vault-p0.md`, `ready.json` while live, the runtime lock, isolated `CODEX_HOME`, and private per-slot worker directories. The official ChatGPT credential stays in macOS Keychain under the scope derived by Codex from that `CODEX_HOME`; a filesystem credential artifact is rejected. The optional monitor reads SQLite in read-only mode.

`bash uninstall.sh --codex` retains noncredential state and repository service logs for audit, but performs a scoped official ChatGPT logout by default. `--keep-chatgpt-login` is the explicit opt-in for retaining that login. Delete the private state directory and retained logs manually if you also want to remove that local history.

## Where are the bot tokens stored?

On macOS:

- Claude: Keychain service `discoparty-secret`, account `discord-bot-token`
- Codex: Keychain service `discoparty-secret`, account `discord-bot-token-codex`

Keychain is the source of truth. The Claude launcher validates policy and private state, reads the token from Keychain with environment fallback disabled as its final credential step, and replaces itself with the pinned Claude process. The token is never put in argv or a file. Any stale `~/Library/Application Support/Discoparty/claude-discord/.env` blocks launch; controlled install and uninstall remove it.

Do not put a real token in `config.toml`, an environment file, a plist, a shell command, the repository, or a GitHub issue. Same-user processes, including a full-access Codex turn, may still inspect process memory or environment or query Keychain.

## Does Disco Party send email or Slack by default?

No. Disco Party installs no Slack, email, or other third-party sender. Claude's native buttons produce owner-bound review evidence, but the resulting Discord reference is not a one-time send capability. The installer removes the obsolete marker-watcher service. Codex gets no automatic access to the Claude review flow.

## Does this require a Mac mini?

No. It requires the reviewed Apple M5 Max chip, not a particular Mac form factor. The installer and preflight require the exact reported chip value `Apple M5 Max`; a base M5, M5 Pro, M5 mini, or non-M5 host is rejected. Preflight separately verifies the exact Codex launcher, native binary, and schema pins.

## Is Linux supported?

The original Python and systemd pieces are portable, but the installers are macOS-first. The Codex provider currently requires the reviewed Apple M5 Max host, a macOS LaunchAgent, and Keychain, so it has no supported Linux installation path yet.

## How do I report a security issue?

Follow the private disclosure instructions in [SECURITY.md](SECURITY.md). Do not open a public GitHub issue for a vulnerability.
