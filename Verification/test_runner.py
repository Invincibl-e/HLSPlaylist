#!/usr/bin/env python3
"""Failure-injection tests: the harness must not turn broken runs green."""
import subprocess
import unittest
from unittest.mock import patch
import run

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

if __name__ == "__main__":
    unittest.main()
