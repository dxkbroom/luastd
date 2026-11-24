"""Shared parser and report model for the kotlinx.coroutines test ports."""

from __future__ import annotations

import re
import subprocess
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path

from kotlin_syntax import KotlinSources
from lua_syntax import LuaSources

KOTLIN_REF = re.compile(r"^\s*-- kotlin:\s*(\S+)@(\S+)\s*$")
MARK = re.compile(r"^\s*--\s*(adapted|not-applicable|defer|todo):\s*(.*)$")
COMMENT = re.compile(r"^\s*--(.*)$")
STATUSES = ("ported", "adapted", "not-applicable", "defer", "todo", "missing")
KOTLIN_TEST_TAG = "1.11.0"
KOTLIN_TEST_DIR = "kotlinx-coroutines-core/common/test"


@dataclass(frozen=True)
class TestPort:
    name: str
    status: str
    reason: str
    line: int


@dataclass
class Port:
    cls: str
    path: str
    tag: str
    file: Path
    tests: list[TestPort] = field(default_factory=list)


@dataclass(frozen=True)
class Issue:
    code: str
    message: str
    file: str | None = None
    cls: str | None = None
    test: str | None = None

    def as_dict(self) -> dict[str, str]:
        result = {"code": self.code, "message": self.message}
        if self.file is not None:
            result["file"] = self.file
        if self.cls is not None:
            result["class"] = self.cls
        if self.test is not None:
            result["test"] = self.test
        return result


def reason_above(lines: list[str], index: int) -> tuple[str, str] | None:
    """Find a status mark in the contiguous comment block above a test."""
    block: list[str] = []
    cursor = index - 1
    while cursor >= 0 and COMMENT.match(lines[cursor]):
        block.insert(0, lines[cursor])
        cursor -= 1
    for mark_index, line in enumerate(block):
        mark = MARK.match(line)
        if mark:
            text = [mark.group(2).strip()]
            for more in block[mark_index + 1 :]:
                if MARK.match(more):
                    break
                text.append(COMMENT.match(more).group(1).strip())
            return mark.group(1), " ".join(part for part in text if part)
    return None


def parse_port(
    file: Path, lua_sources: LuaSources | None = None
) -> tuple[list[Port], list[Issue]]:
    """Parse port classes and return structural issues without losing duplicates."""
    try:
        source_text = file.read_text()
    except OSError as error:
        return [], [Issue("port-unreadable", str(error), file=str(file))]

    lines = source_text.splitlines()
    document = (lua_sources or LuaSources()).get(source_text)
    root = document.root
    ports: list[Port] = []
    issues: list[Issue] = []
    if document.tree.root_node.has_error:
        issues.append(
            Issue("lua-syntax-error", "Lua syntax error in port", file=str(file))
        )
    pending_ref: re.Match[str] | None = None
    current: Port | None = None
    group_mark: tuple[str, str] | None = None
    saw_ref = False
    saw_describe = False
    for node in root.named_children:
        if node.type == "comment":
            reference = KOTLIN_REF.match(document.node_text(node))
            if reference:
                pending_ref = reference
                saw_ref = True
            continue

        call = document.call(node)
        if call is None or call[0] != "describe" or pending_ref is None:
            continue
        function = document.described_function(node)
        if function is None:
            continue
        current = Port(call[1], pending_ref.group(1), pending_ref.group(2), file)
        ports.append(current)
        pending_ref = None
        group_mark = None
        saw_describe = True

        body = function.child_by_field_name("body")
        if body is None:
            continue
        test_calls = document.test_calls(body)
        calls_by_line = {test.line - 1: test for test in test_calls}
        for test_call in test_calls:
            kind, name = test_call.kind, test_call.name
            index = test_call.line - 1
            mark = reason_above(lines, index)
            if kind == "pending":
                # One mark above the first pending call can cover an adjacent run.
                previous = calls_by_line.get(index - 1)
                chained = bool(previous and previous.kind == "pending")
                if mark and mark[0] in ("not-applicable", "defer", "todo"):
                    group_mark = mark
                    status, reason = mark
                elif mark:
                    group_mark = None
                    status, reason = "todo", ""
                elif chained and group_mark:
                    status, reason = group_mark
                else:
                    group_mark = None
                    status, reason = "todo", ""
            else:
                group_mark = None
                if mark and mark[0] == "adapted":
                    status, reason = mark
                else:
                    status, reason = "ported", ""
                    if mark and mark[0] in ("not-applicable", "defer", "todo"):
                        issues.append(
                            Issue(
                                "invalid-status-marker",
                                f"{mark[0]} marker is attached to an active test",
                                file=str(file),
                                cls=current.cls,
                                test=name,
                            )
                        )
            current.tests.append(TestPort(name, status, reason, index + 1))

    if not saw_ref:
        issues.append(
            Issue(
                "kotlin-reference-missing", "no Kotlin source reference", file=str(file)
            )
        )
    elif not saw_describe:
        issues.append(
            Issue(
                "describe-missing",
                "Kotlin reference is not followed by a describe block",
                file=str(file),
            )
        )
    if pending_ref is not None:
        issues.append(
            Issue(
                "describe-missing",
                "Kotlin reference is not followed by a describe block",
                file=str(file),
            )
        )
    return ports, issues


def reorder_lua_tests(
    source: str,
    kotlin_tests: list[str],
    lua_sources: LuaSources | None = None,
) -> str:
    """Reorder top-level Lua test blocks to Kotlin order, preserving block text."""
    return (lua_sources or LuaSources()).get(source).reorder_tests(kotlin_tests)


def kotlin_source(path: str, tag: str, checkout: Path) -> str | None:
    cdtag_source = checkout / ".git" / "cdtag" / tag / path
    if cdtag_source.is_file():
        try:
            return cdtag_source.read_text()
        except OSError:
            pass
    try:
        return subprocess.run(
            ["git", "-C", str(checkout), "show", f"{tag}:{path}"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        return None


def kotlin_test_sources(
    checkout: Path, tag: str
) -> tuple[list[tuple[str, str | None]], list[Issue]]:
    """List Kotlin test sources at the pinned tag, using the cached tag tree when available."""
    tagged_root = checkout / ".git" / "cdtag" / tag
    test_root = tagged_root / KOTLIN_TEST_DIR
    if test_root.is_dir():
        paths = sorted(
            path.relative_to(tagged_root).as_posix()
            for path in test_root.rglob("*Test.kt")
        )
    else:
        try:
            result = subprocess.run(
                [
                    "git",
                    "-C",
                    str(checkout),
                    "ls-tree",
                    "-r",
                    "--name-only",
                    tag,
                    "--",
                    KOTLIN_TEST_DIR,
                ],
                check=True,
                capture_output=True,
                text=True,
            )
        except (OSError, subprocess.CalledProcessError) as error:
            return [], [
                Issue(
                    "kotlin-inventory-unresolved",
                    f"cannot list Kotlin tests at {tag}: {error}",
                )
            ]
        paths = [
            path for path in result.stdout.splitlines() if path.endswith("Test.kt")
        ]

    sources: list[tuple[str, str | None]] = []
    issues: list[Issue] = []
    for path in paths:
        source_file = tagged_root / path
        try:
            source = (
                source_file.read_text()
                if source_file.is_file()
                else kotlin_source(path, tag, checkout)
            )
        except OSError:
            source = None
        sources.append((path, source))
        if source is None:
            issues.append(
                Issue(
                    "kotlin-source-unresolved",
                    f"cannot read {path}@{tag} from {checkout}",
                    file=path,
                )
            )
    return sources, issues


def kotlin_class_test_methods(
    source: str,
    cls: str,
    abstract_methods: dict[str, list[str]] | None = None,
    kotlin_sources: KotlinSources | None = None,
) -> list[str]:
    """Return a class's @Test methods, including methods inherited from abstract bases."""
    documents = kotlin_sources or KotlinSources()
    return documents.get(source).test_methods(cls, abstract_methods)


def kotlin_test_classes(
    source: str,
    abstract_methods: dict[str, list[str]] | None = None,
    kotlin_sources: KotlinSources | None = None,
) -> list[tuple[str, list[str]]]:
    """Associate @Test methods with concrete classes, including inherited methods."""
    documents = kotlin_sources or KotlinSources()
    return documents.get(source).test_classes(abstract_methods)


def inherited_test_methods(
    sources: list[tuple[str, str | None]],
    kotlin_sources: KotlinSources | None = None,
) -> dict[str, list[str]]:
    """Collect abstract test methods so subclasses in other files can inherit them."""
    documents = kotlin_sources or KotlinSources()
    abstract_tests: dict[str, list[str]] = {}
    parents: dict[str, str | None] = {}
    for _path, source in sources:
        if source is None:
            continue
        tests, source_parents = documents.get(source).abstract_methods()
        abstract_tests.update(tests)
        parents.update(source_parents)

    def resolve(name: str, visiting: frozenset[str] = frozenset()) -> list[str]:
        if name in visiting:
            return abstract_tests.get(name, [])
        result = list(abstract_tests.get(name, []))
        parent = parents.get(name)
        if parent in abstract_tests:
            result.extend(resolve(parent, visiting | {name}))
        return result

    return {name: resolve(name) for name in abstract_tests}


def kotlin_test_lines(
    source: str, kotlin_sources: KotlinSources | None = None
) -> dict[str, int]:
    """Return source line numbers for directly declared @Test methods."""
    documents = kotlin_sources or KotlinSources()
    return documents.get(source).test_lines()


def render_kotlin_stub(name: str, source: str, tag: str, tests: list[str]) -> str:
    """Render an initial Lua spec with one reasoned pending case per Kotlin test."""
    lines = [
        "-- Generated by `mise run kotlin:stubs`; replace pending cases as they are ported.",
        f"-- kotlin: {source}@{tag}",
        f'describe("{name}", function ()',
    ]
    for test in tests:
        lines.extend(
            ("    -- todo: port this Kotlin test in Lua.", f'    pending("{test}")', "")
        )
    lines.extend(("end)", ""))
    return "\n".join(lines)


def relative(path: Path, root: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return str(path)


def build_report(
    files: list[Path],
    root: Path,
    checkout: Path,
    source_loader: Callable[[str, str, Path], str | None] = kotlin_source,
    inventory_tag: str | None = None,
) -> dict[str, object]:
    """Create the JSON-ready coverage report and its validation issues."""
    classes: list[dict[str, object]] = []
    issues: list[Issue] = []
    lua_sources = LuaSources()
    kotlin_sources = KotlinSources()
    seen_classes: dict[str, str] = {}
    inventory: list[tuple[str, str | None]] = []
    abstract_methods: dict[str, list[str]] = {}
    if inventory_tag is not None:
        inventory, inventory_issues = kotlin_test_sources(checkout, inventory_tag)
        issues.extend(inventory_issues)
        abstract_methods = inherited_test_methods(inventory, kotlin_sources)

    for file in sorted(files):
        parsed, parse_issues = parse_port(file, lua_sources)
        issues.extend(
            Issue(
                issue.code,
                issue.message,
                file=relative(file, root),
                cls=issue.cls,
                test=issue.test,
            )
            for issue in parse_issues
        )
        if not parsed:
            continue
        for port in parsed:
            lua_file = relative(file, root)
            if port.cls in seen_classes:
                issues.append(
                    Issue(
                        "duplicate-class-port",
                        f"class also appears in {seen_classes[port.cls]}",
                        file=lua_file,
                        cls=port.cls,
                    )
                )
            else:
                seen_classes[port.cls] = lua_file

            source = source_loader(port.path, port.tag, checkout)
            source_tests: list[str] = []
            source_test_lines: dict[str, int] = {}
            if source is None:
                issues.append(
                    Issue(
                        "kotlin-source-unresolved",
                        f"cannot read {port.path}@{port.tag} from {checkout}",
                        file=lua_file,
                        cls=port.cls,
                    )
                )
            else:
                kotlin_document = kotlin_sources.get(source)
                if kotlin_document.has_syntax_error:
                    issues.append(
                        Issue(
                            "kotlin-syntax-error",
                            f"Tree-sitter reported a syntax error in {port.path}@{port.tag}",
                            file=lua_file,
                            cls=port.cls,
                        )
                    )
                if port.cls not in kotlin_document.classes_by_name:
                    issues.append(
                        Issue(
                            "kotlin-class-missing",
                            f"class {port.cls} was not found in {port.path}",
                            file=lua_file,
                            cls=port.cls,
                        )
                    )
                source_tests = kotlin_document.test_methods(port.cls, abstract_methods)
                source_test_lines = kotlin_document.test_lines()

            mapped: dict[str, TestPort] = {}
            for test in port.tests:
                if test.name in mapped:
                    issues.append(
                        Issue(
                            "duplicate-test-mapping",
                            f"test is listed more than once (first at line {mapped[test.name].line})",
                            file=lua_file,
                            cls=port.cls,
                            test=test.name,
                        )
                    )
                mapped[test.name] = test
                if not test.reason and test.status in (
                    "adapted",
                    "not-applicable",
                    "defer",
                    "todo",
                ):
                    issues.append(
                        Issue(
                            "status-reason-missing",
                            f"{test.status} status requires a reason",
                            file=lua_file,
                            cls=port.cls,
                            test=test.name,
                        )
                    )

            stale_tests = [
                {"name": name, "line": test.line}
                for name, test in mapped.items()
                if source is not None and name not in source_tests
            ]
            for stale in stale_tests:
                issues.append(
                    Issue(
                        "stale-test-mapping",
                        f"{stale['name']} is not a Kotlin @Test in {port.cls}",
                        file=lua_file,
                        cls=port.cls,
                        test=str(stale["name"]),
                    )
                )

            tests: list[dict[str, object]] = []
            names = (
                source_tests
                if source is not None
                else [test.name for test in port.tests]
            )
            for name in names:
                test = mapped.get(name)
                tests.append(
                    {
                        "name": name,
                        "status": test.status if test else "missing",
                        "reason": test.reason or None if test else None,
                        "kotlin_line": source_test_lines.get(name),
                        "lua_line": test.line if test else None,
                    }
                )
            counts = {
                status: sum(item["status"] == status for item in tests)
                for status in STATUSES
            }
            classes.append(
                {
                    "name": port.cls,
                    "port_status": "ported",
                    "kotlin_source": port.path,
                    "tag": port.tag,
                    "lua_port": lua_file,
                    "tests": tests,
                    "stale_tests": stale_tests,
                    "counts": counts,
                }
            )

    if inventory_tag is not None:
        inventory_classes: set[str] = set()
        for path, source in inventory:
            if source is None:
                continue
            kotlin_document = kotlin_sources.get(source)
            if kotlin_document.has_syntax_error:
                issues.append(
                    Issue(
                        "kotlin-syntax-error",
                        f"Tree-sitter reported a syntax error in {path}@{inventory_tag}",
                        file=path,
                    )
                )
            test_classes = kotlin_document.test_classes(abstract_methods)
            if (
                not test_classes
                and kotlin_document.has_test_functions
                and not kotlin_document.classes
            ):
                issues.append(
                    Issue(
                        "kotlin-class-missing",
                        f"no test class declaration found in {path}",
                        file=path,
                    )
                )
            for cls, test_names in test_classes:
                if cls in seen_classes:
                    continue
                if cls in inventory_classes:
                    issues.append(
                        Issue(
                            "duplicate-kotlin-test-class",
                            f"class {cls} appears more than once in the Kotlin test tree",
                            file=path,
                            cls=cls,
                        )
                    )
                    continue
                inventory_classes.add(cls)
                missing_tests = [
                    {"name": name, "status": "missing", "reason": None}
                    for name in test_names
                ]
                counts = {
                    status: sum(test["status"] == status for test in missing_tests)
                    for status in STATUSES
                }
                classes.append(
                    {
                        "name": cls,
                        "port_status": "unported",
                        "kotlin_source": path,
                        "tag": inventory_tag,
                        "lua_port": None,
                        "tests": missing_tests,
                        "stale_tests": [],
                        "counts": counts,
                    }
                )

    totals = {status: 0 for status in STATUSES}
    for item in classes:
        for status in STATUSES:
            totals[status] += item["counts"][status]  # type: ignore[index]
    summary = {
        "classes": len(classes),
        "unported_classes": sum(item["port_status"] == "unported" for item in classes),
        **totals,
        "issues": len(issues),
    }
    summary["not_applicable"] = summary.pop("not-applicable")
    for item in classes:
        item["counts"]["not_applicable"] = item["counts"].pop("not-applicable")  # type: ignore[index]
    return {
        "schema_version": 1,
        "summary": summary,
        "classes": classes,
        "issues": [issue.as_dict() for issue in issues],
    }


def filter_report(
    report: dict[str, object], selected: set[str] | None
) -> dict[str, object]:
    """Keep only selected test statuses while preserving report diagnostics."""
    if not selected:
        return report

    status_keys = [status.replace("-", "_") for status in STATUSES]
    classes = []
    for cls in report["classes"]:
        tests = [test for test in cls["tests"] if test["status"] in selected]
        if not tests and not ("missing" in selected and cls["stale_tests"]):
            continue
        filtered = {**cls, "tests": tests}
        filtered["counts"] = {
            key: sum(test["status"].replace("-", "_") == key for test in tests)
            for key in status_keys
        }
        filtered["stale_tests"] = [
            stale for stale in cls["stale_tests"] if "missing" in selected
        ]
        classes.append(filtered)

    summary = {
        "classes": len(classes),
        "unported_classes": sum(cls["port_status"] == "unported" for cls in classes),
        **{key: sum(cls["counts"][key] for cls in classes) for key in status_keys},
        "issues": report["summary"]["issues"],
    }
    return {
        **report,
        "summary": summary,
        "classes": classes,
    }


def markdown_report(report: dict[str, object]) -> str:
    """Render a portable nested Markdown list from the report model."""
    summary = report["summary"]
    counts = " · ".join(
        f"{summary[key]} {label}"
        for key, label in (
            ("ported", "ported"),
            ("adapted", "adapted"),
            ("not_applicable", "not-applicable"),
            ("defer", "defer"),
            ("todo", "todo"),
            ("missing", "missing"),
        )
    )
    lines = [
        f"# Kotlin coroutine test ports — {summary['classes']} classes ({summary['unported_classes']} unported)",
        "",
        counts,
        "",
    ]
    status_icon = {
        "ported": "✓",
        "adapted": "~",
        "not-applicable": "○",
        "defer": "↷",
        "todo": "·",
        "missing": "✗",
    }
    for cls in report["classes"]:
        class_counts = " · ".join(
            f"{cls['counts'][key]} {label}"
            for key, label in (
                ("ported", "ported"),
                ("adapted", "adapted"),
                ("not_applicable", "not-applicable"),
                ("defer", "defer"),
                ("todo", "todo"),
                ("missing", "missing"),
            )
            if cls["counts"][key]
        )
        if cls["port_status"] == "unported":
            class_label = f"**{cls['name']} — unported**"
            port_label = "no Lua port"
        else:
            class_label = f"**{cls['name']}**"
            port_label = f"`{cls['lua_port']}`"
        lines.append(
            f"- {class_label} — `{cls['kotlin_source']}@{cls['tag']}` → {port_label} ({class_counts})"
        )
        for test in cls["tests"]:
            suffix = f" — {test['reason']}" if test["reason"] else ""
            lines.append(
                f"  - {status_icon[test['status']]} `{test['name']}` — {test['status']}{suffix}"
            )
        for stale in cls["stale_tests"]:
            lines.append(
                f"  - ✗ `{stale['name']}` — stale mapping (Lua line {stale['line']})"
            )
    if report["issues"]:
        lines.extend(("", "## Issues"))
        for issue in report["issues"]:
            location = ":".join(
                part
                for part in (issue.get("file"), issue.get("class"), issue.get("test"))
                if part
            )
            lines.append(
                f"- `{issue['code']}`{f' at `{location}`' if location else ''}: {issue['message']}"
            )
    return "\n".join(lines) + "\n"


def has_gaps(report: dict[str, object]) -> bool:
    """Whether `--check` should fail for missing coverage or invalid metadata."""
    return bool(report["summary"]["missing"] or report["issues"])
