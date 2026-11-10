# Subscription router

The subscription router is an optional, stdlib-only module that decides which AI subscription runs a headless task. It suits setups with several logins: two or more Claude profiles, a company Claude seat, a ChatGPT plan for Codex, Cursor, or Gemini.

## Setup

1. Copy `subscription_router/accounts.example.toml` to `subscription_router/accounts.toml` (gitignored), or point `DISCOPARTY_ROUTER_REGISTRY` at your copy.
2. For each extra Claude login, pick a profile directory and sign in once by hand:
   `CLAUDE_CONFIG_DIR=~/.claude-secondary claude /login`
3. List each account's `scope`, `tier` and `capabilities`, then order the `lanes`. Put the account with the most headroom first.
4. Check the result: `python3 subscription_router/router.py route --task-type claude --scope personal`

State (cooldowns, `decisions.jsonl`, `learned-limits.jsonl`, `probe.json`) lives in `DISCOPARTY_ROUTER_STATE_DIR`, default `~/.discoparty/router`.

## How a task is routed

1. Take the lane's chain.
2. Drop accounts that are disabled, out of scope, missing a needed capability, signed out, or cooling.
3. When a need is listed in `tier_a_needs`, keep only tier "A" accounts. Tier A means the run carries your full hook layer.
4. Run on the first survivor. A limit message (`usage limit`, `429`, `quota exceeded` and similar) with little or no output puts that account on cooldown until its stated reset, or `default_cooldown_minutes`, and the next account runs the same prompt. A plan or policy block (for example an unsupported tier) rests the account for seven days.
5. Log the decision and the run, including the model.

A run that succeeds and merely mentions rate limits in a long answer is not treated as a limit.

## Wiring it into scripts

Headless Claude jobs can walk the Claude chain and fail over:

```bash
ROUTER=subscription_router/router.py
while IFS= read -r prof; do
  if [ "$prof" = default ]; then unset CLAUDE_CONFIG_DIR; else export CLAUDE_CONFIG_DIR="$prof"; fi
  out="$(claude -p "$PROMPT" --model opus 2>&1)" && {
    python3 "$ROUTER" record-run --account "$ACCOUNT_ID_FOR_PROF" --model opus --job "$JOB"
    printf '%s\n' "$out"; exit 0; }
  printf '%s' "$out" > /tmp/limit.txt
  python3 "$ROUTER" record-limit --account "$ACCOUNT_ID_FOR_PROF" --file /tmp/limit.txt --reason "$JOB"
done < <(python3 "$ROUTER" claude-chain --scope "${JOB_SCOPE:-both}")
```

Or let the router run the prompt end to end:

```bash
python3 subscription_router/router.py run --task-type research --scope both --prompt "Summarize this changelog"
```

Exit codes: `0` served, `75` every account was limited or failed, `78` router disabled.

## Probe

Run `router.py probe` on a schedule (for example every 15 minutes from a LaunchAgent). It records sign-in state from value-free checks (`codex login status`, `cursor-agent status`, Claude profile account presence), cooldowns, and per-model run counts for the last 24 hours. It exits `2` when a previously signed-in account lapses or when no Claude account has headroom, so your scheduler can raise an alert.

## Rollback

Set `DISCOPARTY_ROUTER_DISABLE=1` or `enabled = false`. `claude-chain` then prints only `default`, so callers fall back to the normal login, and `run` refuses with exit `78`.

## Security notes

- The router strips provider API keys from the child environment so runs use subscription sign-in.
- It never reads or prints tokens and never triggers a login or keychain prompt.
- Codex runs use `--sandbox read-only` by default. Keep sends and writes on tier "A" accounts.
