# Contributing to Disco Party

Thanks for taking the time to improve Disco Party. This project now has two provider paths with different runtimes and security contracts. Keep changes focused and preserve the boundary between them.

## Filing an issue

Open a GitHub issue at https://github.com/vp58/discoparty/issues and include:

- Which provider is affected: Claude, Codex, or shared configuration
- What you were trying to do
- What you expected to happen
- What actually happened
- Operating system and hardware architecture
- Python version
- Claude Code version when the Claude provider is affected
- Codex CLI version and `codex login status` method when the Codex provider is affected, with account details removed
- Relevant redacted log excerpts
- Whether the failure occurred in Discord, the local runtime, model authentication, state reconciliation, output delivery, or monitoring

Never include bot tokens, OAuth material, API keys, owner personal data, private prompts, Keychain output, or confidential model responses.

If the issue is security-related, do not file a public issue. Follow `docs/SECURITY.md`.

## Pull request flow

1. Fork the repository or create a branch off `main` if you have write access.
2. Use a descriptive branch such as `feat/short-summary`, `fix/short-summary`, or `docs/short-summary`.
3. Make a focused change.
4. Update the relevant public documentation when behavior changes.
5. Add or update tests at the natural coverage location.
6. Push the branch and open a pull request against `main`.
7. Complete the PR template with the provider, security boundary, verification, risks, and rollback notes.
8. One reviewer approval is enough to merge. Documentation-only changes from maintainers may self-merge.
9. Squash or rebase is fine. Keep history readable.

Large changes should start with an issue that describes the intended trust model and migration path.

## Provider compatibility rules

- `bash install.sh` remains the backward-compatible Claude install path.
- Codex stays opt-in through `bash install-codex.sh`.
- Claude and Codex must use separate Discord applications, bots, tokens, and channels.
- The Codex application and bot remain dedicated to one integration and one configured Discord server.
- A Codex feature must not silently inherit a Claude outbound adapter or approval result.
- A Claude feature must not depend on the Codex CLI, ChatGPT login, SQLite job store, or LaunchAgent.
- Shared configuration changes must load older Claude-only configurations with safe Codex defaults.
- A writable Codex workspace must never overlap the repository, config, state, or logs control plane.
- New Codex authority defaults to Disco Party's custom root-deny `discoparty-workspace-only` profile with agent-tool network disabled.
- `danger-full-access` remains an explicit high-risk opt-in. Changes to its exact acknowledgement, owner-only ingress, public-output sanitization, or fail-closed runtime checks require a new threat model and bypass test.
- Do not introduce plaintext secret storage or embed credentials in config, logs, plists, fixtures, or tests.
- Do not describe behavioral exact-later approval as an enforcement boundary.

## Code style

- Python uses the standard library where practical. `websockets` remains the required runtime dependency.
- Use absolute imports, type hints where they clarify behavior, and small focused functions.
- Bash scripts use `set -euo pipefail` unless a documented recovery script needs narrower error handling.
- Do not use em dashes in user-facing strings, code comments, or documentation.
- Configuration goes through `conversations/config.py`. Do not hardcode deployment-specific paths or Discord IDs.
- Authorization uses immutable IDs, never names, roles, labels, or visible text.
- Security errors should avoid echoing prompts, tokens, schema payloads, credentials, or sensitive responses.
- Unknown protocol messages and unsupported authority requests fail closed.

## Tests

Run the existing Claude and shared suites:

```sh
python3 -m unittest discover -s discord-gateway/tests -t discord-gateway -v
```

Run the Codex bridge suite:

```sh
PYTHONPATH=. python3 -m unittest discover -s codex-discord/tests -v
bash codex-discord/tests/test_install_codex.sh
```

Run the Codex preflight against the installed candidate when your change affects runtime configuration, authentication, Discord identity, binary pins, or App Server protocol:

```sh
PYTHONPATH=. python3 -m codex_discord_bridge.preflight
```

The unit suites use mocks and local files. They do not prove that a live Discord event reached the correct provider or that a ChatGPT subscription is usable. Describe live tests separately and never claim one was run when it was not.

## Codex protocol changes

OpenAI currently labels App Server experimental. Consult the official [Codex App Server documentation](https://learn.chatgpt.com/docs/app-server), [CLI reference](https://developers.openai.com/codex/cli/reference), and [changelog](https://learn.chatgpt.com/docs/changelog) before changing the integration.

The current reviewed baseline is Codex CLI `0.153.4`, native arm64, model `gpt-5.6-sol`, provider `openai`, and Ultra reasoning. The worker preserves the canonical user `HOME` for local computer access but sets an isolated `CODEX_HOME`; do not make it inherit normal `~/.codex` credentials or configuration.

The service also uses a private immutable Python venv whose path binds the CPython version, dependency version, and Apple Silicon lock hash. Update the lock, path identity, staging and atomic-publication logic, installed-distribution verification, and private manifest together when changing Python dependencies. Do not mutate an existing published runtime in place. Do not re-enable project-document discovery or automatic workspace `AGENTS.md` loading for Discord-triggered work.

A Codex CLI upgrade PR must include:

1. The old and candidate CLI versions.
2. The linked official release notes.
3. Launcher and native binary path and hash changes.
4. A generated experimental schema bundle comparison.
5. The added, removed, or changed server request methods.
6. Explicit safe handling for every new server request.
7. Sandbox, network, approval, authentication, and thread-lifecycle review notes.
8. Unit test output.
9. Preflight output with secrets and personal identifiers removed.
10. Opt-in approval evaluation and live Discord acceptance results when actually run.
11. Rollback instructions to the prior reviewed CLI and pins.

Do not weaken a version, path, binary, schema, or method-set check just to make a newer CLI start.

## Security-sensitive changes

Request focused review when a change touches:

- Discord ingress authorization
- Discord Gateway visibility outside the configured provider channel
- owner identity checks
- channel or managed-thread routing
- Keychain or model authentication
- isolated ChatGPT credential parsing and durable principal binding
- App Server request handling
- sandbox, writable roots, network access, or full computer access
- public-output filtering
- approval semantics or outbound adapters
- leases, fencing generations, cursors, delivery manifests, hashes, nonces, or reconciliation
- policy-fingerprint inputs or stale-policy quarantine
- rate, pending-job, input, retention, or database-capacity limits
- readiness marker publication or installer readiness polling
- Gateway IDENTIFY or RESUME behavior
- log content or monitoring output

Add a test that demonstrates both the allowed case and the denied or recovered case. For delivery or restart changes, include a fault test at every boundary where an external effect can occur before local state is committed.

## Documentation expectations

When provider behavior changes, update the relevant file under `docs/` and keep the README summary consistent.

For Codex product facts, link directly to current official OpenAI documentation at `developers.openai.com` or its official redirect target. Separate upstream behavior from Disco Party policy. For example, state that OpenAI offers multiple authentication modes, then state that Disco Party allows only ChatGPT login.

Avoid promises that cannot be established by code or tests. Use `expected`, `experimental`, or `not yet verified` when that is the actual state.

## What we are not looking for

- Full computer access as a default
- One shared Discord bot or channel for both providers
- Automatic acceptance of the newest Codex CLI or schema
- Generic Discord approval buttons that grant broad Codex authority
- Plaintext credential files, committed `.env` secrets, or tokens in launchd plists
- Silent reruns of uncertain Codex work
- Re-enabling the retired marker watcher or treating a Discord review reference as a send capability
- Third-party outbound integrations without a separately reviewed, one-time receipt gate and isolated credential holder
- Required dependencies without a strong reason

## Code of Conduct

This project follows the Contributor Covenant. See `CODE_OF_CONDUCT.md`.
