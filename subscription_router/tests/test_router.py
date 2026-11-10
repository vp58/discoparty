#!/usr/bin/env python3
"""Tests for the subscription router: filtering, failover, limit learning, model logging."""
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import router  # noqa: E402

EXAMPLE = HERE.parent / "accounts.example.toml"


def always_signed_in(_acct):
    return True


class RouterTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        mock_env = {"DISCOPARTY_ROUTER_STATE_DIR": self.tmp.name,
                               "DISCOPARTY_ROUTER_REGISTRY": str(EXAMPLE)}
        self._saved = {k: os.environ.get(k) for k in list(mock_env) + ["DISCOPARTY_ROUTER_DISABLE"]}
        os.environ.update(mock_env)
        os.environ.pop("DISCOPARTY_ROUTER_DISABLE", None)
        self.reg = router.load_registry()

    def tearDown(self):
        for k, v in self._saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        self.tmp.cleanup()

    def decisions(self):
        path = Path(self.tmp.name) / "decisions.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()]


class ChainTests(RouterTestCase):
    def test_lane_order_is_kept(self):
        dec = router.chain("claude", reg=self.reg, signed_in_fn=always_signed_in)
        self.assertEqual(dec["chain"], ["claude-secondary", "claude-primary", "claude-work"])

    def test_personal_task_skips_company_only_account(self):
        dec = router.chain("claude", scope="personal", reg=self.reg, signed_in_fn=always_signed_in)
        self.assertNotIn("claude-work", dec["chain"])
        self.assertIn({"account": "claude-work", "why": "scope: company-only account"}, dec["skipped"])

    def test_tier_a_need_keeps_only_hooked_accounts(self):
        dec = router.chain("cron", needs=["sends"], reg=self.reg, signed_in_fn=always_signed_in)
        self.assertTrue(all(self.reg["accounts"][a]["tier"] == "A" for a in dec["chain"]))
        self.assertNotIn("codex", dec["chain"])

    def test_missing_capability_is_filtered(self):
        dec = router.chain("claude", needs=["browser"], reg=self.reg, signed_in_fn=always_signed_in)
        self.assertEqual(dec["chain"], ["claude-primary"])

    def test_disabled_and_signed_out_accounts_are_skipped(self):
        dec = router.chain("research", reg=self.reg,
                           signed_in_fn=lambda a: a.get("config_dir") != "~/.claude-secondary")
        self.assertNotIn("antigravity", dec["chain"])
        self.assertNotIn("claude-secondary", dec["chain"])

    def test_cooling_account_is_skipped(self):
        router.record_limit("claude-secondary", "usage limit", reg=self.reg, minutes=30)
        dec = router.chain("claude", reg=self.reg, signed_in_fn=always_signed_in)
        self.assertEqual(dec["chosen"], "claude-primary")

    def test_unknown_lane_account_rejected(self):
        bad = Path(self.tmp.name) / "bad.toml"
        bad.write_text('[accounts.a]\nlauncher="claude"\n[lanes]\nx=["a","ghost"]\n')
        with self.assertRaises(ValueError):
            router.load_registry(bad)


class ResetParsingTests(unittest.TestCase):
    REF = datetime(2026, 1, 5, 15, 0, tzinfo=timezone.utc)

    def test_clock_reset_with_zone(self):
        at = router.parse_reset("You've hit your session limit, resets 11pm (America/New_York)", self.REF)
        self.assertEqual(at, datetime(2026, 1, 6, 4, 0, tzinfo=timezone.utc))

    def test_relative_reset(self):
        at = router.parse_reset("Too many requests, try again in 20 minutes", self.REF)
        self.assertEqual(at, self.REF + timedelta(minutes=20))

    def test_no_reset(self):
        self.assertIsNone(router.parse_reset("quota exceeded", self.REF))


class RunTests(RouterTestCase):
    def fake(self, results):
        calls = []

        def executor(cmd, env, stdin, timeout, cwd):
            calls.append((cmd, env.get("CLAUDE_CONFIG_DIR")))
            return results.pop(0)
        return executor, calls

    def test_fails_over_on_limit_and_logs_model(self):
        executor, calls = self.fake([
            ("", "Claude AI usage limit reached. resets 11pm (UTC)", 1),
            ("hello", "", 0),
        ])
        res, rc = router.run("claude", "both", [], "say hello", model="opus", executor=executor,
                             reg=self.reg, signed_in_fn=always_signed_in)
        self.assertEqual(rc, 0)
        self.assertEqual(res["served_by"], "claude-primary")
        self.assertEqual(res["model"], "opus")
        self.assertTrue(calls[0][1].endswith(".claude-secondary"))
        self.assertIsNone(calls[1][1])
        self.assertIsNotNone(router.cooling("claude-secondary"))
        run_rec = [d for d in self.decisions() if d["event"] == "run"][-1]
        self.assertEqual(run_rec["model"], "opus")

    def test_plan_block_rests_account_for_a_week(self):
        executor, _ = self.fake([("", "IneligibleTierError: no longer supported", 1), ("ok", "", 0)])
        res, rc = router.run("research", "both", [], "q", executor=executor, reg=self.reg,
                             signed_in_fn=always_signed_in)
        self.assertEqual(res["served_by"], "cursor")
        until = datetime.fromisoformat(router.cooling("codex")["until"])
        self.assertGreater(until, router.now() + timedelta(days=6))

    def test_output_mentioning_rate_limit_is_not_a_limit(self):
        long_answer = "\n".join(["Rate limiting explained:"] + ["line"] * 10)
        executor, _ = self.fake([(long_answer, "", 0)])
        res, rc = router.run("claude", "both", [], "explain", executor=executor, reg=self.reg,
                             signed_in_fn=always_signed_in)
        self.assertEqual(res["served_by"], "claude-secondary")

    def test_all_limited_returns_75(self):
        executor, _ = self.fake([("", "rate limited", 1)] * 3)
        res, rc = router.run("sends", "both", ["sends"], "x", executor=executor, reg=self.reg,
                             signed_in_fn=always_signed_in)
        self.assertEqual(rc, 75)
        self.assertIsNone(res["served_by"])

    def test_api_keys_are_stripped(self):
        os.environ["ANTHROPIC_API_KEY"] = "placeholder"
        try:
            _, env, _ = router.build_cmd(self.reg["accounts"]["claude-primary"], "p")
        finally:
            os.environ.pop("ANTHROPIC_API_KEY")
        self.assertNotIn("ANTHROPIC_API_KEY", env)


class CliTests(RouterTestCase):
    def test_disable_switch_prints_default(self):
        os.environ["DISCOPARTY_ROUTER_DISABLE"] = "1"
        from io import StringIO
        from contextlib import redirect_stdout
        buf = StringIO()
        with redirect_stdout(buf):
            self.assertEqual(router.main(["claude-chain"]), 0)
        self.assertEqual(buf.getvalue().strip(), "default")

    def test_record_run_logs_model(self):
        router.main(["record-run", "--account", "claude-primary", "--model", "opus", "--job", "nightly"])
        rec = self.decisions()[-1]
        self.assertEqual((rec["served_by"], rec["model"], rec["job"]), ("claude-primary", "opus", "nightly"))


if __name__ == "__main__":
    unittest.main()
