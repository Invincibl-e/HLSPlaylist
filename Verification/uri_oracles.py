#!/usr/bin/env python3
"""Independent fixed RFC vectors and construction-based URI expectations."""
import json
import random
from run import CORPUS, RESULTS, probe, write

TEXT = "#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\ns\n#EXT-X-ENDLIST\n"

def cases():
    fixed = json.loads((CORPUS / "uri-oracles.json").read_text())
    rows = [{"input": {"name": f"uri-fixed-{i}", "text": TEXT, "url": row["base"],
                       "uriReferences": [row["reference"]]},
             "expected": [row["expected"]], "source": row["source"]}
            for i, row in enumerate(fixed)]
    rng = random.Random(3986)
    # Expectations are assembled from the known destination, never urljoin or
    # the library. Inserting cancellable path pairs must retain exact bytes.
    atoms = ["a", "b;p", "%2e", "%2E%2e", "%2F", "a%20b", "a+b", "x%25y", "~z", ".g", "g.."]
    for i in range(2000):
        prefix = "/".join([rng.choice(atoms)] + rng.choices(atoms + [""], k=rng.randrange(0, 12)))
        leaf = rng.choice(atoms)
        query = "?sig=a%2Fb+z%3D&x=&x=2#f/../g" if i % 2 else "?#"
        expected = "https://fixture.test/" + prefix + "/" + leaf + query
        path = prefix + "/./cancel/../" + leaf + query
        reference = ["/", "../", "//fixture.test/", "https://fixture.test/"][i % 4] + path
        rows.append({"input": {"name": f"uri-property-{i}", "text": TEXT,
                              "url": "https://fixture.test/base/master?old#discard",
                              "uriReferences": [reference]},
                     "expected": [expected], "source": "RFC3986 §5.2.4; seed 3986, cancellable path construction"})
    for depth in [1, 16, 128, 1024]:
        rows.append({"input": {"name": f"uri-depth-{depth}", "text": TEXT,
                              "url": "https://fixture.test/b/c",
                              "uriReferences": ["/" + "x/../" * depth + "g"]},
                     "expected": ["https://fixture.test/g"], "source": "RFC3986 §5.2.4"})
    return rows

def verify(expected, output):
    if not expected or len(expected) != len(output):
        raise RuntimeError("URI oracle output count mismatch or empty corpus")
    failures = []
    for case, row in zip(expected, output):
        checks = {"identity": row.get("name") == case["input"]["name"],
                  "accepted": row.get("status") == "accepted"}
        checks.update({key: row.get(key) == case["expected"]
                       for key in ["resolvedURIs", "segmentURLs", "playlistURIs"]})
        if not all(checks.values()):
            failures.append({"case": case, "checks": checks, "output": row})
    return {"cases": len(expected), "checksPerCase": 5, "failures": failures,
            "seed": 3986, "fixed": len(json.loads((CORPUS / "uri-oracles.json").read_text()))}

def require(expected, output, label):
    summary = verify(expected, output)
    write(RESULTS / f"{label}-uri-summary.json", summary)
    if summary["failures"]:
        raise RuntimeError(f"{label}: URI golden expectations failed ({len(summary['failures'])})")
    print(f"{label}: {summary['cases']} URI oracle cases passed", flush=True)
    return summary

if __name__ == "__main__":
    expected = cases()
    output = probe([row["input"] for row in expected], timeout=120)
    write(RESULTS / "uri-oracles.json", [{"input": row["input"], "expected": row["expected"],
                                        "source": row["source"], "output": result}
                                       for row, result in zip(expected, output)])
    require(expected, output, "mac")
