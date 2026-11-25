#!/usr/bin/env -S uv run --project xtasks python
# MISE description="Run one Kotlin coroutine Lua port test"
# USAGE arg "<class>" help="Kotlin test class registered in the kotlinx test target"
# USAGE arg "[target]" default="luajit52" help="Lua version used by the test runtime" {
# USAGE   choices "luajit52" "luajit" "lua52" "lua53" "lua54" "lua55"
# USAGE }
"""Run one registered Kotlin coroutine port with the correct Lua features."""

from __future__ import annotations

import os
import subprocess


def main() -> int:
    class_name = os.environ["usage_class"]
    target = os.environ["usage_target"]
    result = subprocess.run(
        [
            "cargo",
            "test",
            "-p",
            "luastd_runtime",
            "--test",
            "kotlinx",
            "--features",
            f"{target},vendored",
            class_name,
        ],
        check=False,
    )
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
