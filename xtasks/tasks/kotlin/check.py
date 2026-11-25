#!/usr/bin/env -S uv run --project xtasks python
# MISE description="Report which kotlinx.coroutines tests the Kotlin ports cover (ported/adapted/deprecated/not-applicable/defer/todo/missing)"
# USAGE flag "--check" help="Exit 1 if a Kotlin test is missing from its port or a port names a test Kotlin does not have"
# USAGE flag "--deprecated" help="Include deprecated Kotlin tests (hidden by default)"
# USAGE flag "--class <name>" help="Check one Kotlin test class"
# USAGE arg "[FILES]..." help="Port files (default: crates/luastd_runtime/tests/lua/kotlinx/*.lua)"
"""Report coverage of the kotlinx.coroutines test ports."""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(os.environ.get("MISE_PROJECT_ROOT") or Path(__file__).resolve().parents[3])
sys.path.insert(0, str(ROOT / "xtasks/lib"))

from kotlin_coverage import (
    KOTLIN_TEST_TAG,
    inherited_test_methods,
    kotlin_class_test_methods,
    kotlin_source,
    kotlin_test_sources,
    parse_port,
    relative,
)
from kotlin_syntax import KotlinSources
from lua_syntax import LuaSources

PORTS = ROOT / "crates/luastd_runtime/tests/lua/kotlinx"
KOTLINX = Path(os.environ.get("KOTLINX_DIR") or ROOT.parent / "kotlinx.coroutines")


def main(argv: list[str]) -> int:
    check = os.environ.get("usage_check") == "true" or "--check" in argv
    include_deprecated = (
        os.environ.get("usage_deprecated") == "true" or "--deprecated" in argv
    )
    display_statuses = ["ported", "adapted"]
    if include_deprecated:
        display_statuses.append("deprecated")
    display_statuses.extend(["not-applicable", "defer", "todo", "missing"])
    class_name = os.environ.get("usage_class")
    files = [Path(file) for file in os.environ.get("usage_files", "").split() if file]
    if not files:
        env_files = os.environ.get("usage_files", "").split()
        files = [Path(file) for file in env_files] or sorted(PORTS.glob("*.lua"))

    lua_sources = LuaSources()
    kotlin_sources = KotlinSources()
    inventory, _ = kotlin_test_sources(KOTLINX, KOTLIN_TEST_TAG)
    abstract_methods = inherited_test_methods(inventory, kotlin_sources)
    problems = 0
    found_class = False
    totals: dict[str, int] = {}
    for file in files:
        ports, _ = parse_port(file, lua_sources)
        for port in ports:
            if class_name and port.cls != class_name:
                continue
            found_class = True
            source = kotlin_source(port.path, port.tag, KOTLINX)
            rel = relative(file, ROOT)
            print(f"{port.cls}  ({port.path}@{port.tag} -> {rel})")
            if source is None:
                print(f"  ! Kotlin source not found under {KOTLINX} (set KOTLINX_DIR)")
                problems += 1
                continue
            if not re.search(rf"\bclass\s+{re.escape(port.cls)}\b", source):
                print(f"  ! no class {port.cls} in {port.path}")
                problems += 1
            kotlin_tests = kotlin_class_test_methods(
                source, port.cls, abstract_methods, kotlin_sources
            )
            mapped = {test.name: (test.status, test.reason) for test in port.tests}
            visible_tests = [
                name
                for name in kotlin_tests
                if include_deprecated
                or mapped.get(name, ("missing",))[0] != "deprecated"
            ]
            for name in visible_tests:
                status, reason = mapped.get(name, ("missing", ""))
                totals[status] = totals.get(status, 0) + 1
                problems += status == "missing"
                print(f"  {status:<8} {name}" + (f"  - {reason}" if reason else ""))
            for test in port.tests:
                if test.name not in kotlin_tests:
                    print(f"  ! {test.name} is not a @Test in {port.cls}")
                    problems += 1
            counts = {
                status: sum(
                    1
                    for name in visible_tests
                    if mapped.get(name, ("missing",))[0] == status
                )
                for status in display_statuses
            }
            print(
                "  "
                + ", ".join(f"{count} {status}" for status, count in counts.items())
                + f" of {len(visible_tests)}"
            )
    if totals:
        print(
            "total: "
            + ", ".join(
                f"{totals.get(status, 0)} {status}" for status in display_statuses
            )
        )
    if class_name and not found_class:
        print(f"class not found in selected port files: {class_name}", file=sys.stderr)
        problems += 1
    return 1 if check and problems else (1 if class_name and not found_class else 0)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
