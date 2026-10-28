#!/usr/bin/env python3
"""Read-only summary of complete reader profile runs; never drop outliers."""

import argparse
import gzip
import json
import math
import re
from pathlib import Path


def percentile(values, q):
    values = sorted(values)
    if not values:
        raise ValueError("Empty sample set")
    return values[max(0, math.ceil(len(values) * q) - 1)]


def stats(values, divisor=1):
    return {
        "n": len(values),
        "p50": percentile(values, 0.5) / divisor,
        "p95": percentile(values, 0.95) / divisor,
        "max": max(values) / divisor,
        "method": "nearest-rank; no filtering",
    }


def summarize(folder):
    completed = json.loads((folder / "result.json").read_text())
    if (
        completed["exit_code"]
        or not completed["checks_passed"]
        or completed["observer_errors"]
        or completed.get("final_matrix") is not True
    ):
        raise ValueError("Incomplete or observer-failed run: " + str(folder))
    raw = json.loads((folder / "profile-result.json").read_text())["reader_benchmark"]
    if not raw["completed"] or raw["reached"] != list(range(500)) or raw["mode"] != "profile":
        raise ValueError("Missing full 500-page profile result")
    latency = {}
    for phase in ["4k-open", "4k-adjacent", "8k-open", "8k-adjacent"]:
        rows = [r for r in raw["samples"] if r["phase"] == phase]
        if sorted(r["trial"] for r in rows) != list(range(30)):
            raise ValueError("Expected all thirty trials: " + phase)
        latency[phase] = stats([r["latency_us"] for r in rows], divisor=1000)
    with gzip.open(folder / "memory-samples.jsonl.gz", "rt") as stream:
        samples = [json.loads(line) for line in stream]
    memory = {
        "sample_count": len(samples),
        "pids": sorted({r["pid"] for r in samples}),
        "definition": "kernel smaps_rollup; excludes added memtrack estimates",
        "maximum_query_seconds": max(r["sample_seconds"] for r in samples),
    }
    for name, key in [
        ("sampled_pss", "Pss"),
        ("sampled_rss", "Rss"),
        ("kernel_rss_high_water", "VmHWM"),
    ]:
        values = [
            int(re.search(r"^" + key + r":\s+(\d+)\s+kB", s["raw"], re.M).group(1)) for s in samples
        ]
        memory[name + "_mib"] = max(values) / 1024
    return {
        "run": str(folder),
        "source": json.loads((folder / "source.json").read_text())["source"],
        "latency_ms": latency,
        "memory": memory,
        "peaks": raw["peaks"],
        "frames_us": {
            name: stats([r[index] for r in raw["frame_timings_us"]])
            for index, name in enumerate(["build", "raster", "total"])
        },
        "long_pages": len(raw["reached"]),
        "gestures": raw["gestures"],
        "long_scroll_seconds": raw["scroll_us"] / 1e6,
    }


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("runs", type=Path, nargs="+")
    args = p.parse_args()
    print(json.dumps([summarize(folder) for folder in args.runs], indent=2))
