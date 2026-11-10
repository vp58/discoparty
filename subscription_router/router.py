#!/usr/bin/env python3
"""Disco Party subscription router.

Spreads headless agent work across several AI subscriptions (more than one
Claude login, Codex, Google Antigravity, Cursor and so on). For each task it:

1. takes the lane's ordered chain from the registry,
2. drops accounts that are disabled, out of scope, missing a needed
   capability, signed out, or cooling after a limit,
3. keeps only tier "A" accounts when a need demands the full hook layer,
4. runs the prompt on the first survivor and fails over on a limit message.

Limits are learned from the providers' own messages: the stated reset time
becomes a cooldown, and a plan or policy block rests the account for a week.
Every decision and run is logged with the account AND the model that served it.

Commands
  route        --task-type LANE [--scope S] [--needs a,b]   print the chain (JSON)
  run          --task-type LANE [--scope S] [--needs a,b] [--model M] --prompt TEXT
  claude-chain [--scope S]          Claude config dirs in order ("default" = normal login)
  record-run   --account ID --model M [--job NAME] [--rc N]
  record-limit --account ID --file PATH [--reason TEXT]
  clear        --account ID
  status | probe

Environment
  DISCOPARTY_ROUTER_REGISTRY   path to accounts.toml
  DISCOPARTY_ROUTER_STATE_DIR  where cooldowns and logs live
  DISCOPARTY_ROUTER_DISABLE=1  rollback switch (claude-chain prints "default")

The router never reads or prints credentials and never starts a login.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import tomllib
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

HERE = Path(__file__).resolve().parent
SCOPES = ("personal", "company", "both")
STRIP_ENV = ("ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY", "XAI_API_KEY")

LIMIT = re.compile(
    r"you.{0,3}ve hit your ([\w-]+ )?limit|usage limit|rate.?limit(ed)?|quota exceeded|"
    r"resource.?exhausted|too many requests|\b429\b|usage cap",
    re.I,
)
BLOCK = re.compile(
    r"IneligibleTierError|no longer supported|not available (on|for) your (plan|tier)|"
    r"plugins? (are )?blocked|org(anization)? policy|not entitled",
    re.I,
)
RESET_CLOCK = re.compile(r"resets?\s+(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:\(([\w/+-]+)\))?", re.I)
RESET_IN = re.compile(r"(?:try again|resets?)\s+in\s+(\d+)\s*(second|minute|hour)s?", re.I)
BLOCK_COOLDOWN_MINUTES = 7 * 24 * 60


def now() -> datetime:
    return datetime.now(timezone.utc)


def registry_path() -> Path:
    env = os.environ.get("DISCOPARTY_ROUTER_REGISTRY")
    if env:
        return Path(env).expanduser()
    local = HERE / "accounts.toml"
    return local if local.exists() else HERE / "accounts.example.toml"


def state_dir() -> Path:
    d = Path(os.environ.get("DISCOPARTY_ROUTER_STATE_DIR", "~/.discoparty/router")).expanduser()
    d.mkdir(parents=True, exist_ok=True)
    return d


def load_registry(path: Path | None = None) -> dict:
    with open(path or registry_path(), "rb") as f:
        reg = tomllib.load(f)
    for aid, acct in reg.get("accounts", {}).items():
        if acct.get("scope", "both") not in SCOPES:
            raise ValueError(f"account {aid}: scope must be one of {SCOPES}")
    for lane, ids in reg.get("lanes", {}).items():
        missing = [i for i in ids if i not in reg.get("accounts", {})]
        if missing:
            raise ValueError(f"lane {lane}: unknown accounts {missing}")
    return reg


def disabled(reg: dict) -> bool:
    return os.environ.get("DISCOPARTY_ROUTER_DISABLE") == "1" or not reg.get("enabled", True)


# ---------------------------------------------------------------- state

def _cool_file() -> Path:
    return state_dir() / "cooldowns.json"


def load_cool() -> dict:
    try:
        return json.loads(_cool_file().read_text())
    except (FileNotFoundError, ValueError):
        return {}


def save_cool(data: dict) -> None:
    tmp = _cool_file().with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=1))
    os.replace(tmp, _cool_file())


def log(name: str, rec: dict) -> None:
    rec = dict(rec, at=now().isoformat(timespec="seconds"))
    with open(state_dir() / name, "a") as f:
        f.write(json.dumps(rec) + "\n")


def cooling(acct_id: str, cool: dict | None = None) -> dict | None:
    c = (cool if cool is not None else load_cool()).get(acct_id)
    if not c:
        return None
    return c if datetime.fromisoformat(c["until"]) > now() else None


# ---------------------------------------------------------------- accounts

def config_dir(acct: dict) -> Path | None:
    d = acct.get("config_dir")
    return None if d in (None, "default") else Path(d).expanduser()


def signed_in(acct: dict) -> bool:
    """Value-free check. For Claude, read only whether the profile names an account."""
    if acct.get("launcher") != "claude":
        return True  # other CLIs are checked by `probe` through their own status commands
    d = config_dir(acct) or Path.home()
    try:
        data = json.loads((d / ".claude.json").read_text())
    except (FileNotFoundError, ValueError):
        return False
    return bool((data.get("oauthAccount") or {}).get("emailAddress"))


def chain(task_type: str, scope: str = "both", needs=(), reg: dict | None = None,
          log_it: bool = True, signed_in_fn=signed_in) -> dict:
    reg = reg or load_registry()
    lane = reg.get("lanes", {}).get(task_type)
    if lane is None:
        raise SystemExit(f"router: unknown task type {task_type!r} (lanes: {', '.join(reg.get('lanes', {}))})")
    needs = [n for n in needs if n]
    tier_a = any(n in reg.get("tier_a_needs", []) for n in needs)
    cool = load_cool()
    picked, skipped = [], []
    for aid in lane:
        a = reg["accounts"][aid]
        caps = a.get("capabilities", [])
        why = None
        if not a.get("enabled", True):
            why = "disabled"
        elif scope == "personal" and a.get("scope") == "company":
            why = "scope: company-only account"
        elif scope == "company" and a.get("scope") == "personal":
            why = "scope: personal-only account"
        elif tier_a and a.get("tier") != "A":
            why = "tier: needs the full hook layer"
        elif any(n not in caps for n in needs):
            why = "missing capability: " + ",".join(n for n in needs if n not in caps)
        elif not signed_in_fn(a):
            why = "not signed in"
        elif cooling(aid, cool):
            why = "cooling until " + cool[aid]["until"]
        (skipped.append({"account": aid, "why": why}) if why else picked.append(aid))
    dec = {"task_type": task_type, "scope": scope, "needs": needs,
           "chosen": picked[0] if picked else None, "chain": picked, "skipped": skipped}
    if log_it:
        log("decisions.jsonl", dict(dec, event="route"))
    return dec


# ---------------------------------------------------------------- limits

def parse_reset(text: str, ref: datetime | None = None) -> datetime | None:
    """Turn 'resets 11pm (America/New_York)' or 'try again in 20 minutes' into a UTC time."""
    ref = ref or now()
    m = RESET_IN.search(text)
    if m:
        n, unit = int(m.group(1)), m.group(2).lower()
        return ref + timedelta(**{unit + "s": n})
    m = RESET_CLOCK.search(text)
    if m and (m.group(3) or m.group(2)):
        hour, minute = int(m.group(1)), int(m.group(2) or 0)
        ampm = (m.group(3) or "").lower()
        if ampm == "pm" and hour != 12:
            hour += 12
        if ampm == "am" and hour == 12:
            hour = 0
        if hour > 23 or minute > 59:
            return None
        try:
            tz = ZoneInfo(m.group(4)) if m.group(4) else timezone.utc
        except Exception:
            tz = timezone.utc
        local = ref.astimezone(tz)
        at = local.replace(hour=hour, minute=minute, second=0, microsecond=0)
        if at <= local:
            at += timedelta(days=1)
        return at.astimezone(timezone.utc)
    return None


def record_limit(acct_id: str, text: str, reason: str = "", reg: dict | None = None,
                 minutes: int | None = None) -> dict:
    reg = reg or load_registry()
    reset = None if minutes else parse_reset(text)
    until = reset or now() + timedelta(minutes=minutes or int(reg.get("default_cooldown_minutes", 60)))
    cool = load_cool()
    cool[acct_id] = {"until": until.isoformat(timespec="seconds"), "reason": reason or "rate limit",
                     "reset_parsed": bool(reset), "set_at": now().isoformat(timespec="seconds")}
    save_cool(cool)
    m = LIMIT.search(text) or BLOCK.search(text)
    snippet = text[max(0, m.start() - 40):m.end() + 80].replace("\n", " ")[:200] if m else ""
    log("learned-limits.jsonl", {"account": acct_id, "until": cool[acct_id]["until"],
                                 "reset_parsed": bool(reset), "reason": reason, "message": snippet})
    return cool[acct_id]


def is_limited(out: str, err: str, rc: int) -> bool:
    """A limit counts only when the run failed or produced almost nothing."""
    return bool(LIMIT.search(out + "\n" + err)) and (rc != 0 or len(out.strip().splitlines()) <= 3)


# ---------------------------------------------------------------- running

def effective_model(acct: dict, model: str | None) -> str:
    if acct["launcher"] == "claude":
        return model or acct.get("default_model", "sonnet")
    return acct.get("default_model") or "cli-default"


def build_cmd(acct: dict, prompt: str, model: str | None = None):
    env = {k: v for k, v in os.environ.items() if k not in STRIP_ENV}
    launcher = acct["launcher"]
    stdin = None
    if launcher == "claude":
        d = config_dir(acct)
        if d:
            env["CLAUDE_CONFIG_DIR"] = str(d)
        else:
            env.pop("CLAUDE_CONFIG_DIR", None)
        cmd = ["claude", "-p", prompt, "--model", effective_model(acct, model)]
    elif launcher == "codex":
        cmd = ["codex", "exec", "--skip-git-repo-check", "--sandbox", "read-only", "-"]
        stdin = prompt
    elif launcher == "agy":
        # Google Antigravity CLI. Plan mode keeps it read-only, like codex --sandbox read-only.
        cmd = ["agy", "-p", prompt, "--mode", "plan"]
    elif launcher == "cursor":
        cmd = ["cursor-agent", "-p", prompt, "--output-format", "text"]
    else:
        raise ValueError("unknown launcher " + launcher)
    return cmd, env, stdin


def _exec(cmd, env, stdin, timeout, cwd):
    try:
        p = subprocess.run(cmd, input=stdin, capture_output=True, text=True, env=env, timeout=timeout, cwd=cwd)
        return p.stdout or "", p.stderr or "", p.returncode
    except subprocess.TimeoutExpired:
        return "", "timeout", 124
    except FileNotFoundError as e:
        return "", str(e), 127


def run(task_type: str, scope: str, needs, prompt: str, model: str | None = None,
        timeout: int = 600, cwd: str | None = None, executor=_exec, reg: dict | None = None,
        signed_in_fn=signed_in):
    reg = reg or load_registry()
    dec = chain(task_type, scope, needs, reg, signed_in_fn=signed_in_fn)
    attempts = []
    for aid in dec["chain"]:
        acct = reg["accounts"][aid]
        used_model = effective_model(acct, model if acct["launcher"] == "claude" else None)
        cmd, env, stdin = build_cmd(acct, prompt, model if acct["launcher"] == "claude" else None)
        t0 = time.time()
        out, err, rc = executor(cmd, env, stdin, timeout, cwd)
        both = out + "\n" + err
        blocked = rc != 0 and bool(BLOCK.search(both))
        limited = not blocked and is_limited(out, err, rc)
        attempts.append({"account": aid, "model": used_model, "rc": rc,
                         "ms": int((time.time() - t0) * 1000), "limited": limited, "blocked": blocked})
        if blocked:
            record_limit(aid, both, "plan or policy block learned during run", reg, BLOCK_COOLDOWN_MINUTES)
            continue
        if limited:
            record_limit(aid, both, "limit message during run", reg)
            continue
        if rc == 0:
            log("decisions.jsonl", {"event": "run", "served_by": aid, "model": used_model,
                                    "task_type": task_type, "scope": scope, "attempts": attempts})
            return {"served_by": aid, "model": used_model, "task_type": task_type, "scope": scope,
                    "attempts": attempts, "output": (out.strip() or err.strip())[-2000:]}, 0
    log("decisions.jsonl", {"event": "run", "served_by": None, "task_type": task_type,
                            "scope": scope, "attempts": attempts})
    return {"served_by": None, "attempts": attempts, "skipped": dec["skipped"]}, 75


# ---------------------------------------------------------------- probe

def _status_ok(cmd, expect: str = "logged in") -> bool | None:
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    text = (p.stdout + p.stderr).lower()
    return expect in text and (expect == "logged in" or p.returncode == 0)


def probe(reg: dict | None = None) -> dict:
    reg = reg or load_registry()
    cool = load_cool()
    res = {}
    for aid, a in reg["accounts"].items():
        launcher = a["launcher"]
        if launcher == "claude":
            ok = signed_in(a)
        elif launcher == "codex":
            ok = _status_ok(["codex", "login", "status"])
        elif launcher == "cursor":
            ok = _status_ok(["cursor-agent", "status"])
        elif launcher == "agy":
            ok = _status_ok(["agy", "models"], expect="gemini")  # listing models needs a live sign-in
        else:
            ok = None  # unknown: learned from run results instead
        c = cooling(aid, cool)
        res[aid] = {"launcher": launcher, "scope": a.get("scope", "both"), "signed_in": ok,
                    "cooling_until": c["until"] if c else None,
                    "headroom": "cooling" if c else ("ok" if ok else "unavailable" if ok is False else "unknown")}
    cutoff = (now() - timedelta(hours=24)).isoformat()
    try:
        for line in open(state_dir() / "decisions.jsonl"):
            d = json.loads(line)
            who = d.get("served_by")
            if d.get("event") == "run" and who in res and d.get("at", "") >= cutoff:
                models = res[who].setdefault("models_24h", {})
                key = d.get("model") or "unrecorded"
                models[key] = models.get(key, 0) + 1
    except FileNotFoundError:
        pass
    out = {"at": now().isoformat(timespec="seconds"), "enabled": not disabled(reg), "accounts": res}
    (state_dir() / "probe.json").write_text(json.dumps(out, indent=1))
    return out


# ---------------------------------------------------------------- CLI

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("route", "run"):
        s = sub.add_parser(name)
        s.add_argument("--task-type", required=True)
        s.add_argument("--scope", default="both", choices=SCOPES)
        s.add_argument("--needs", default="")
        if name == "run":
            s.add_argument("--prompt", required=True)
            s.add_argument("--model")
            s.add_argument("--timeout", type=int, default=600)
    s = sub.add_parser("claude-chain")
    s.add_argument("--scope", default="both", choices=SCOPES)
    s.add_argument("--task-type", default="claude")
    s = sub.add_parser("record-run")
    s.add_argument("--account", required=True)
    s.add_argument("--model", required=True)
    s.add_argument("--job", default="")
    s.add_argument("--rc", type=int, default=0)
    s = sub.add_parser("record-limit")
    s.add_argument("--account", required=True)
    s.add_argument("--file", required=True)
    s.add_argument("--reason", default="")
    s = sub.add_parser("clear")
    s.add_argument("--account", required=True)
    sub.add_parser("status")
    sub.add_parser("probe")
    a = ap.parse_args(argv)
    reg = load_registry()

    if a.cmd == "claude-chain":
        if disabled(reg):
            print("default")
            return 0
        dec = chain(a.task_type, a.scope, (), reg)
        dirs = [str(config_dir(reg["accounts"][i]) or "default") for i in dec["chain"]
                if reg["accounts"][i]["launcher"] == "claude"]
        print("\n".join(dirs or ["default"]))
        return 0
    if a.cmd == "route":
        print(json.dumps(chain(a.task_type, a.scope, a.needs.split(","), reg), indent=1))
        return 0
    if a.cmd == "run":
        if disabled(reg):
            print(json.dumps({"error": "router disabled"}))
            return 78
        res, rc = run(a.task_type, a.scope, a.needs.split(","), a.prompt, a.model, a.timeout, reg=reg)
        print(json.dumps(res, indent=1))
        return rc
    if a.cmd == "record-run":
        log("decisions.jsonl", {"event": "run", "served_by": a.account, "model": a.model,
                                "job": a.job, "rc": a.rc, "source": "external"})
        return 0
    if a.cmd == "record-limit":
        print(json.dumps(record_limit(a.account, Path(a.file).read_text(errors="replace"), a.reason, reg)))
        return 0
    if a.cmd == "clear":
        cool = load_cool()
        cool.pop(a.account, None)
        save_cool(cool)
        print("cleared " + a.account)
        return 0
    if a.cmd == "status":
        cool = load_cool()
        print(json.dumps({"enabled": not disabled(reg), "accounts": {
            k: {"scope": v.get("scope", "both"), "tier": v.get("tier"), "signed_in": signed_in(v),
                "cooling": (cooling(k, cool) or {}).get("until")} for k, v in reg["accounts"].items()}}, indent=1))
        return 0
    if a.cmd == "probe":
        try:
            prev = json.loads((state_dir() / "probe.json").read_text()).get("accounts", {})
        except (FileNotFoundError, ValueError):
            prev = {}
        out = probe(reg)
        print(json.dumps(out, indent=1))
        lapsed = [k for k, v in out["accounts"].items() if prev.get(k, {}).get("signed_in") and v["signed_in"] is False]
        claude_ok = [k for k, v in out["accounts"].items() if v["launcher"] == "claude" and v["headroom"] == "ok"]
        if lapsed:
            sys.stderr.write("router probe: sign-in lapsed for %s\n" % ", ".join(lapsed))
            return 2
        if not claude_ok:
            sys.stderr.write("router probe: no Claude account has headroom\n")
            return 2
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
