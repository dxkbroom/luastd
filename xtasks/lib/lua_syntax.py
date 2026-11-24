"""Tree-sitter-backed Lua source documents used by the xtasks."""

from __future__ import annotations

import ast
import re
from collections.abc import Iterator
from dataclasses import dataclass

from tree_sitter import Node
from tree_sitter_language_pack import get_parser

_MARK = re.compile(r"^\s*--\s*(adapted|not-applicable|defer|todo):\s*(.*)$")
_COMMENT = re.compile(r"^\s{4}--")


@dataclass(frozen=True)
class LuaTestCall:
    kind: str
    name: str
    line: int
    node: Node


class LuaSource:
    """Parsed Lua text with syntax-aware access to port specs and test calls."""

    def __init__(self, text: str, parser) -> None:
        self.text = text
        self.source = text.encode()
        self.tree = parser.parse(self.source)
        self.root = self.tree.root_node
        self.lines = text.splitlines(keepends=True)

    def nodes(self, node: Node) -> Iterator[Node]:
        stack = [node]
        while stack:
            current = stack.pop()
            yield current
            stack.extend(reversed(current.children))

    def node_text(self, node: Node) -> str:
        return self.source[node.start_byte : node.end_byte].decode()

    @staticmethod
    def first_child(node: Node, node_type: str) -> Node | None:
        return next(
            (child for child in node.named_children if child.type == node_type), None
        )

    def string_value(self, node: Node) -> str:
        try:
            value = ast.literal_eval(self.node_text(node))
        except (SyntaxError, ValueError):
            content = self.first_child(node, "string_content")
            return self.node_text(content) if content is not None else ""
        return value if isinstance(value, str) else ""

    def call(self, node: Node) -> tuple[str, str] | None:
        if node.type != "function_call":
            return None
        name_node = node.child_by_field_name("name")
        arguments = node.child_by_field_name("arguments")
        if name_node is None or arguments is None:
            return None
        name = self.node_text(name_node)
        if name not in ("describe", "it", "pending"):
            return None
        string = self.first_child(arguments, "string")
        return (name, self.string_value(string)) if string is not None else None

    def described_function(self, node: Node) -> Node | None:
        arguments = node.child_by_field_name("arguments")
        return (
            self.first_child(arguments, "function_definition")
            if arguments is not None
            else None
        )

    def test_calls(self, body: Node) -> list[LuaTestCall]:
        result = []
        for node in body.named_children:
            call = self.call(node)
            if call is not None and call[0] in ("it", "pending"):
                result.append(
                    LuaTestCall(call[0], call[1], node.start_point.row + 1, node)
                )
        return result

    def reorder_tests(self, kotlin_tests: list[str]) -> str:
        """Reorder direct test calls while preserving each original source block."""
        if self.root.has_error:
            return self.text
        starts: list[tuple[int, LuaTestCall]] = []
        for describe in self.root.named_children:
            call = self.call(describe)
            if call is None or call[0] != "describe":
                continue
            function = self.described_function(describe)
            body = (
                function.child_by_field_name("body") if function is not None else None
            )
            if body is None:
                continue
            for test in self.test_calls(body):
                if test.node.start_point.column != 4:
                    continue
                start = test.line - 1
                while (
                    start > 0
                    and _COMMENT.match(self.lines[start - 1])
                    and not _MARK.match(self.lines[start - 1])
                ):
                    start -= 1
                starts.append((start, test))
        if len(starts) < 2:
            return self.text

        blocks: dict[str, str] = {}
        spans: list[tuple[int, int]] = []
        final_call_end = 0
        for position, (start, test) in enumerate(starts):
            final_call_end = test.node.end_point.row + 1
            end = (
                starts[position + 1][0]
                if position + 1 < len(starts)
                else final_call_end
            )
            spans.append((start, end))
            blocks[test.name] = "".join(self.lines[start:end])

        if len(blocks) != len(starts) or any(
            name not in blocks for name in kotlin_tests
        ):
            return self.text
        ordered = [blocks[name] for name in kotlin_tests if name in blocks]
        ordered.extend(
            blocks[test.name] for _, test in starts if test.name not in kotlin_tests
        )
        first, _ = spans[0]
        return "".join(
            self.lines[:first] + ["".join(ordered)] + self.lines[final_call_end:]
        )


class LuaSources:
    """Per-run parser and parsed-document cache, keyed by source text."""

    def __init__(self) -> None:
        self._parser = get_parser("lua")
        self._documents: dict[str, LuaSource] = {}

    def get(self, text: str) -> LuaSource:
        document = self._documents.get(text)
        if document is None:
            document = LuaSource(text, self._parser)
            self._documents[text] = document
        return document
