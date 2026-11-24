#!/usr/bin/env -S uv run --project xtasks python
#MISE description="Rewrite `local cases = { {name=, run=} }` busted specs into describe/it blocks"
#USAGE flag "--check" help="Only report which files would change; exit 1 if any would"
#USAGE flag "--no-group" help="Don't nest cases into describe blocks by their first word"
#USAGE flag "--no-fmt" help="Don't run luafmt on rewritten files"
#USAGE arg "[FILES]..." help="Spec files to rewrite (default: every spec/*_spec.lua with a cases table)"
"""Convert table-driven busted specs into plain describe/it blocks.

Recognised input (indentation is arbitrary, quotes may be ' or "):

    local cases = {
        { name = "new keeps the text", run = function () ... end },
        ...
    }
    for _, case in pairs(cases) do
        it(case.name, case.run)
    end

Output: one top-level `describe(<module>)` (module taken from the first
`require("...")`, else the file name). Inside it, cases whose names share a
first word are nested in `describe(<word>)` with that word stripped from the
`it` name, so busted still prints the original full name. Top-level `it(...)`
blocks are folded in the same way. Everything else in the file is kept.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

IND = "    "


@dataclass
class Case:
    name: str
    body: list[str]  # dedented body lines


def dedent(lines: list[str]) -> list[str]:
    widths = [len(l) - len(l.lstrip()) for l in lines if l.strip()]
    cut = min(widths, default=0)
    return [l[cut:] if l.strip() else "" for l in lines]


def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


CASES_START = re.compile(r"^local (\w+) = \{\s*$")
LOOP = re.compile(
    r"^for _, (\w+) in i?pairs\((\w+)\) do\s*\n\s*it\(\1\.name, \1\.run\)\s*\nend\s*\n?",
    re.M,
)
ENTRY = re.compile(
    r"\{\s*name\s*=\s*(?P<q>[\"'])(?P<name>(?:\\.|(?!(?P=q)).)*)(?P=q)\s*,\s*"
    r"run\s*=\s*function\s*\(\s*\)[ \t]*\n(?P<body>.*?)\n[ \t]*end\s*,?\s*\}\s*,?",
    re.S,
)
TOP_IT = re.compile(
    r"^it\((?P<q>[\"'])(?P<name>(?:\\.|(?!(?P=q)).)*)(?P=q),\s*function\s*\(\s*\)[ \t]*\n(?P<body>.*?)\n^end\)\s*\n?",
    re.S | re.M,
)


def find_cases_block(lines: list[str]) -> tuple[int, int, str] | None:
    """Return (start, end_exclusive, var) of the top-level cases table."""
    for i, line in enumerate(lines):
        m = CASES_START.match(line)
        if not m:
            continue
        for j in range(i + 1, len(lines)):
            if lines[j].rstrip() == "}":
                return i, j + 1, m.group(1)
    return None


def unescape(s: str) -> str:
    return re.sub(r"\\(.)", r"\1", s)


def module_name(src: str, path: Path) -> str:
    m = re.search(r"require\s*\(?\s*[\"']([^\"']+)[\"']", src)
    if m:
        return m.group(1)
    return path.stem.removesuffix("_spec")


def group(cases: list[Case], enabled: bool) -> list[tuple[str | None, list[Case]]]:
    if not enabled:
        return [(None, cases)]
    first = [c.name.split(" ", 1)[0] for c in cases]
    counts: dict[str, int] = {}
    for w in first:
        counts[w] = counts.get(w, 0) + 1
    out: list[tuple[str | None, list[Case]]] = []
    index: dict[str, int] = {}
    for c, w in zip(cases, first):
        if counts[w] >= 2 and " " in c.name:
            if w not in index:
                index[w] = len(out)
                out.append((w, []))
            out[index[w]][1].append(Case(c.name.split(" ", 1)[1], c.body))
        else:
            out.append((None, [c]))
    return out


def render_it(c: Case, depth: int) -> list[str]:
    pad = IND * depth
    lines = [f"{pad}it({lua_str(c.name)}, function ()"]
    lines += [(pad + IND + l) if l else "" for l in c.body]
    lines.append(f"{pad}end)")
    return lines


def convert(path: Path, do_group: bool) -> str | None:
    src = path.read_text()
    lines = src.split("\n")
    block = find_cases_block(lines)
    if block is None:
        return None
    start, end, var = block
    table_src = "\n".join(lines[start + 1 : end - 1])
    cases = [
        Case(unescape(m["name"]), dedent(m["body"].split("\n")))
        for m in ENTRY.finditer(table_src)
    ]
    expected = len(re.findall(r"\bname\s*=", table_src))
    if len(cases) != expected:
        raise SystemExit(f"{path}: parsed {len(cases)} of {expected} cases; refusing to rewrite")

    rest = "\n".join(lines[:start]) + "\n\x00CASES\x00\n" + "\n".join(lines[end:])
    loop = LOOP.search(rest)
    if not loop or loop.group(2) != var:
        raise SystemExit(f"{path}: no `for _, case in pairs({var}) do it(case.name, case.run) end` loop found")
    rest = rest[: loop.start()] + rest[loop.end() :]

    # Fold top-level it(...) blocks into the describe, before the table cases.
    top: list[Case] = []

    def take(m: re.Match) -> str:
        top.append(Case(unescape(m["name"]), dedent(m["body"].split("\n"))))
        return ""

    rest = TOP_IT.sub(take, rest)

    body: list[str] = [f"describe({lua_str(module_name(src, path))}, function ()"]
    for i, (title, members) in enumerate(group(top + cases, do_group)):
        if i:
            body.append("")
        if title is None:
            for j, c in enumerate(members):
                if j:
                    body.append("")
                body += render_it(c, 1)
            continue
        body.append(f"{IND}describe({lua_str(title)}, function ()")
        for j, c in enumerate(members):
            if j:
                body.append("")
            body += render_it(c, 2)
        body.append(f"{IND}end)")
    body.append("end)")

    out = rest.replace("\x00CASES\x00", "\n".join(body))
    out = re.sub(r"\n{3,}", "\n\n", out).strip("\n") + "\n"
    return out


def main(argv: list[str]) -> int:
    check = os.environ.get("usage_check") == "true" or "--check" in argv
    no_group = os.environ.get("usage_no_group") == "true" or "--no-group" in argv
    no_fmt = os.environ.get("usage_no_fmt") == "true" or "--no-fmt" in argv
    files = [Path(a) for a in argv if not a.startswith("--")]
    if not files and os.environ.get("usage_files"):
        files = [Path(f) for f in os.environ["usage_files"].split()]
    if not files:
        files = sorted(Path("spec").glob("**/*_spec.lua"))

    changed: list[Path] = []
    for f in files:
        new = convert(f, not no_group)
        if new is None:
            continue
        changed.append(f)
        if check:
            print(f"would rewrite {f}")
            continue
        f.write_text(new)
        print(f"rewrote {f}")

    if changed and not check and not no_fmt and shutil.which("luafmt"):
        subprocess.run(["luafmt", "--write", *map(str, changed)], check=True)
    if not changed:
        print("no cases tables found")
    return 1 if check and changed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
