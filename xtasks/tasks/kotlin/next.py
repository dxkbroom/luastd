#!/usr/bin/env -S uv run --project xtasks python
# MISE description="Select actionable Kotlin coroutine tests for the next porting pass"
# USAGE flag "--class <name>" help="Limit suggestions to one Kotlin test class"
# USAGE flag "--limit <count>" default="5" help="Maximum tests to suggest"
# USAGE flag "--json" help="Write machine-readable porting context"
"""Select a small, actionable batch of Kotlin coroutine tests to port."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ROOT = Path(os.environ.get("MISE_PROJECT_ROOT") or Path(__file__).resolve().parents[3])
sys.path.insert(0, str(ROOT / "xtasks/lib"))

from kotlin_coverage import KOTLIN_TEST_TAG, build_report

PORTS = ROOT / "crates/luastd_runtime/tests/lua/kotlinx"
KOTLINX = Path(os.environ.get("KOTLINX_DIR") or ROOT.parent / "kotlinx.coroutines")


def main() -> int:
    try:
        limit = int(os.environ.get("usage_limit", "5"))
    except ValueError:
        print("--limit must be an integer", file=sys.stderr)
        return 2
    if limit < 1:
        print("--limit must be greater than zero", file=sys.stderr)
        return 2

    class_name = os.environ.get("usage_class")
    report = build_report(
        sorted(PORTS.glob("*.lua")), ROOT, KOTLINX, inventory_tag=KOTLIN_TEST_TAG
    )
    candidates = []
    for cls in report["classes"]:
        if class_name and cls["name"] != class_name:
            continue
        for test in cls["tests"]:
            status = test["status"]
            if status not in ("todo", "missing"):
                continue
            candidates.append(
                {
                    "class": cls["name"],
                    "test": test["name"],
                    "status": status,
                    "kotlin_source": cls["kotlin_source"],
                    "tag": cls["tag"],
                    "kotlin_line": test.get("kotlin_line"),
                    "lua_port": cls["lua_port"],
                    "lua_line": test.get("lua_line"),
                    "trace": test.get("trace", {"status": "unavailable"}),
                }
            )

    candidates.sort(
        key=lambda item: (
            0 if item["status"] == "todo" else 1,
            item["class"],
            item["kotlin_line"] or 0,
        )
    )
    selected = candidates[:limit]
    if class_name and not any(cls["name"] == class_name for cls in report["classes"]):
        print(f"Kotlin test class not found: {class_name}", file=sys.stderr)
        return 1

    if os.environ.get("usage_json") == "true":
        print(json.dumps({"candidates": selected}, ensure_ascii=False, indent=2))
    else:
        for item in selected:
            print(
                f"{item['class']}.{item['test']} [{item['status']}]\n"
                f"  Kotlin: {item['kotlin_source']}:{item['kotlin_line']}\n"
                f"  Lua: {item['lua_port'] or '(generate port)'}:{item['lua_line'] or '-'}"
            )
        if not selected:
            print("No actionable Kotlin tests found.")
        else:
            print(f"Selected {len(selected)} of {len(candidates)} actionable tests.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
