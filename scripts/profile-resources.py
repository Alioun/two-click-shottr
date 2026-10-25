#!/usr/bin/env python3
"""Alternate two prepared release app bundles through the same visible workload."""
import argparse
import json
from pathlib import Path
import statistics
import subprocess
import time


def run(app, report):
    subprocess.run(["open", "-n", "--stdout", str(report), str(app),
                    "--args", "--profile-resources"], check=True)
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        try:
            result = json.loads(report.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            time.sleep(0.1)
            continue
        if not result.get("passed") or result.get("movementEvents") != 240:
            raise RuntimeError(f"Workload failed: {result}")
        return result
    raise TimeoutError(f"No complete resource profile for {app}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--runs", type=int, default=5)
    args = parser.parse_args()
    if args.runs < 1:
        parser.error("--runs must be positive")
    args.output.mkdir(parents=True, exist_ok=True)
    results = {"baseline": [], "candidate": []}
    for index in range(args.runs):
        for side in results:
            report = (args.output / f"{side}-{index + 1}.json").resolve()
            if report.exists():
                raise FileExistsError(f"Preserving existing measurement {report}")
            results[side].append(run(getattr(args, side).resolve(), report))
            print(f"{side} run {index + 1} passed", flush=True)
    summary = {"runsPerSide": args.runs, "errors": 0, "metrics": {}}
    for side, runs in results.items():
        summary["metrics"][side] = {}
        for phase in ("idle", "stationarySelection", "movingSelection"):
            metrics = summary["metrics"][side][phase] = {}
            for name in ("cpuSeconds", "elapsedSeconds", "peakResidentBytes", "voluntaryContextSwitches"):
                values = [run[phase][name] for run in runs]
                metrics[name] = {"median": statistics.median(values), "min": min(values), "max": max(values)}
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
