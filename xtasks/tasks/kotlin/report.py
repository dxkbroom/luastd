#!/usr/bin/env -S uv run --project xtasks python
# MISE description="Render a structured report of kotlinx.coroutines test ports"
# USAGE flag "--json" help="Write the report as JSON"
# USAGE flag "--markdown" help="Write the report as nested Markdown"
# USAGE flag "--check" help="Exit 1 if the report contains coverage gaps or invalid port metadata"
# USAGE group "output" "--json" "--markdown"
# USAGE flag "--ported" help="Include ported tests; if no status flag is set, show all statuses"
# USAGE flag "--adapted" help="Include adapted tests"
# USAGE flag "--deprecated" help="Include deprecated Kotlin tests (hidden by default)"
# USAGE flag "--not-applicable" help="Include not-applicable tests"
# USAGE flag "--defer" help="Include tests deferred because the current API cannot support them"
# USAGE flag "--todo" help="Include unported tests that can be worked on with the current API"
# USAGE flag "--missing" help="Include Kotlin tests not listed in a Lua port"
# USAGE flag "--class <name>" help="Show one Kotlin test class"
"""Render current Kotlin coroutine port coverage as a tree, Markdown, or JSON."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ROOT = Path(os.environ.get("MISE_PROJECT_ROOT") or Path(__file__).resolve().parents[3])
sys.path.insert(0, str(ROOT / "xtasks/lib"))

from kotlin_coverage import (
    KOTLIN_TEST_TAG,
    build_report,
    filter_report,
    has_gaps,
    markdown_report,
)

PORTS = ROOT / "crates/luastd_runtime/tests/lua/kotlinx"
KOTLINX = Path(os.environ.get("KOTLINX_DIR") or ROOT.parent / "kotlinx.coroutines")
STATUS_SYMBOL = {
    "ported": "✓",
    "adapted": "~",
    "deprecated": "†",
    "not-applicable": "○",
    "defer": "↷",
    "todo": "·",
    "missing": "✗",
}
STATUSES = (
    "ported",
    "adapted",
    "deprecated",
    "not-applicable",
    "defer",
    "todo",
    "missing",
)


def counts_label(counts: dict[str, int], *, compact: bool = False) -> str:
    labels = []
    for key, status in (
        ("ported", "ported"),
        ("adapted", "adapted"),
        ("deprecated", "deprecated"),
        ("not_applicable", "not-applicable"),
        ("defer", "defer"),
        ("todo", "todo"),
        ("missing", "missing"),
    ):
        count = counts[key]
        if count or not compact:
            labels.append(f"{count} {status}")
    return " · ".join(labels)


def terminal_tree(report: dict[str, object]):
    from rich.text import Text
    from rich.tree import Tree

    summary = report["summary"]
    root = Tree(
        Text(
            f"Kotlin coroutine test ports  [{summary['classes']} classes · "
            f"{summary['unported_classes']} unported · {counts_label(summary)}]",
            style="bold",
        )
    )
    for cls in report["classes"]:
        class_status = "unported · " if cls["port_status"] == "unported" else ""
        style = "yellow" if cls["port_status"] == "unported" else "cyan"
        branch = root.add(
            Text(
                f"{cls['name']}  [{class_status}{counts_label(cls['counts'], compact=True)}]",
                style=style,
            )
        )
        for test in cls["tests"]:
            label = f"{STATUS_SYMBOL[test['status']]} {test['name']}  {test['status']}"
            if test["reason"]:
                label += f" — {test['reason']}"
            label += f"  · trace {test['trace']['status']}"
            branch.add(Text(label))
        for stale in cls["stale_tests"]:
            branch.add(
                Text(
                    f"✗ {stale['name']}  stale (Lua line {stale['line']})", style="red"
                )
            )
    if not report["classes"]:
        root.add(Text("No Kotlin test ports found", style="yellow"))
    if report["issues"]:
        issues = root.add(Text(f"Issues  [{len(report['issues'])}]", style="red"))
        for issue in report["issues"]:
            location = ":".join(
                part
                for part in (issue.get("file"), issue.get("class"), issue.get("test"))
                if part
            )
            prefix = f"{location}: " if location else ""
            issues.add(Text(f"{issue['code']}: {prefix}{issue['message']}"))
    return root


def main() -> int:
    files = sorted(PORTS.glob("*.lua"))
    full_report = build_report(files, ROOT, KOTLINX, inventory_tag=KOTLIN_TEST_TAG)
    selected = {
        status
        for status in STATUSES
        if os.environ.get(f"usage_{status.replace('-', '_')}") == "true"
    }
    class_name = os.environ.get("usage_class")
    report = filter_report(full_report, selected or None, class_name)

    if os.environ.get("usage_json") == "true":
        print(json.dumps(report, ensure_ascii=False, indent=2))
    elif os.environ.get("usage_markdown") == "true":
        print(markdown_report(report), end="")
    else:
        from rich.console import Console

        Console(highlight=False).print(terminal_tree(report))

    return 1 if os.environ.get("usage_check") == "true" and has_gaps(full_report) else 0


if __name__ == "__main__":
    raise SystemExit(main())
