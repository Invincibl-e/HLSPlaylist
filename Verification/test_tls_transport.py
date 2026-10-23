#!/usr/bin/env python3
"""Actual HTTP/2 identity reuse/cleanup; trust authorization is tested separately."""
import hashlib
import http.server
import pathlib
import subprocess
import tempfile
import threading
import unittest
from unittest.mock import patch
import tls_identity
import tls_transport


class TransportTests(unittest.TestCase):
    def test_reuse_preserves_identity_and_never_modifies_macos_trust(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = pathlib.Path(temporary)
            cert, key = tls_identity.prepare(work / "identity")
            original = [hashlib.sha256(p.read_bytes()).hexdigest() for p in [cert, key]]
            self.assertEqual(tls_identity.prepare(work / "identity"), (cert, key))
            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), http.server.BaseHTTPRequestHandler)
            thread = threading.Thread(target=server.serve_forever)
            thread.start()
            try:
                real_run = subprocess.run
                def guard(command, *args, **kwargs):
                    if command[0] == "security":
                        self.fail("Transport attempted to change macOS trust settings")
                    return real_run(command, *args, **kwargs)
                with patch.object(tls_transport, "SCRATCH", work), \
                     patch.object(tls_transport, "identity", return_value=(cert, key)), \
                     patch.object(tls_transport, "require_trust") as trust, \
                     patch.object(tls_transport.subprocess, "run", side_effect=guard):
                    for index in range(2):
                        directory = work / f"run-{index}"
                        with tls_transport.transport(f"http://127.0.0.1:{server.server_port}",
                                                     directory, pathlib.Path("/validator")) as ready:
                            # transport itself performs real curl --http2 --cacert.
                            self.assertEqual(pathlib.Path(ready["certificate"]).read_bytes(), cert.read_bytes())
                            self.assertIn("HTTP/2.0", (directory / "http2.log").read_text())
                        self.assertFalse((directory / "localhost-key.pem").exists())
                    # Device transport still owns a separate ephemeral identity.
                    device_directory = work / "device"
                    with tls_transport.transport(f"http://127.0.0.1:{server.server_port}",
                                                 device_directory, None) as ready:
                        self.assertTrue((device_directory / "localhost-key.pem").exists())
                        self.assertNotEqual(pathlib.Path(ready["certificate"]).read_bytes(), cert.read_bytes())
                    self.assertFalse((device_directory / "localhost-key.pem").exists())
                    self.assertEqual(trust.call_count, 2)
                    self.assertEqual(original, [hashlib.sha256(p.read_bytes()).hexdigest() for p in [cert, key]])
                # Fail before starting a server if pre-provisioned trust is absent.
                with patch.object(tls_transport, "identity", return_value=(cert, key)), \
                     patch.object(tls_transport, "require_trust", side_effect=RuntimeError("not trusted")):
                    with self.assertRaisesRegex(RuntimeError, "not trusted"):
                        with tls_transport.transport("http://127.0.0.1:1", work / "refused", pathlib.Path("/validator")):
                            self.fail("Untrusted identity started a transport")
                    self.assertFalse((work / "refused").exists())
            finally:
                server.shutdown()
                server.server_close()
                thread.join()

    def test_invalid_identity_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = pathlib.Path(temporary)
            with self.assertRaisesRegex(RuntimeError, "missing"):
                tls_identity.identity(work)
            cert, key = tls_identity.prepare(work)
            key.chmod(0o644)
            with self.assertRaisesRegex(RuntimeError, "mode 600"):
                tls_identity.identity(work)
            key.chmod(0o600)
            _, other = tls_identity.prepare(work / "other")
            key.write_bytes(other.read_bytes())
            with self.assertRaisesRegex(RuntimeError, "mismatch"):
                tls_identity.identity(work)


if __name__ == "__main__":
    unittest.main()
