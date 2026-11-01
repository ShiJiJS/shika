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


def byte_count(value):
    match = re.fullmatch(r"(\d+(?:\.\d+)?)\s*(B|kB|KB|MB|GB|TB|KiB|MiB|GiB|TiB)", value.strip())
    if not match:
        raise ValueError("Unknown Docker byte unit: " + value)
    number, unit = match.groups()
    power = {
        "B": 0,
        "kB": 1,
        "KB": 1,
        "MB": 2,
        "GB": 3,
        "TB": 4,
        "KiB": 1,
        "MiB": 2,
        "GiB": 3,
        "TiB": 4,
    }[unit]
    return float(number) * (1024 if "i" in unit else 1000) ** power


def environment_summary(folder):
    source = json.loads((folder / "source.json").read_text())
    with gzip.open(folder / "environment-samples.jsonl.gz", "rt") as stream:
        rows = [json.loads(line) for line in stream]
    if not rows:
        raise ValueError("No environment observations")
    identity = source.get("runtime_id", rows[0]["runtime_id"])
    qemu_pid = source["qemu"].split()[0]
    for row in rows:
        if (
            row["runtime_id"] != identity
            or not row["server"]["ID"]
            or not identity.startswith(row["server"]["ID"])
            or row["qemu"].split()[0] != qemu_pid
        ):
            raise ValueError("Environment observation identity changed")
    result = {
        "sample_count": len(rows),
        "runtime_id": identity,
        "source_runtime_id_recorded": "runtime_id" in source,
        "qemu_pid": qemu_pid,
        "scope": "Build/startup through terminal report; owned local runtime and host simulator, not NAS/phone",
        "server_max_cpu_percent": max(
            float(r["server"]["CPUPerc"].removesuffix("%")) for r in rows
        ),
        "server_max_docker_memory_mib": max(
            byte_count(r["server"]["MemUsage"].split("/")[0]) for r in rows
        )
        / 1024**2,
        "qemu_max_host_rss_mib": max(float(r["qemu"].split()[1]) for r in rows) / 1024,
        "qemu_max_reported_cpu_percent": max(float(r["qemu"].split()[2]) for r in rows),
        "counter_definition": "Docker CLI rounded cumulative traffic/block counters; approximate sampled delta, not physical NAS IO",
    }
    for field, names in [
        ("NetIO", ["network_received", "network_sent"]),
        ("BlockIO", ["block_read", "block_written"]),
    ]:
        values = [[byte_count(part) for part in r["server"][field].split("/")] for r in rows]
        if any(len(value) != 2 for value in values):
            raise ValueError("Expected two Docker counters")
        for index, name in enumerate(names):
            counters = [value[index] for value in values]
            if any(b < a for a, b in zip(counters, counters[1:])):
                raise ValueError("Docker counter reset during observation: " + name)
            result[name] = {
                "initial_bytes": counters[0],
                "final_bytes": counters[-1],
                "sampled_delta_bytes": counters[-1] - counters[0],
            }
    return result


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
    environment = environment_summary(folder)
    if not environment["source_runtime_id_recorded"] or len(memory["pids"]) != 1:
        raise ValueError("Final measurement requires one App PID and recorded runtime identity")
    return {
        "run": str(folder),
        "source": json.loads((folder / "source.json").read_text())["source"],
        "latency_ms": latency,
        "memory": memory,
        "environment": environment,
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
