#!/usr/bin/env -S uv run --project xtasks python
# MISE description="Generate pending Lua spec ports for unported Kotlin test classes"
# USAGE flag "--dry-run" help="List stubs that would be generated without writing files"
# USAGE flag "--class <name>" help="Generate a stub for one Kotlin test class"
"""Generate a pending Lua spec and register it for each unported Kotlin test class."""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(os.environ.get("MISE_PROJECT_ROOT") or Path(__file__).resolve().parents[3])
sys.path.insert(0, str(ROOT / "xtasks/lib"))

from kotlin_coverage import KOTLIN_TEST_TAG, build_report, render_kotlin_stub

PORTS = ROOT / "crates/luastd_runtime/tests/lua/kotlinx"
KOTLINX = Path(os.environ.get("KOTLINX_DIR") or ROOT.parent / "kotlinx.coroutines")
TESTS_RS = ROOT / "crates/luastd_runtime/tests/kotlinx.rs"
CLASS_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")
MACRO = re.compile(r"(?s)(kotlinx!\s*\{\n)(.*?)(\n\})")


def register_classes(source: str, classes: set[str]) -> str:
    """Add generated specs to the compile-time include_str! test registry."""
    match = MACRO.search(source)
    if match is None:
        raise ValueError(f"could not find kotlinx! registry in {TESTS_RS}")
    current = set(
        re.findall(
            r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*$", match.group(2), re.MULTILINE
        )
    )
    names = sorted(current | classes)
    body = "".join(f"    {name},\n" for name in names).rstrip("\n")
    return (
        source[: match.start()]
        + match.group(1)
        + body
        + match.group(3)
        + source[match.end() :]
    )


def main() -> int:
    report = build_report(
        sorted(PORTS.glob("*.lua")), ROOT, KOTLINX, inventory_tag=KOTLIN_TEST_TAG
    )
    class_name = os.environ.get("usage_class")
    if class_name:
        relevant_issues = [
            issue
            for issue in report["issues"]
            if issue.get("class") in (None, class_name)
        ]
        report["classes"] = [
            cls for cls in report["classes"] if cls["name"] == class_name
        ]
    else:
        relevant_issues = report["issues"]
    if relevant_issues:
        print(
            f"Kotlin inventory has {len(relevant_issues)} relevant issue(s); refusing to generate incomplete stubs",
            file=sys.stderr,
        )
        return 1

    candidates = [cls for cls in report["classes"] if cls["port_status"] == "unported"]
    if class_name:
        candidates = [cls for cls in candidates if cls["name"] == class_name]
        if not candidates:
            print(f"no unported Kotlin test class named {class_name}", file=sys.stderr)
            return 1
    generated: list[tuple[Path, dict[str, object]]] = []
    for cls in candidates:
        name = str(cls["name"])
        if not CLASS_NAME.fullmatch(name):
            print(
                f"Skipping Kotlin class with unsupported Lua/Rust identifier: {name}",
                file=sys.stderr,
            )
            continue
        target = PORTS / f"{name}.lua"
        if target.exists():
            print(f"Skipping existing file {target.relative_to(ROOT)}", file=sys.stderr)
            continue
        generated.append((target, cls))

    if os.environ.get("usage_dry_run") == "true":
        for target, _ in generated:
            print(target.relative_to(ROOT))
        print(f"Would generate {len(generated)} stub(s)")
        return 0

    for target, cls in generated:
        contents = render_kotlin_stub(
            str(cls["name"]),
            str(cls["kotlin_source"]),
            str(cls["tag"]),
            [str(test["name"]) for test in cls["tests"]],
        )
        target.write_text(contents)

    if generated:
        test_source = TESTS_RS.read_text()
        updated = register_classes(
            test_source, {str(cls["name"]) for _, cls in generated}
        )
        TESTS_RS.write_text(updated)

    print(
        f"Generated {len(generated)} pending Kotlin port stub(s) and registered them in {TESTS_RS.relative_to(ROOT)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
