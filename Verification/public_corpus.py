#!/usr/bin/env python3
"""Offline, byte-pinned public manifests with explicit acceptance contracts."""
import hashlib
import json
from run import CORPUS, RESULTS, probe, write


def cases():
    directory = CORPUS / "public"
    manifest = json.loads((directory / "manifest.json").read_text())
    if not manifest["inputs"]:
        raise RuntimeError("Empty public corpus")
    rows = []
    for source in manifest["inputs"]:
        body = (directory / source["name"]).read_bytes()
        if hashlib.sha256(body).hexdigest() != source["sha256"]:
            raise RuntimeError("Public corpus hash mismatch: " + source["name"])
        rows.append({**source, "text": body.decode("utf-8"), "url": source["effectiveURL"], "rewrite": True})
    return rows


def verify(inputs, outputs):
    if not inputs or len(inputs) != len(outputs) or [r["name"] for r in inputs] != [r["name"] for r in outputs]:
        raise RuntimeError("Public corpus result identity/count mismatch")
    failures = []
    for source, out in zip(inputs, outputs):
        if source["accepted"]:
            met = (out["status"] == "accepted" and out.get("idempotent") is True
                   and out.get("rewriteIdempotent") is True and out.get("rewritePreserved") is True)
        else:
            met = (out["status"] == "rejected" and out.get("parseAccepted") is not True
                   and source["reason"] in out.get("error", ""))
        if not met:
            failures.append({"name": source["name"], "expectation": source["reason"], "output": out})
    return failures


if __name__ == "__main__":
    inputs = cases()
    outputs = probe(inputs, timeout=180)
    failures = verify(inputs, outputs)
    write(RESULTS / "public-corpus-output.json", outputs)
    write(RESULTS / "public-corpus.json", {"cases": len(inputs),
          "providers": sorted({row["provider"] for row in inputs}),
          "uniqueBodies": len({row["sha256"] for row in inputs}),
          "expectedAccepted": sum(row["accepted"] for row in inputs),
          "failures": failures})
    print("Public manifests:", len(inputs), "failures:", len(failures), flush=True)
    if failures:
        raise SystemExit(1)
