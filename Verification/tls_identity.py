#!/usr/bin/env python3
"""Explicit one-time localhost identity setup; ordinary tests only read it."""
import argparse
import hashlib
import json
import os
import pathlib
import subprocess


def identity_directory():
    return pathlib.Path(os.environ.get("HLS_TLS_IDENTITY") or
                        pathlib.Path.home() / ".local/share/hlsplaylist-verification/tls").expanduser().resolve()


def identity(directory=None):
    directory = directory or identity_directory()
    cert, key = directory / "localhost.pem", directory / "localhost-key.pem"
    if not cert.is_file() or not key.is_file():
        raise RuntimeError("Localhost identity missing. Run python3 Verification/tls_identity.py prepare, "
                           "then explicitly install it once; see Verification/TESTING.md")
    if key.stat().st_mode & 0o077:
        raise RuntimeError("Localhost private key must have mode 600")
    subprocess.run(["openssl", "x509", "-in", str(cert), "-checkend", "86400", "-noout"],
                   check=True, capture_output=True, timeout=10)
    public_cert = subprocess.check_output(["openssl", "x509", "-in", str(cert), "-pubkey", "-noout"], timeout=10)
    public_key = subprocess.check_output(["openssl", "pkey", "-in", str(key), "-pubout"], timeout=10)
    if public_cert != public_key:
        raise RuntimeError("Localhost certificate/private key mismatch")
    return cert, key


def require_trust(cert):
    result = subprocess.run(["security", "verify-cert", "-L", "-q", "-c", str(cert),
                             "-p", "ssl", "-n", "localhost"], capture_output=True, timeout=15)
    if result.returncode:
        raise RuntimeError("Localhost identity is not trusted. Explicit one-time setup: "
                           "python3 Verification/tls_identity.py install. "
                           "Tests never change macOS trust settings automatically.")


def prepare(directory):
    cert, key = directory / "localhost.pem", directory / "localhost-key.pem"
    if cert.exists() or key.exists():
        return identity(directory)  # Never overwrite or silently rotate an identity.
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        subprocess.run(["openssl", "req", "-x509", "-newkey", "ec",
                        "-pkeyopt", "ec_paramgen_curve:P-256", "-nodes", "-days", "365",
                        "-subj", "/CN=HLSPlaylist lab localhost",
                        "-addext", "basicConstraints=critical,CA:TRUE",
                        "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:::1",
                        "-addext", "extendedKeyUsage=serverAuth",
                        "-addext", "keyUsage=digitalSignature,keyCertSign",
                        "-keyout", str(key), "-out", str(cert)],
                       check=True, capture_output=True, timeout=15)
        key.chmod(0o600)
        return identity(directory)
    except BaseException:
        cert.unlink(missing_ok=True)
        key.unlink(missing_ok=True)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["prepare", "check", "install", "remove"])
    args = parser.parse_args()
    if args.action == "remove":
        cert = identity_directory() / "localhost.pem"
        if not cert.is_file():
            raise RuntimeError("Certificate to remove is missing")
    else:
        cert, _ = prepare(identity_directory()) if args.action == "prepare" else identity()
    if args.action == "install":
        try:
            require_trust(cert)
        except RuntimeError:
            # Deliberately opt-in. This is the only normal setup action that
            # invokes macOS authorization; keep it out of suite/CI execution.
            keychain = subprocess.check_output(["security", "default-keychain", "-d", "user"],
                                              text=True, timeout=10).strip().strip('"')
            subprocess.run(["security", "add-trusted-cert", "-r", "trustRoot", "-p", "ssl",
                            "-s", "localhost", "-k", keychain, str(cert)], check=True, timeout=60)
    if args.action in ["check", "install"]:
        require_trust(cert)
    if args.action == "remove":
        subprocess.run(["security", "remove-trusted-cert", str(cert)], check=True, timeout=60)
        der = subprocess.check_output(["openssl", "x509", "-in", str(cert), "-outform", "DER"], timeout=10)
        subprocess.run(["security", "delete-certificate", "-Z", hashlib.sha1(der).hexdigest()],
                       check=True, timeout=30)
        # Keep files for inspection. Rotation/deletion is an explicit lab operation.
    print(json.dumps({"action": args.action, "certificate": str(cert),
                      "certificateSHA256": hashlib.sha256(cert.read_bytes()).hexdigest()}))


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error))
