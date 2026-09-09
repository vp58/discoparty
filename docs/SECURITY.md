# Disco Party security

Disco Party is a local, single-owner Discord control plane for two powerful coding agents. This document describes the security boundaries, the controls each provider applies, and the risks that remain.

## Security posture in one page

- Use separate Discord applications, bots, tokens, and channels for Claude and Codex.
- Keep the writable Codex workspace completely separate from the Disco Party repository, config, state, logs, LaunchAgent plist, and trusted instruction control plane.
- Keep Codex on the custom `discoparty-workspace-only` profile by default. `danger-full-access` requires the exact operator acknowledgment independently of destination trust, and remains uncontained because Hooks cannot supply a fail-closed same-user boundary.
- Treat public Discord as public. Other server members may read the channel and its threads even though only the configured owner can trigger Codex.
- Never put secrets, regulated records, confidential source material, or private personal details in a public prompt.
- Keep deterministic approval gates for every external send and consequential action. The Codex later-message approval contract is behavioral and cannot enforce authorization.
- Keep the isolated `CODEX_HOME`, scoped ChatGPT Keychain login, derived Vault P0 snapshot, and reviewed policy config private. Normal `~/.codex` is intentionally not reused.
- Expect the Codex service to stop after an unreviewed CLI or App Server schema change. That is intentional.
- Protect the Mac, Discord account, ChatGPT account, Claude account, and bot tokens with MFA and normal endpoint security.

## Trust boundaries

### Local machine

Disco Party trusts the logged-in macOS account and the code installed under that account. A process running as the same user may be able to read Disco Party state, local model credentials, transcripts, and bot tokens or invoke the installed agents.

`danger-full-access` removes Codex's local command sandbox and gives it the same-user shell, filesystem, process, and command-network authority available to the service account. This includes possible Keychain queries and modification of user-owned control files. Owner-only Discord ingress does not create an operating-system boundary. Disco Party therefore accepts this mode only after the exact acknowledgment. Sandbox authority is independent of destination trust, so either a public or owner-private channel may use it.

### Discord

Discord is both an input transport and an output surface. Codex uses public visibility by default and may optionally use a verified owner-private parent channel.

For Claude, the official Discord plugin is configured with an exact per-channel `allowFrom` list containing only `[discord].owner_user_id`; the global direct-message allowlist is empty. Other members may read the public channel but cannot create Claude conversations. Only that same configured owner can record a button review decision.

For Codex, the bridge accepts work only from one immutable Discord owner user ID in one immutable guild and channel, or in threads the bridge previously recorded as managed. Other users may still read a public channel and its public threads.

### Model providers

Claude Code and Codex have separate sign-in stores and separate behavior. Enabling one does not authenticate the other.

Codex must report a ChatGPT login. Disco Party forbids API-key mode, requires the exact macOS Keychain credential backend, disables filesystem secret storage, rebuilds the App Server environment from an allowlist, and does not copy the Discord token or `OPENAI_API_KEY` into the child environment. It requires App Server `account/read` to return a ChatGPT account with a nonempty email and supported plan, then hashes those nonsecret facts for durable state binding without logging the email. OpenAI explains the account and policy differences between ChatGPT and API-key sign-in in its [authentication documentation](https://learn.chatgpt.com/docs/auth).

New installations default the state directory to `~/Library/Application Support/Discoparty/codex-discord`, outside the documented repository clone. Every override or reused path must remain below the canonical `~/Library/Application Support/Discoparty` root. Arbitrary paths elsewhere under the user's home are rejected so config and App Server rollouts cannot be redirected into another Git checkout or synced working tree. Both the installer and runtime loader canonicalize the path and reject wrong ownership, group or world write access, symlinks, and non-directory ancestry. The installer keeps canonical macOS `HOME` for Keychain access, creates a private `CODEX_HOME` below the selected state path, performs a separate official ChatGPT browser login in that scope, and writes the only user config App Server may load. Normal `~/.codex` credentials, MCP servers, plugins, and custom providers are not loaded. This is configuration separation within one macOS account, not OS isolation. Full access shares that account's authority and can read the separate state directory and other same-user files, query Keychain, and reach any authority granted to the login session.

### Third-party content

Every Discord message, attachment URL, webpage, repository file, terminal output, email, Slack message, and tool result can contain prompt injection. Trusted owner ingress proves who requested the task. It does not make the content encountered during the task trustworthy.

## Provider separation

| Control | Claude | Codex |
| --- | --- | --- |
| Discord bot | Dedicated | Dedicated and installed in exactly one configured server |
| Discord channel | Dedicated Claude `#claude` listen channel | Dedicated Codex `#chatgpt` channel, different ID required |
| Bot credential | Keychain `discoparty-secret/discord-bot-token` | Keychain `discoparty-secret/discord-bot-token-codex` |
| Model credential | Claude Code login | Codex ChatGPT login |
| Runtime | Interactive tmux listener | Headless LaunchAgent |
| Conversation state | Markdown files and registry | SQLite job state plus Codex thread IDs |
| Outbound approval | Button result is review evidence only; no third-party send adapter is installed | Exact later owner message instruction contract |

A shared bot would weaken identity checks and make token rotation couple two failure domains. A shared channel would create ambiguous routing and let one runtime observe the other's commands. Disco Party rejects the shared-channel configuration for Codex.

The Codex application and bot must be dedicated to this integration and one server. Gateway READY must list exactly the configured guild, with no duplicate, malformed, or additional entry. This runtime check proves the bot's current guild membership, while the operator remains responsible for not reusing the application for another installation mode.

Separate Keychain account names do not prove the underlying token values differ. Preflight compares the dedicated Codex token with standard Claude token sources it can discover and blocks a match. If Claude uses a custom source that cannot be discovered, preflight warns and the operator must verify the tokens are different.

## Claude legacy takeover boundary

`install.sh --take-over-legacy` is the only supported path from the reviewed
`com.thesystem` Claude orchestrator to Disco Party. It is fail closed and does
not run in scratch mode. It requires both an exact maintenance phrase and a
second acknowledgment bound to the exact counts of `claimed` rows without a
new operation ledger and `dispatched` rows. A SHA-256 digest covers every full
nonterminal queue row and dispatch operation between planning and quarantine.
Any drift stops takeover and restores the legacy runtime.

The healthcheck is stopped first so it cannot recreate `cx-chat` during the
maintenance window. All five reviewed jobs, the exact one-pane tmux session,
its process group, and known descendants must be gone before backup or queue
mutation. The replacement does not reuse the old Discord Gateway session or
sequence.

The pre-mutation backup contains a SQLite API snapshot, raw database and WAL
state, conversation registry, active and archived transcripts, other state,
legacy approval files, and exact plists. It is current-user private and each
file is covered by a SHA-256 manifest. Legacy approval files are recorded as
quarantined and never imported into the new approval schema.

`claimed` rows without the operation ledger and all legacy `dispatched` rows
have an unknown side-effect boundary. Explicit quarantine changes their queue
state to `errored` so no drainer can select them, while preserving each complete
original row for safe pre-acceptance rollback. These rows are unresolved manual
review items. They are never replayed, completed, or represented as migrated.
Any `spawned` row is a hard stop because model, local-tool, or Discord response
effects may already have occurred.

Discord gap recovery uses one global lower snowflake and a captured upper
boundary across the root channel plus every thread in the verified registry.
It accepts only the configured owner, stores the complete source payload,
inserts idempotently by Discord `message_id`, and confirms the eyes reaction.
The same bounded scan runs again after exact replacement readiness, so Gateway
overlap cannot create a duplicate queue row.

Before takeover commits, the controller writes a random 256-bit challenge and
15-minute expiry into the private receipt, then sends a bare local command to
the exact tmux listener. Discord input is always channel-envelope wrapped and
the pinned listener contract rejects the command inside any such envelope. The
completion token is exact, fresh, challenge-bound, and single-use. The
controller still treats that token only as protocol evidence: it independently
queries SQLite and refuses commit while any safe row remains in `received`,
`claimed`, or `dispatched`.

Automatic rollback is evidence based. Before replacement start, Disco Party
freezes the maximum SQLite row ID and every nonterminal state and update time.
It may stop the replacement and reload legacy services only if no new row and
no transition is observed. Once work is admitted, or once takeover commits,
the receipt permanently forbids automatic legacy restart. This avoids running
two consumers after either may have crossed a side-effect boundary.

## Codex ingress authorization

Every accepted Codex event must satisfy all of these checks:

- numeric event ID
- `MESSAGE_CREATE` event type
- configured receiving bot ID
- configured Discord application ID
- supported ingress policy version
- supported Discord message type
- configured guild ID
- configured root channel ID or a recorded managed-thread ID
- configured owner author ID
- human author, not a bot
- no webhook ID
- non-empty content

The Gateway READY payload must also match the configured bot and application before the bridge starts reconciliation. Its guild set must be exactly the configured guild. The bot token is verified through Discord's own bot identity endpoint before service startup.

Authorization uses IDs, never server names, channel names, nicknames, roles, or visible account text.

### Discord permission verification

Disco Party does not trust an invite-time permission integer or a successful message read. It fetches and strictly parses the current bot, OAuth application, channel, guild roles, and bot guild-member records through these endpoints:

- `GET /users/@me`
- `GET /oauth2/applications/@me`
- `GET /channels/{channel_id}`
- `GET /guilds/{guild_id}`
- `GET /guilds/{guild_id}/members/{bot_id}`
- `GET /guilds/{guild_id}/channels`
- `GET /guilds/{guild_id}/threads/active`

The channel must match the configured guild and channel IDs, have type `GUILD_TEXT`, and not have the `CHANNEL_OBFUSCATED` flag. Bot membership must be active, not pending, and not under an active communication timeout. Unknown, duplicated, non-canonical, or malformed snowflakes, roles, permission strings, and overwrite types fail closed.

Disco Party implements Discord's official owner and Administrator semantics, guild role union, `@everyone` channel overwrite, combined role overwrites, and member overwrite precedence. It fails closed if the bot owns the guild. Its guild roles must not contain:

- Kick Members, Ban Members, or Administrator
- Manage Channels, Manage Guild, View Audit Log, Manage Messages, or View Guild Insights
- Mute Members, Deafen Members, Move Members, or Manage Nicknames
- Manage Roles, Manage Webhooks, Manage Guild Expressions, Manage Events, Manage Threads, or Moderate Members
- View Creator Monetization Analytics, Create Guild Expressions, or Create Events

The configured channel's effective permissions must exclude that same set plus Create Instant Invite, Send TTS Messages, Attach Files, Mention Everyone, Create Private Threads, Send Voice Messages, Send Polls, Use External Apps, and Pin Messages. Channel overwrites cannot reintroduce one of these forbidden capabilities.

The bot's effective channel permissions must include required mask `0x0000004800010c40`, which contains:

- View Channel
- Read Message History
- Add Reactions
- Send Messages
- Create Public Threads
- Send Messages in Threads

The channel's `@everyone` overwrite must explicitly deny Manage Threads, Create Public Threads, and Create Private Threads. Only the configured bot's exact member overwrite may restore Create Public Threads. No role overwrite, including the bot role, and no other member overwrite may allow any of those three thread capabilities. The bot member overwrite may not restore Manage Threads or Create Private Threads. This prevents ordinary members from flooding the bridge's managed-thread inventory through Discord's later role/member overwrite precedence.

In `public`, View Channel remains effective for the `@everyone` baseline. In `owner_private`, the parent channel must explicitly deny `@everyone` View Channel, grant View Channel through exact member allows only to the configured guild owner and dedicated bridge, contain no other role or member View allow, and have no other effective reader. A currently small public server does not qualify because a newly invited member could immediately read retained history. Discord documents the calculation in [Permissions](https://docs.discord.com/developers/topics/permissions), the channel type in [Channels Resource](https://docs.discord.com/developers/resources/channel), and parent-channel visibility in [Threads](https://docs.discord.com/developers/topics/threads).

The calculation runs at preflight, daemon startup, Gateway READY, Gateway RESUMED, every 300 seconds, and after `CHANNEL_CREATE`, `CHANNEL_UPDATE`, `CHANNEL_DELETE`, `THREAD_CREATE`, `THREAD_UPDATE`, `THREAD_DELETE`, `THREAD_LIST_SYNC`, `GUILD_CREATE`, `GUILD_UPDATE`, `GUILD_DELETE`, `GUILD_ROLE_CREATE`, `GUILD_ROLE_UPDATE`, `GUILD_ROLE_DELETE`, `GUILD_MEMBER_ADD`, `GUILD_MEMBER_REMOVE`, or `GUILD_MEMBER_UPDATE`. Owner-private mode repeats its exact private-channel reader proof at those same boundaries. Every security event must identify the configured guild, and a foreign-guild event fails closed. A permission or audience proof failure terminates the Gateway task, clears readiness, and causes the service supervisor to cancel every worker. A launchd restart must repeat the checks before useful processing resumes.

The verifier enumerates all guild channels visible to the bot and all active threads. It requires effective View Channel only on configured `#chatgpt`, its exact declared `GUILD_CATEGORY` parent when present, and active public child threads whose parent is that exact channel. The parent-category exception exposes category metadata and cannot carry messages. A visible unrelated channel, category, private thread, announcement thread, or public thread under another parent blocks startup or the current Gateway cycle. This constrains what Discord can deliver through the `GUILD_MESSAGES` and privileged `MESSAGE_CONTENT` intents. Discord documents the delivery scope in [Gateway intents](https://docs.discord.com/developers/events/gateway#gateway-intents) and the list resources in the [Guild resource](https://docs.discord.com/developers/resources/guild).

## Public-channel safety

The Codex channel may be public, but safe publication is a separate decision from safe execution. Before durable intake, public mode rejects likely credentials, payment cards, and personal-data shapes. Owner-private mode permits personal data but still rejects likely credentials and payment cards. Rejected content receives a stop reaction and is not written to Disco Party's SQLite ledger or passed to Codex. Claude's public queue applies the conservative pre-enqueue predicate. The original Discord message already exists on Discord, and a provider may already have received it, so this is local minimization rather than recall or complete ingress DLP.

Before sending a Codex result to Discord, Disco Party attempts to mask known credential and payment-card shapes, including:

- private keys and common API tokens
- bearer credentials, cookies, passwords, and authenticated URLs
- payment cards that pass the Luhn check

Public mode additionally attempts to mask Social Security numbers, email addresses, phone numbers, structured personal records, and confidentiality markers. Owner-private mode preserves requested personal detail only after the exact private-channel reader proof. Oversized responses are truncated with a visible note. The useful remainder is delivered, and outbound messages disable Discord mention parsing.

This is deliberately best-effort redact-never-withhold DLP. It can produce false positives, miss novel or partial sensitive shapes, and disclose matched context while preserving the useful response. It is not a complete data loss prevention system or confidentiality boundary. It also does not protect the prompt itself: anything typed into Discord has already been sent to Discord, and accepted Codex content is stored in the private local job ledger and sent to the model provider for processing.

## Codex sandbox and network access

OpenAI documents local sandboxing, approvals, and network controls in [Agent approvals and security](https://learn.chatgpt.com/docs/permissions). Disco Party sets policy explicitly at both App Server thread and turn creation.

### `workspace-write`

This compatibility setting selects Disco Party's custom `discoparty-workspace-only` permission profile. The profile extends `:workspace`, denies filesystem `:root`, preserves the minimal read set, denies both temporary-directory aliases, and disables agent-tool network. The configured working directory is the only runtime workspace root and no extra writable roots are accepted.

Codex can still execute permitted commands and read, create, modify, or delete content inside that workspace. A successful prompt injection can damage the workspace even when the separated control plane remains outside its filesystem authority. Keep the directory narrow, version controlled, and backed up.

Safe mode also disables project config layers, MCP servers, apps, web search, Browser, Computer Use, plugins, every unreviewed hook, image generation, multi-agent, local automation, skill search, skill dependency installation, and every skill except the exact canonical `skill-finder`, `eli5`, `marketing/websites/vinaytalks`, and `triage` closures. It enables only the isolated canonical Vault security, em dash, and deny-only outbound hooks. `thread/start` sends `dynamicTools: []`. Empty `environments` and `selectedCapabilityRoots` fields are intentionally omitted because they break Codex CLI `0.151.0` runtime-root resolution. Preflight and each thread start or resume require the reviewed session-flags layer, optional disabled project layers from canonical `.codex` ancestors inside the untrusted Git root, the exact isolated user layer, and an empty system layer in that order. They reject any active project, MDM, enterprise, legacy managed, packaged, duplicate, reordered, or unknown layer, any shell environment injection, any unexpected skill, hook, or MCP server, any App Server instruction source, or a weakened effective policy.

This does not make the whole App Server process offline. It still contacts OpenAI for model execution. It constrains agent tools and rejects the capability surfaces above. Use the smallest useful working directory and treat workspace files explicitly read during a task as untrusted input.

The working directory must not overlap the Disco Party repository, `config.toml`, state directory, service logs, LaunchAgent plist, trusted instruction file, canonical Vault policy source, or canonical shared-skill source in either direction. If it does, an otherwise workspace-scoped agent can rewrite its own executable bridge, authorization policy, persisted jobs, launch configuration, or future trusted policy and skill content. Configuration, installer, and preflight validation fail closed on this overlap. Installer and runtime state validation also require the canonical Application Support subtree and reject symlinked, foreign-owned, non-directory, or group or world-writable ancestry.

### Explicit `danger-full-access`

The full-access configuration requires the sandbox selection and acceptance:

```toml
sandbox_mode = "danger-full-access"
full_computer_access_accepted = true
```

The non-interactive installer also requires `DISCOPARTY_CODEX_FULL_COMPUTER_ACCESS_ACCEPTED=FULL_COMPUTER_ACCESS_ACCEPTED`. Channel trust remains a separate choice: both `public` and `owner_private` may use full access. Full access removes the Codex command sandbox boundary. A successful prompt injection or mistaken instruction could affect same-user files, processes, Keychain queries, network destinations, and any built-in capability exposed by the reviewed App Server config.

Isolated state, untrusted Git roots, capability shutdown, and canonical hooks do not contain the same-user filesystem and agent-tool network authority that `:danger-full-access` would grant.

### Canonical lifecycle hook guardrails

Disco Party reads the canonical Vault security validator, em dash write validator, outbound-send guard, and helper closure through stable descriptors, then publishes a content-addressed private runtime snapshot outside every writable root. Snapshot directories are mode `0500`, files are single-link mode `0400`, and the Python hook commands use absolute paths with `-I -S` so a writable working directory, Python environment, user site, or shell startup file cannot inject code. The private user-level `hooks.json` points only to this snapshot. The outbound handler runs in deny-only mode and never turns a Discord message, button, marker, or review reference into authorization.

Before App Server starts, Disco Party validates and hashes the canonical source closure, runtime snapshot, manifest, and hook config. It then uses official `hooks/list` metadata to require the exact user source, source path, commands, matchers, enabled state, definition hashes, timeouts, and no discovery warnings or errors. It watches synchronous hook events and rejects a turn with failed, stopped, or unexpected hook runs. The one-invocation hook-trust bypass is used only after these independent checks.

These checks are defense in depth. OpenAI documents that hosted tools do not use the local hook path and that specialized tool paths can opt out. Exact `0.151.0` tests also show that launch failures, timeouts, kills, malformed output, serialization failures, and non-2 errors allow the tool to continue. App Server can stop later work after a failed hook event, but cannot undo a completed effect. Danger-full-access explicitly accepts this residual risk; Disco Party still keeps automatic outbound send authority out of the bridge.

OpenAI documents [Browser](https://learn.chatgpt.com/docs/browser) as unavailable in Codex CLI and documents [Computer Use](https://learn.chatgpt.com/docs/computer-use) as a separate ChatGPT desktop plugin. App Server `dynamicTools` are client-supplied callbacks, and Disco Party deliberately sends an empty list. The bridge does not provide first-class screenshots, visual clicks, or the desktop plugin's app approval model.

Deployments that require containment stronger than accepted same-user risk need controls such as:

- an independent operating-system identity, dedicated machine boundary, or capability broker
- a fail-closed authorization path outside the Codex process
- no outbound credential readable by the model worker
- a new threat model with hook and raw-network bypass tests
- a supervised end-to-end acceptance test

## App Server protocol control

OpenAI identifies `codex app-server` as experimental in the [Codex CLI reference](https://developers.openai.com/codex/cli/reference). Its [App Server documentation](https://learn.chatgpt.com/docs/app-server) explains the explicit `experimentalApi` capability and version-specific generated schemas.

Disco Party opts in to the experimental surface and compensates with these checks before every App Server start:

1. Require ChatGPT authentication.
2. After initialization, require App Server `account/read` to identify a `chatgpt` account.
3. Require exact Codex CLI `0.153.4`.
4. Resolve the launcher and require its reviewed path and SHA-256 hash.
5. Require the reviewed Apple Silicon native binary path and SHA-256 hash on the exact Apple M5 Max install path.
6. Generate the full official experimental JSON schema bundle from the installed CLI.
7. Require the reviewed schema bundle hash.
8. Require the exact reviewed set of server-to-client request methods.
9. Require model `gpt-5.6-sol`, provider `openai`, Ultra reasoning, and no provider-model fallback.
10. Start with `--strict-config`.

Every recognized server request has an explicit response. Command and file approvals are declined, legacy approvals are aborted, permission requests grant no permissions, user-input prompts receive no answers, MCP elicitations are declined, and unsupported tool calls fail. An unknown request returns a protocol error and ends the App Server session.

This design favors service interruption over silently accepting a new authority surface.

The isolated mode `0600` config is the only user layer App Server may report. The complete allowed topology is the exact reviewed session-flags layer, zero or more disabled project layers from canonical `.codex` ancestors inside the untrusted Git root, that isolated user layer, and an empty `/etc/codex/config.toml` system layer. All other source types and active project layers block the session. Both modes require an inert shell environment policy, the exact expanded workspace profile definition, `instructionSources: []`, no administrator configuration requirements, no MCP server, and exactly four enabled skills at the canonical Vault paths. Safe mode additionally requires the complete disabled feature set and root-deny, network-off sandbox. Full mode requires the official danger profile but still disables `multi_agent` and `skill_search`; the bridge cannot attest descendant lifecycle or hook events. An unexpected layer, administrator requirement, model, provider, effort, profile, sandbox result, instruction source, skill, or MCP surface blocks the session.

The Vault is the single maintained source for the four bound skills. Disco Party creates exactly four absolute links in the isolated `CODEX_HOME/skills`, rejects any extra entry or redirected link, hashes every regular file in each closure, and binds names, paths, file hashes, and the closure manifest to durable policy. It rechecks the binding before every turn and immediately after `turn/start`. Skill-finder is injected on every turn; ELI5 requests additionally include ELI5 and VinayTalks, asset and artifact requests additionally include VinayTalks, and triage requests additionally include triage. Full mode automatically selects and hashes the canonical Vault `CLAUDE.md` as its external trusted instructions when no separate file is configured. Skill-finder may read the broader live Vault library through full shell access, but those additional files are outside the four-skill manifest and are not sealed or attested by Disco Party.

Disco Party also extracts exactly the six canonical P0 sections from the Vault `CLAUDE.md`, writes a private mode `0400` snapshot without maintaining another prose copy, and binds the source path, source hash, snapshot path, snapshot hash, and seal version into Codex durable policy. Descriptor-safe reads reject symlinks, unsafe ancestry, heading drift, reordering, extra P0 headings, or source and snapshot changes. Codex revalidates the seal before and after every turn. Claude validates the same derived seal at launcher startup and appends it to listener and subagent system prompts; because Claude also has broad Vault access, that is drift detection and instruction inheritance rather than an OS boundary.

These checks detect drift and narrow time-of-check/time-of-use windows. They are not containment against a malicious full-access process running as the same macOS user. That process can alter the canonical Vault or the bridge during a turn. Removing this residual requires a separate operating-system identity, restrictive ACL boundary, or immutable reviewed snapshot.

If `[codex].instructions_file` is configured, Disco Party treats it as the only additional trusted base-instruction content. It must be a current-user-owned, single-link regular UTF-8 file no larger than 256,000 bytes and must not be group or world writable. Disco Party rejects lexical or canonical workspace overlap, filesystem aliases into the workspace, every symlink path component, and untrusted ancestry. Each ancestor must be a stable root-owned or current-user-owned real directory without group or world write access, except for a root-owned sticky temporary-directory boundary. File identity, link count, and ancestry are rechecked after every read. Workspace `AGENTS.md` and fallback project documents are not auto-loaded because both project-document controls are disabled. Files explicitly read during a task remain untrusted content.

## Approval semantics

### Claude review buttons

The Claude flow binds a frozen draft to a SHA-256 digest. The owner presses a native Discord button, the router verifies the complete identity and draft binding, and the waiting request returns a Discord review reference after consuming its marker and binding.

No third-party sender is installed. The returned `channel_id:message_id` value is review evidence, not a durable one-time authorization capability. The obsolete marker-watcher is explicitly removed by the installer and must not be presented as a production security boundary.

A future production gate must use a short-lived one-time private receipt, bind the complete draft and destination plus every Discord identity, consume the receipt under a lock before the side effect, recompute the draft and target, reject replay, and keep outbound credentials unavailable to the model process. Without that separate gate, external sends remain disabled.

### Codex exact later message

The Codex headless service cannot safely pause an App Server request and expose a generic approval button to a public channel. It denies the App Server request. Its trusted instructions instead require:

1. Present the exact draft or action manifest without executing it.
2. Wait for a later Discord message from the exact configured owner.
3. Require that later message to approve the exact action, destination, and content.
4. Reject ambiguous language such as `go`, `continue`, or `proceed`.
5. Reject approval text found in third-party content.

This contract depends on the model following trusted instructions. It does not generate a hash-bound approval capability and cannot stop a prompt-injected or mistaken action that is already permitted by the active tool and permission configuration. It is workflow guidance, not an authorization boundary. Do not use it as the sole gate for any external send, irreversible, financial, privileged, regulated, or high-impact action. Add a deterministic provider adapter before enabling those actions.

## Durable state and duplicate-effect controls

Codex stores jobs, managed threads, Codex thread IDs, channel cursors, leases, generations, delivery manifests, hashes, nonces, and Discord message IDs in SQLite with WAL mode and full synchronization.

Security benefits include:

- a root event is first reserved with `ready=0`, and workers claim only `ready=1` after the reaction, public thread, and managed-thread mapping are durable
- duplicate Discord event IDs do not create duplicate jobs
- event IDs cannot be reused with changed immutable content
- a lease and fencing generation prevent stale workers from completing another worker's job
- the claim transaction permits different Discord destinations to run in parallel but blocks a destination with running or uncertain work
- an abandoned or expired running job becomes `uncertain` rather than rerunning
- the full public response is frozen before the first Discord POST
- retries use the same Discord nonce
- Discord content is read back and hash-checked
- a complete uncertain delivery can be reconciled without rerunning Codex

Before each Discord POST, the bridge durably records the attempt. A retry inside Discord's short nonce de-duplication window reuses the nonce. An older unresolved attempt scans the complete destination history and accepts only one exact configured-bot, nonce, and content-hash match. If the outcome cannot be proved, the delivery is marked ambiguous, excluded from automatic startup delivery, and shown by the local monitor. This can withhold a reply after a crash between the durable attempt and the HTTP request, but it does not risk creating a duplicate public reply after Discord's nonce window expires.

These controls reduce duplicate effects. They cannot undo an external action that completed before a crash. An uncertain job requires human review before any manual retry.

Durable authority is bound to a policy fingerprint. It includes the Discord IDs, resolved workspace, sandbox mode, model, provider, Ultra effort, rendered thread config, built-in Disco Party base-instruction hash, reviewed CLI and native binary hash, schema hash, the domain-separated ChatGPT `account/read` binding, sealed Vault P0 source and snapshot, exact shared-skill closure, and optional trusted-instruction path and content hash. The reported email is not logged or stored in the fingerprint payload. Jobs, managed Discord threads, Codex session scopes, and delivery manifests from another fingerprint cannot silently resume. A login-principal change cancels stale queued jobs, marks stale running jobs uncertain, and prevents old session routing from being reused.

Admission, concurrency, and storage are bounded. Defaults are 5 accepted messages per minute, 30 per hour, 3 concurrent App Server workers, 100 queued, running, or uncertain jobs, 12,000 input characters, 30 days of retention for completed, failed, cancelled, and eligible old uncertain jobs, and 268,435,456 bytes of logical database capacity. Worker concurrency accepts 1 through 4. Related SQLite routing and delivery state is pruned with an eligible job, while root mappings stay when a recent or active child still needs the thread. A capacity failure rejects the new job or delivery manifest. Raising a limit increases simultaneous local authority, backlog, storage, model-use, and public-output risk.

These storage limits are not a filesystem quota. The logical database calculation does not count the SQLite WAL, service logs, or other state files. App Server threads are persisted outside Disco Party's SQLite ledger, and their rollout or transcript state under the isolated `CODEX_HOME` is not removed by `retention_days` or counted by `max_database_bytes`. That state can retain model and tool context after its SQLite mapping is pruned and can grow independently. Treat it as sensitive local data, especially in full mode, and establish a separate review and deletion procedure if shorter retention is required.

## Gateway restart controls

Discord Gateway RESUME is preferred while the session and sequence remain valid. A full process restart may require IDENTIFY, so the Codex bridge stores a separate `identify-ledger.json` with defaults of 20 IDENTIFY operations per rolling hour and 400 per rolling day. The file is mode `0600` in a mode `0700` state directory.

If the ledger is malformed or unreadable, the bridge persists a full 24-hour block before allowing another IDENTIFY. This prevents a corrupted or deleted in-memory counter from turning a launchd crash loop into an unbounded identify loop.

Durable per-channel message cursors let the bridge reconcile accepted messages after reconnect. They are separate from the Gateway sequence and do not authorize events by themselves.

On first activation, the bridge sets the root-channel cursor to the newest existing message without dispatching historical content. Only later messages are eligible. This startup boundary prevents installation in a reused public channel from executing old owner requests.

Gateway socket reads and heartbeats do not perform REST or SQLite work. Dispatches enter a bounded queue of 1,000 items, and one serial ingress dispatcher performs reconciliation, permission checks, admission, and message handling. A separate bounded pool owns one App Server per slot. Queue exhaustion aborts the socket so reconnect reconciliation can recover from durable cursors. This protects heartbeats from slow disk, REST, or model operations and bounds in-memory event growth.

## Secret storage

On macOS, use the installer prompts so secrets go directly into Keychain:

| Credential | Service | Account |
| --- | --- | --- |
| Claude Discord bot | `discoparty-secret` | `discord-bot-token` |
| Codex Discord bot | `discoparty-secret` | `discord-bot-token-codex` |

Keychain is the source of truth for both Discord tokens. The [official Claude channels documentation](https://code.claude.com/docs/en/channels) accepts `DISCORD_BOT_TOKEN` through the process environment. Immediately before every Claude plugin launch, Disco Party validates the static policy and private state, reads the token from Keychain with environment fallback disabled as its final credential-producing operation, and uses `execve` to replace the wrapper with the pinned Claude process. The token is absent from argv and is never written to disk. A stale plugin `.env` blocks launch; controlled install and uninstall remove it.

The process environment is not a same-user boundary. A same-user process, including full-access Codex, may inspect Claude process memory or environment or query Keychain. The Codex App Server child does not inherit the Discord token.

Do not manually place real tokens in environment files, `config.toml`, plist files, token files, shell commands, screenshots, logs, issue reports, or commits.

The Codex ChatGPT credential is managed by the official Codex login flow in the macOS Keychain item scoped from Disco Party's isolated `CODEX_HOME`. Normal `~/.codex` is not used. Disco Party requires exact `keyring` mode, disables filesystem secret storage, rejects every known `auth.json` or sibling credential artifact, requires CLI ChatGPT login status, and binds App Server's nonsecret ChatGPT email and plan facts. It does not read, copy, log, or transform the Keychain credential into an API key.

The `account/read` binding is intentionally a state-binding mechanism, not credential verification. The official Codex client and OpenAI service perform upstream authentication. Full access can query same-user Keychain items or modify the bridge code itself, so isolated configuration and principal binding are not protection from an uncontained agent.

`bash uninstall.sh --codex` removes the LaunchAgent, monitor, and normally the Codex Discord Keychain entry. After service shutdown it also performs an official logout scoped to the isolated `CODEX_HOME` and verifies the scoped login and filesystem credential state are absent. `--keep-chatgpt-login` is an explicit opt-in. It intentionally retains `config.toml`, SQLite and App Server noncredential state, repository service logs, and immutable Python runtimes for audit or reinstall. Delete the private state directory and retained logs manually if that local history must also be removed.

If a bot token may have leaked, rotate only that provider's token in the Discord Developer Portal and replace its corresponding Keychain entry. Then rerun preflight and the live Discord acceptance test.

## What Disco Party protects against

- Non-owner Discord users starting Codex work
- A Claude non-owner producing a valid owner-bound button review marker
- Bot, webhook, wrong-guild, wrong-channel, wrong-application, and wrong-message-type Codex events
- Codex bot membership in an additional Discord server at Gateway READY
- A wrong, trust-baseline, obfuscated, malformed, under-permissioned, over-privileged, guild-owner, pending, or timed-out Codex bot and channel configuration
- Accidental reuse of a Discord event with changed content
- Normal `~/.codex` config, credentials, MCP servers, and plugins being loaded through the isolated `CODEX_HOME`
- Silent Codex protocol drift after a CLI upgrade
- Best-effort masking of common credential and sensitive-data shapes in Codex public output
- Unrelated guild-channel visibility at verified startup and during periodic or event-driven permission checks
- Duplicate Codex Discord replies after common crash and lost-response scenarios
- A stale Codex worker completing a job after losing its lease
- A restart loop consuming an unlimited number of locally permitted IDENTIFY attempts

## What Disco Party does not protect against

- Malware or another process running as the local user
- A takeover of the configured owner Discord account
- A takeover of the Claude, ChatGPT, or macOS account
- Compromise or misuse of the official ChatGPT credential in same-user Keychain; Disco Party binds the reported account but does not create a separate authentication boundary
- A leaked bot token used outside Disco Party
- Prompt injection that stays within the permissions granted to an agent
- Same-user credential access, Keychain queries, process control, and network authority under `danger-full-access`
- Visual Browser or Computer Use parity through the headless App Server bridge
- A same-user full-access process modifying canonical shared skills during an active turn
- Authorization of third-party sends from a Discord review reference alone
- Prompt injection through repository files, webpages, messages, or other content the model reads during a task
- Built-in full-mode capability changes that pass the pinned protocol and policy review
- Every possible sensitive datum in model output
- Sensitive input already posted to a public Discord channel
- An external action that completed before a worker crashed
- Physical access to an unlocked Mac
- A malicious or compromised dependency, CLI binary, optional trusted instruction file, or built-in capability that was approved into the installation
- Discord or model-provider outages and retention policies
- Growth or long-lived sensitive content in App Server rollout state outside the SQLite retention and capacity limits

## Deployment checklist

Before enabling Codex in a real server:

- [ ] Claude and Codex use separate applications, bots, tokens, and channels.
- [ ] The Codex application is dedicated to this integration, and Gateway READY proves its bot belongs only to the configured server.
- [ ] Discord IDs were copied with Developer Mode and independently checked.
- [ ] The Codex owner ID belongs to one MFA-protected personal account.
- [ ] Each bot has only the permissions it needs.
- [ ] Both tokens are in separate Keychain accounts, no stale Claude plugin `.env` exists, and the launcher passes its no-disk credential checks.
- [ ] Preflight proved the standard Claude and Codex token sources differ, or custom token separation was checked manually.
- [ ] The isolated `state_dir/home/.codex` login reports the intended ChatGPT account, and normal `~/.codex` is not reused.
- [ ] Preflight requires exact keyring mode, rejects filesystem credential artifacts, and passes the ChatGPT `account/read` binding without logging the email.
- [ ] `OPENAI_API_KEY` is absent from the service environment.
- [ ] Codex CLI is exactly `0.151.0`, and preflight reports `gpt-5.6-sol`, OpenAI provider, Ultra reasoning, and the reviewed schema and binary pins.
- [ ] Codex preflight passes without bypasses.
- [ ] Installer bootstrap produced a fresh readiness marker, and an end-to-end owner message was verified in Discord. A loaded LaunchAgent alone was not treated as readiness.
- [ ] Preflight verifies `GUILD_TEXT`, non-obfuscated flags, exact bot and application identity, active non-owner membership, no forbidden guild or configured-channel capabilities, and all six required permissions. Public trust keeps `@everyone` View Channel effective; owner-private trust proves the exact private reader topology.
- [ ] Preflight's guild-channel and active-thread enumeration confirms the bot can View only `#chatgpt`, its exact declared parent category when present, and its active public child threads.
- [ ] The working directory is the narrowest useful directory and does not overlap repository, config, state, logs, LaunchAgent plist, trusted instruction file, or shared-skill source.
- [ ] Preflight discovers exactly the canonical skill-finder, ELI5, VinayTalks, and triage paths, and their complete closure hash matches the bound policy.
- [ ] The canonical Vault P0 source and private derived snapshot match their bound hashes, with no second prose copy.
- [ ] The custom `discoparty-workspace-only` profile remains selected, or danger-full-access has the exact acknowledgment, automatic canonical Vault bootstrap, and documented risk acceptance. This sandbox choice is independent of channel trust.
- [ ] The exact canonical hook definitions and complete script closure match policy, `hooks/list` reports no extra or failed entry, and a supported-tool denial canary passes.
- [ ] No third-party outbound sender is enabled from a Discord review reference alone.
- [ ] Admission, worker-concurrency, pending-job, input, retention, and database limits match the deployment's risk budget.
- [ ] App Server rollout state under the isolated `CODEX_HOME` has a separate inspection and deletion plan if local retention matters.
- [ ] A non-owner Discord test creates no Codex reaction, thread, or job.
- [ ] An owner test produces an eyes reaction, thread, and reply.
- [ ] Sensitive-output canaries demonstrate best-effort redact-never-withhold behavior without treating public delivery as confidential, and ambiguous-approval canaries fail safely.
- [ ] Backups, monitoring, and token-rotation steps are understood.

## Reporting a vulnerability

Do not file a public GitHub issue for a suspected security vulnerability. Email the maintainer through the address on the repository owner's GitHub profile.

Include:

1. A concise description and expected impact.
2. Reproduction steps or a minimal proof of concept.
3. The affected provider and version.
4. Whether the issue crosses the owner, channel, bot, sandbox, approval, output, or delivery boundary.
5. A suggested remediation if you have one.

High-priority areas include non-owner Codex execution, cross-provider routing, approval bypass, file exfiltration, bot-token leakage, protocol-pin bypass, public-output disclosure, and duplicate external effects.
