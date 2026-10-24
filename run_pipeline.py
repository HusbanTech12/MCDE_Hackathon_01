"""Rebuild the warehouse from the raw exports in one command.

    python run_pipeline.py

Steps, in order: raw load, staging, warehouse and ERD, the ten question
CSVs, then the data-quality checks. Set DATABASE_URL or DATA_DIR to
override the defaults used by each step.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent

STEPS = (
    ROOT / "ingestion" / "load_raw.py",
    ROOT / "transform" / "build_staging.py",
    ROOT / "warehouse" / "build_warehouse.py",
    ROOT / "analytics" / "run_questions.py",
    ROOT / "quality" / "run_checks.py",
)


def main() -> int:
    for script in STEPS:
        print(f"\n=== {script.relative_to(ROOT)} ===", flush=True)
        completed = subprocess.run([sys.executable, str(script)], cwd=ROOT)
        if completed.returncode != 0:
            print(f"\nStopped at {script.name}.", file=sys.stderr)
            return completed.returncode
    print("\nPipeline finished.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
