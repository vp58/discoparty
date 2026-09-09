# Changelog

All notable changes to Disco Party will be documented in this file.

This project follows the spirit of Keep a Changelog and uses semantic versioning once tagged releases begin.

## [Unreleased]

### Added

- Optional Codex Discord orchestrator with a dedicated bot, channel, owner-only ingress policy, headless LaunchAgent, official OpenAI App Server client, and read-only local monitor.
- Isolated Codex `CODEX_HOME`, reviewed config, and separately scoped ChatGPT subscription login through the official macOS Keychain backend, without a manually supplied OpenAI API key or reuse of normal `~/.codex`.
- Canonical Codex state placement below `~/Library/Application Support/Discoparty`, with matching installer and runtime ownership, mode, topology, and symlink checks so authentication and rollout state cannot be redirected into another Git checkout or synced working tree.
- Private immutable Apple Silicon Python venv identified by CPython version, dependency version, and lock hash, with binary-only wheels, installed-distribution verification, a private manifest, and atomic publication.
- Exact official Codex CLI `0.151.0` native arm64 pin with `gpt-5.6-sol`, OpenAI provider, Ultra reasoning, and fallback disabled.
- Custom `discoparty-workspace-only` default with root and temporary-directory denies, agent-tool network off, untrusted project roots, and disabled project config, MCP, apps, web, Browser, Computer Use, hooks, plugins, local automation, skill search, and every non-canonical skill.
- Exact shared Vault ELI5 and VinayTalks discovery through a validated two-link isolated bridge, complete closure hashing, policy-fingerprint binding, explicit per-turn skill items, and drift checks before and immediately after turn start.
- Mechanically derived mode `0400` snapshot of the six canonical Vault P0 sections, with source and snapshot hashes bound into policy and revalidated around every Codex turn. Claude validates the same seal at launcher startup and inherits it through listener and subagent prompts.
- Disabled project-document discovery and rejected administrator configuration requirements in both authority modes, with the optional external `instructions_file` as the only additional instruction source. Trusted file loading rejects hardlinks, symlink components, unstable or writable ancestry, and lexical, canonical, or filesystem-alias overlap with the workspace.
- Explicit release block for `danger-full-access` after exact Codex `0.151.0` testing showed that hook framework and process failures can fail open. The reviewed workspace-only profile remains the supported authority boundary.
- Exact canonical Vault security, written-text, and deny-only outbound Hooks with private isolated configuration, complete script-closure binding, `hooks/list` attestation, and run-event monitoring as defense in depth.
- Strict Discord REST identity, `GUILD_TEXT`, public `@everyone` baseline, active non-owner membership, broad forbidden guild and configured-channel capability rejection, overwrite precedence, required-permission verification, and runtime drift checks.
- Enforced Discord visibility isolation through guild-channel and active-thread enumeration, allowing View Channel only on configured `#chatgpt`, its exact parent category when present, and active public child threads beneath it.
- Dedicated single-server Codex bot enforcement through exact Gateway READY guild inventory and fail-closed foreign-guild security-event validation.
- Bounded queued Discord Gateway dispatch that separates heartbeats and socket reads from serial REST and SQLite processing.
- Codex durable SQLite jobs, readiness state, leases, fencing generations, managed-thread mappings, channel cursors, delivery manifests, hashes, and Discord nonces.
- Configurable Codex rate, pending-job, input, retention, and logical database-capacity limits.
- Explicit disclosure that SQLite retention and capacity do not prune or bound App Server rollout state under the isolated `CODEX_HOME`.
- Policy-fingerprint binding for jobs, managed Discord threads, Codex session scopes, and delivery manifests.
- Exact Keychain credential mode with filesystem `auth.json` rejection, official login-status verification, and durable ChatGPT principal binding from nonsecret App Server `account/read` email and plan facts, with the email withheld and prior routing quarantined after a login change.
- Bounded Codex App Server worker pool with one through four slots, default three, parallel progress for independent Discord threads, strict same-thread ordering, uncertain-job blocking, and pool-wide readiness and failure fencing. Built-in multi-agent stays disabled in every authority mode.
- Pre-persistence sensitive-input rejection for Codex owner messages and Claude queue intake, plus whole-field withholding in the local monitor.
- Fresh two-sided Gateway and App Server readiness marker required during installer bootstrap.
- Persistent Discord Gateway IDENTIFY budget with RESUME-first reconnect behavior.
- Codex public-output withholding, disabled Discord mentions, and exact later owner-approval instructions.
- Exact Apple M5 Max-gated installer and fail-closed pins for the reviewed Codex CLI, launcher, Apple Silicon binary, experimental schema bundle, and server request method set.
- Separate Codex installer and Keychain account so the original Claude installation remains backward compatible.
- Keychain-to-process Claude token launch with no credential in argv or on disk, stale plugin `.env` rejection, and explicit same-user process-memory risk.
- Explicit legacy `com.thesystem` Codex takeover with exact plist and ledger validation, dual-run refusal, opt-in Keychain import over standard input, late process-tree quiesce, private backup, policy-scoped root-cursor handoff, fail-closed bootstrap authorization, and rollback state tracking.
- Dual-provider setup, architecture, security, operations, FAQ, and contribution documentation with official OpenAI references.
- GitHub Actions CI for Python 3.11, 3.12, and 3.13.
- Root Code of Conduct.
- FAQ covering setup, security, multi-channel behavior, and approval buttons.
- Legacy dry-run Slack payload parser retained as unsupported reference material; the installer removes the obsolete marker-watcher and installs no outbound sender.
- README badges, contents, and first-message walkthrough.

### Changed

- Moved the reviewed Codex CLI pin from `0.151.0` to `0.153.4`, with re-verified npm launcher and native arm64 binary SHA-256 hashes and a regenerated experimental schema bundle hash. The prior pin made the bridge refuse to start on a current Codex install.

## [0.1.0-pre] - 2026-05-24

### Added

- Public Disco Party repo with install path, uninstall path, launchd templates, systemd templates, setup docs, architecture docs, security docs, issue templates, and PR template.
- Persistent Discord listener and worker-dispatch pattern extracted from the original private deployment.
- Discord approval gateway and marker watcher for review-gated outbound sends.
- Identity persistence hooks for Claude Code listener sessions.
