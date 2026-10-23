#!/usr/bin/env python3
"""Failure-injection tests: the harness must not turn broken runs green."""
import subprocess
import os
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch
import run
from device_checks import verify
from suite import run_step
import tls_identity
import uri_oracles

class RunnerTests(unittest.TestCase):
    def check_output(self, stdout="", returncode=0):
        return patch.object(run.subprocess, "run", return_value=subprocess.CompletedProcess([], returncode, stdout, "crash"))

    def test_crash_is_not_parse_rejection(self):
        with self.check_output(returncode=-11), self.assertRaises(RuntimeError):
            run.probe([{"name": "a", "text": "#EXTM3U"}])

    def test_missing_output_is_failure(self):
        with self.check_output(), self.assertRaises(RuntimeError):
            run.probe([{"name": "a", "text": "#EXTM3U"}])

    def test_extra_output_is_failure(self):
        with self.check_output('{"name":"a","status":"accepted"}\n' * 2), self.assertRaises(RuntimeError):
            run.probe([{"name": "a", "text": "#EXTM3U"}])

    def test_wrong_identity_is_failure(self):
        with self.check_output('{"name":"b","status":"accepted"}\n'), self.assertRaises(RuntimeError):
            run.probe([{"name": "a", "text": "#EXTM3U"}])

    def test_invalid_status_is_failure(self):
        with self.check_output('{"name":"a","status":"timeout"}\n'), self.assertRaises(RuntimeError):
            run.probe([{"name": "a", "text": "#EXTM3U"}])

    def test_failed_expectation_is_failure(self):
        with self.assertRaises(RuntimeError):
            run.require_results([{"met": False}], "injected")

    def test_expected_rejection_is_valid_response(self):
        with self.check_output('{"name":"a","status":"rejected"}\n'):
            self.assertEqual(run.probe([{"name": "a", "text": "#EXTM3U"}])[0]["status"], "rejected")

    def test_uri_oracle_requires_gold_for_each_public_api(self):
        expected = [{"input": {"name": "a"}, "expected": ["https://a/g"]}]
        valid = {"name": "a", "status": "accepted",
                 **{key: ["https://a/g"] for key in ["resolvedURIs", "segmentURLs", "playlistURIs"]}}
        self.assertEqual(uri_oracles.verify(expected, [valid])["failures"], [])
        for key in valid:
            with self.subTest(key=key):
                missing = {k: v for k, v in valid.items() if k != key}
                self.assertTrue(uri_oracles.verify(expected, [missing])["failures"])
        for key in ["resolvedURIs", "segmentURLs", "playlistURIs"]:
            self.assertTrue(uri_oracles.verify(expected, [{**valid, key: ["https://a/wrong"]}])["failures"])
        for output in [[], [valid, valid]]:
            with self.assertRaises(RuntimeError):
                uri_oracles.verify(expected, output)
        with self.assertRaises(RuntimeError):
            uri_oracles.verify([], [])

    def test_device_empty_incomplete_simulated_or_missing_cases_fail(self):
        base = {"simulator": False, "complete": True, "plannedCases": ["aes/original"],
                "results": [{"kind": "aes", "candidate": "original"}]}
        for report, expected in [
            ({**base, "plannedCases": [], "results": []}, []),
            ({**base, "complete": False}, ["aes/original"]),
            ({**base, "simulator": True}, ["aes/original"]),
            ({**base, "results": []}, ["aes/original"]),
            (base, ["aes/rewrite"])
        ]:
            with self.subTest(report=report), self.assertRaises(AssertionError):
                verify(report, expected)

    def test_first_frame_without_progress_is_not_playback(self):
        row = {"kind": "local-ll", "candidate": "original", "firstFrame": True,
               "progress10s": False, "pause": True, "resume": True}
        report = {"simulator": False, "complete": True, "plannedCases": ["local-ll/original"], "results": [row]}
        self.assertFalse(verify(report, ["local-ll/original"])[0]["met"])
        row["progress10s"] = True
        row["errorLogs"] = [{"status": -15410, "comment": "Server must support http2 ECN and SACK"}]
        self.assertFalse(verify(report, ["local-ll/original"])[0]["met"])

    def test_network_failure_is_not_expected_strict_rejection(self):
        row = {"kind": "ts", "candidate": "rewrite", "firstFrame": False}
        report = {"simulator": False, "complete": True, "plannedCases": ["ts/rewrite"], "results": [row]}
        origins = {"ts": "https://fixture.test/ts/master.m3u8"}
        self.assertFalse(verify(report, ["ts/rewrite"], origins=origins)[0]["met"])
        rejection = {"source": "https://fixture.test/ts/video.m3u8", "candidate": "rewrite",
                     "status": 422, "error": "Control character"}
        self.assertTrue(verify(report, ["ts/rewrite"], [rejection], origins)[0]["met"])

    def test_timeout_allows_child_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = pathlib.Path(directory) / "cleaned"
            script = ("import pathlib, time\ntry:\n time.sleep(30)\n"
                      f"finally:\n pathlib.Path({str(marker)!r}).write_text('cleaned')\n")
            with open(os.devnull, "w") as log, self.assertRaises(subprocess.TimeoutExpired):
                run_step([sys.executable, "-c", script], os.environ, log, 1)
            self.assertEqual(marker.read_text(), "cleaned")

    def test_missing_trust_fails_without_modifying_trust(self):
        with patch.object(tls_identity.subprocess, "run",
                          return_value=subprocess.CompletedProcess([], 1)) as called:
            with self.assertRaisesRegex(RuntimeError, "one-time setup"):
                tls_identity.require_trust(pathlib.Path("/lab/localhost.pem"))
            self.assertEqual(called.call_count, 1)
            self.assertEqual(called.call_args.args[0][:2], ["security", "verify-cert"])

    def test_reinstall_trusted_identity_is_read_only(self):
        with patch.object(sys, "argv", ["tls_identity.py", "install"]), \
             patch.object(tls_identity, "identity", return_value=(pathlib.Path(__file__), None)), \
             patch.object(tls_identity, "require_trust") as check, \
             patch.object(tls_identity.subprocess, "run") as command, \
             patch("builtins.print"):
            tls_identity.main()
            self.assertEqual(check.call_count, 2)
            command.assert_not_called()

if __name__ == "__main__":
    unittest.main()
