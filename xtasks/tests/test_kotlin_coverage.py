"""Unit tests for the Kotlin port coverage report model and renderers."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))

from kotlin_coverage import (
    build_report,
    filter_report,
    has_gaps,
    kotlin_class_test_methods,
    kotlin_test_classes,
    markdown_report,
    parse_port,
    render_kotlin_stub,
    reorder_lua_tests,
)
from kotlin_syntax import KotlinSources
from lua_syntax import LuaSources

SOURCE = """class ExampleTest {
    @Test
    fun testKnown() { expect(1); finish(2) }

    @Test
    fun testAdapted() { expect(1); finish(2) }

    @Test
    fun testTodo() {}

    @Test
    fun testDeprecated() {}

    @Test
    fun testMissing() {}
}
"""

PORT = """-- kotlin: sample/ExampleTest.kt@1.11.0
describe("ExampleTest", function ()
    it("testKnown", function () t:expect(1); t:finish(2) end)
    -- adapted: this port exercises the same case with an existing primitive.
    it("testAdapted", function () t:expect(1); t:finish(3) end)
    -- todo: the API needed by this case is not available.
    pending("testTodo")
    -- deprecated: this case exercises a deprecated Kotlin API.
    pending("testDeprecated")
    it("testStale", function () end)
end)
"""


class KotlinCoverageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.port_file = self.root / "ExampleTest.lua"
        self.port_file.write_text(PORT)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_source_caches_reuse_parsed_lua_and_kotlin_documents(self) -> None:
        lua_sources = LuaSources()
        kotlin_sources = KotlinSources()
        self.assertIs(lua_sources.get(PORT), lua_sources.get(PORT))
        self.assertIs(kotlin_sources.get(SOURCE), kotlin_sources.get(SOURCE))

    def source_loader(self, path: str, tag: str, checkout: Path) -> str | None:
        self.assertEqual("sample/ExampleTest.kt", path)
        self.assertEqual("1.11.0", tag)
        self.assertEqual(self.root, checkout)
        return SOURCE

    def test_parse_port_records_status_reasons_and_line_numbers(self) -> None:
        ports, issues = parse_port(self.port_file)
        self.assertEqual([], issues)
        self.assertEqual(["ExampleTest"], [port.cls for port in ports])
        self.assertEqual(
            [
                ("testKnown", "ported", ""),
                (
                    "testAdapted",
                    "adapted",
                    "this port exercises the same case with an existing primitive.",
                ),
                ("testTodo", "todo", "the API needed by this case is not available."),
                (
                    "testDeprecated",
                    "deprecated",
                    "this case exercises a deprecated Kotlin API.",
                ),
                ("testStale", "ported", ""),
            ],
            [(test.name, test.status, test.reason) for test in ports[0].tests],
        )
        self.assertTrue(all(test.line > 0 for test in ports[0].tests))

    def test_parse_port_reads_multiline_calls_from_lua_syntax_tree(self) -> None:
        self.port_file.write_text("""-- kotlin: sample/ExampleTest.kt@1.11.0
describe("ExampleTest", function ()
    it(
        "testKnown",
        function ()
            local value = "parentheses () are string content"
            assert(value ~= "")
        end
    )
end)
""")
        ports, issues = parse_port(self.port_file)
        self.assertEqual([], issues)
        self.assertEqual(["testKnown"], [test.name for test in ports[0].tests])

    def test_reorder_lua_tests_uses_call_nodes_for_nested_parentheses(self) -> None:
        source = """describe("ExampleTest", function ()
    it("testSecond", function ()
        local value = "closing ) characters"
        helper(function () return value end)
    end)
    it("testFirst", function () end)
end)
"""
        reordered = reorder_lua_tests(source, ["testFirst", "testSecond"])
        self.assertLess(
            reordered.index('it("testFirst"'), reordered.index('it("testSecond"')
        )

    def test_kotlin_tree_sitter_tracks_annotations_and_nested_classes(self) -> None:
        source = """open class BaseTest {
    @kotlin.test.Test
    fun testBase() { fun helper() {} }
}

class DerivedTest : BaseTest()

class NestedTest {
    @Test
    fun testNested() {}
}
"""
        self.assertEqual(["testBase"], kotlin_class_test_methods(source, "DerivedTest"))
        self.assertEqual(
            [
                ("BaseTest", ["testBase"]),
                ("DerivedTest", ["testBase"]),
                ("NestedTest", ["testNested"]),
            ],
            kotlin_test_classes(source),
        )

    def test_report_includes_statuses_missing_and_stale_tests(self) -> None:
        report = build_report(
            [self.port_file], self.root, self.root, self.source_loader
        )
        cls = report["classes"][0]
        self.assertEqual("ExampleTest", cls["name"])
        self.assertEqual(
            ["ported", "adapted", "todo", "deprecated", "missing"],
            [test["status"] for test in cls["tests"]],
        )
        self.assertEqual([{"name": "testStale", "line": 10}], cls["stale_tests"])
        self.assertEqual(1, cls["counts"]["missing"])
        self.assertEqual("matches", cls["tests"][0]["trace"]["status"])
        self.assertEqual("differs", cls["tests"][1]["trace"]["status"])
        self.assertEqual(0, report["summary"]["not_applicable"])
        self.assertIn(
            "stale-test-mapping", {issue["code"] for issue in report["issues"]}
        )
        self.assertTrue(has_gaps(report))

    def test_json_shape_and_markdown_tree(self) -> None:
        report = build_report(
            [self.port_file], self.root, self.root, self.source_loader
        )
        decoded = json.loads(json.dumps(report))
        self.assertEqual(2, decoded["schema_version"])
        self.assertIn("not a claim", decoded["trace_semantics"])
        self.assertIn("not_applicable", decoded["summary"])
        self.assertEqual(
            "sample/ExampleTest.kt", decoded["classes"][0]["kotlin_source"]
        )
        markdown = markdown_report(filter_report(report, None))
        self.assertIn("# Kotlin coroutine test ports", markdown)
        self.assertIn("- **ExampleTest**", markdown)
        self.assertIn("  - ✓ `testKnown` — ported", markdown)
        self.assertIn("trace matches", markdown)
        self.assertIn("kotlin: `expect(1) → finish(2)`", markdown)
        self.assertIn("lua: `expect(1) → finish(2)`", markdown)
        self.assertIn("  - ✗ `testMissing` — missing", markdown)
        self.assertNotIn("testDeprecated", markdown)
        self.assertIn("## Issues", markdown)

    def test_valid_report_passes_check_when_only_todo_and_na_remain(self) -> None:
        valid_source = """class ExampleTest {
    @Test
    fun testTodo() {}

    @Test
    fun testNa() {}
}
"""
        self.port_file.write_text("""-- kotlin: sample/ExampleTest.kt@1.11.0
describe("ExampleTest", function ()
    -- todo: unavailable API.
    pending("testTodo")
    -- not-applicable: this case does not apply to the runtime.
    pending("testNa")
end)
""")
        report = build_report(
            [self.port_file],
            self.root,
            self.root,
            lambda _path, _tag, _checkout: valid_source,
        )
        self.assertEqual([], report["issues"])
        self.assertFalse(has_gaps(report))

    def test_deprecated_cases_are_hidden_by_default_and_selectable(self) -> None:
        report = build_report(
            [self.port_file], self.root, self.root, self.source_loader
        )
        default = filter_report(report, None)
        self.assertNotIn(
            "testDeprecated",
            [test["name"] for cls in default["classes"] for test in cls["tests"]],
        )
        deprecated = filter_report(report, {"deprecated"})
        self.assertEqual(
            ["testDeprecated"],
            [test["name"] for cls in deprecated["classes"] for test in cls["tests"]],
        )

    def test_check_fails_for_missing_reason_and_duplicate_mapping(self) -> None:
        self.port_file.write_text("""-- kotlin: sample/ExampleTest.kt@1.11.0
describe("ExampleTest", function ()
    pending("testKnown")
    pending("testKnown")
end)
""")
        report = build_report(
            [self.port_file], self.root, self.root, self.source_loader
        )
        codes = {issue["code"] for issue in report["issues"]}
        self.assertIn("status-reason-missing", codes)
        self.assertIn("duplicate-test-mapping", codes)
        self.assertTrue(has_gaps(report))

    def test_unresolved_source_is_an_issue_and_fails_check(self) -> None:
        report = build_report(
            [self.port_file],
            self.root,
            self.root,
            lambda _path, _tag, _checkout: None,
        )
        self.assertIn(
            "kotlin-source-unresolved", {issue["code"] for issue in report["issues"]}
        )
        self.assertTrue(has_gaps(report))

    def test_missing_kotlin_reference_is_an_issue(self) -> None:
        self.port_file.write_text('describe("ExampleTest", function () end)\n')
        report = build_report(
            [self.port_file], self.root, self.root, self.source_loader
        )
        self.assertIn(
            "kotlin-reference-missing", {issue["code"] for issue in report["issues"]}
        )
        self.assertTrue(has_gaps(report))

    def test_inventory_adds_kotlin_classes_without_lua_ports(self) -> None:
        test_root = self.root / ".git/cdtag/1.11.0/kotlinx-coroutines-core/common/test"
        test_root.mkdir(parents=True)
        (test_root / "ExampleTest.kt").write_text(SOURCE)
        (test_root / "UnportedTest.kt").write_text("""class UnportedTest {
    @Test
    fun testOnlyOnKotlin() {}
}
""")
        (
            test_root / "InheritedTest.kt"
        ).write_text("""abstract class InheritedTestBase {
    @Test
    fun testInherited() {}
}

class InheritedTest : InheritedTestBase()
""")
        report = build_report(
            [self.port_file],
            self.root,
            self.root,
            self.source_loader,
            inventory_tag="1.11.0",
        )
        unported = next(
            cls for cls in report["classes"] if cls["name"] == "UnportedTest"
        )
        self.assertEqual("unported", unported["port_status"])
        self.assertIsNone(unported["lua_port"])
        self.assertEqual("missing", unported["tests"][0]["status"])
        self.assertEqual(2, report["summary"]["unported_classes"])
        inherited = next(
            cls for cls in report["classes"] if cls["name"] == "InheritedTest"
        )
        self.assertEqual(
            ["testInherited"], [test["name"] for test in inherited["tests"]]
        )
        self.assertEqual(3, report["summary"]["classes"])
        self.assertTrue(has_gaps(report))

    def test_render_stub_marks_each_kotlin_test_todo(self) -> None:
        stub = render_kotlin_stub(
            "ExampleTest",
            "kotlinx-coroutines-core/common/test/ExampleTest.kt",
            "1.11.0",
            ["testOne", "testTwo"],
        )
        target = self.root / "Generated.lua"
        target.write_text(stub)
        ports, issues = parse_port(target)
        self.assertEqual([], issues)
        self.assertEqual(["ExampleTest"], [port.cls for port in ports])
        self.assertEqual(["testOne", "testTwo"], [test.name for test in ports[0].tests])
        self.assertTrue(
            all(test.status == "todo" and test.reason for test in ports[0].tests)
        )


if __name__ == "__main__":
    unittest.main()
