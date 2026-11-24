"""Tree-sitter-backed Kotlin source documents used by the xtasks."""

from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass

from tree_sitter import Node
from tree_sitter_language_pack import get_parser


@dataclass(frozen=True)
class KotlinClassInfo:
    name: str
    parent: str | None
    abstract: bool
    tests: tuple[tuple[str, int], ...]


class KotlinSource:
    """Parsed Kotlin text with indexed classes and annotated test functions."""

    def __init__(self, text: str, parser) -> None:
        self.text = text
        self.source = text.encode()
        self.tree = parser.parse(self.source)
        self.has_syntax_error = self.tree.root_node.has_error
        self._test_nodes: dict[tuple[str, str], Node] = {}
        self.classes = self._classes()
        self.classes_by_name = {item.name: item for item in self.classes}
        self.has_test_functions = any(
            node.type == "function_declaration" and self._test_name(node)
            for node in self._walk(self.tree.root_node)
        )

    def _walk(self, node: Node) -> Iterator[Node]:
        stack = [node]
        while stack:
            current = stack.pop()
            yield current
            stack.extend(reversed(current.children))

    def _text(self, node: Node) -> str:
        return self.source[node.start_byte : node.end_byte].decode()

    @staticmethod
    def _first_child(node: Node, node_type: str) -> Node | None:
        return next(
            (child for child in node.named_children if child.type == node_type), None
        )

    def _test_name(self, node: Node) -> str | None:
        modifiers = self._first_child(node, "modifiers")
        if modifiers is None:
            return None
        is_test = any(
            annotation.type == "annotation"
            and any(
                user_type.type == "user_type"
                and self._text(user_type).split(".")[-1] == "Test"
                for user_type in self._walk(annotation)
            )
            for annotation in self._walk(modifiers)
        )
        if not is_test:
            return None
        name = self._first_child(node, "simple_identifier")
        return self._text(name) if name is not None else None

    def _classes(self) -> tuple[KotlinClassInfo, ...]:
        classes = []
        for declaration in (
            node
            for node in self._walk(self.tree.root_node)
            if node.type == "class_declaration"
        ):
            name_node = self._first_child(declaration, "type_identifier")
            if name_node is None:
                continue
            modifiers = self._first_child(declaration, "modifiers")
            abstract = bool(
                modifiers
                and any(
                    node.type == "inheritance_modifier"
                    and self._text(node) == "abstract"
                    for node in self._walk(modifiers)
                )
            )
            delegation = self._first_child(declaration, "delegation_specifier")
            parent_node = (
                next(
                    (
                        node
                        for node in self._walk(delegation)
                        if node.type == "type_identifier"
                    ),
                    None,
                )
                if delegation is not None
                else None
            )
            body = self._first_child(declaration, "class_body")
            tests = []
            if body is not None:
                for member in body.named_children:
                    if member.type != "function_declaration":
                        continue
                    test_name = self._test_name(member)
                    if test_name is not None:
                        tests.append((test_name, member.start_point.row + 1))
                        self._test_nodes[(self._text(name_node), test_name)] = member
            classes.append(
                KotlinClassInfo(
                    name=self._text(name_node),
                    parent=self._text(parent_node) if parent_node else None,
                    abstract=abstract,
                    tests=tuple(tests),
                )
            )
        return tuple(classes)

    def trace_events(
        self, class_name: str, test_name: str
    ) -> list[dict[str, object]] | None:
        """Return source-ordered expect/finish markers for a test method."""
        info = self.classes_by_name.get(class_name)
        if info is None:
            return None
        method = self._test_nodes.get((class_name, test_name))
        if method is None and info.parent is not None:
            return self.trace_events(info.parent, test_name)
        if method is None:
            return None

        events = []
        for call in self._walk(method):
            if call.type != "call_expression":
                continue
            name = self._first_child(call, "simple_identifier")
            if name is None:
                continue
            event_name = self._text(name)
            if event_name not in ("expect", "finish", "expectUnreached"):
                continue
            suffix = self._first_child(call, "call_suffix")
            arguments = self._first_child(suffix, "value_arguments") if suffix else None
            values = [
                self._text(argument).strip()
                for argument in (arguments.named_children if arguments else [])
                if argument.type == "value_argument"
            ]
            events.append(
                {
                    "event": {"expectUnreached": "expect_unreached"}.get(
                        event_name, event_name
                    ),
                    "args": values,
                }
            )
        return events

    def test_methods(
        self,
        name: str,
        abstract_methods: dict[str, list[str]] | None = None,
    ) -> list[str]:
        def inherited_tests(class_name: str, visiting: frozenset[str]) -> list[str]:
            if class_name in visiting:
                return [test for test, _ in self.classes_by_name[class_name].tests]
            info = self.classes_by_name[class_name]
            result = [test for test, _ in info.tests]
            parent = info.parent
            if parent in self.classes_by_name:
                result.extend(inherited_tests(parent, visiting | {class_name}))
            elif abstract_methods and parent in abstract_methods:
                result.extend(abstract_methods[parent])
            return list(dict.fromkeys(result))

        return (
            inherited_tests(name, frozenset()) if name in self.classes_by_name else []
        )

    def test_classes(
        self, abstract_methods: dict[str, list[str]] | None = None
    ) -> list[tuple[str, list[str]]]:
        result = []
        for item in self.classes:
            tests = self.test_methods(item.name, abstract_methods)
            if tests and not item.abstract:
                result.append((item.name, tests))
        return result

    def test_lines(self) -> dict[str, int]:
        return {name: line for item in self.classes for name, line in item.tests}

    def abstract_methods(self) -> tuple[dict[str, list[str]], dict[str, str | None]]:
        tests = {
            item.name: [name for name, _ in item.tests]
            for item in self.classes
            if item.abstract
        }
        parents = {item.name: item.parent for item in self.classes if item.abstract}
        return tests, parents


class KotlinSources:
    """Per-run parser and parsed-document cache, keyed by source text."""

    def __init__(self) -> None:
        self._parser = get_parser("kotlin")
        self._documents: dict[str, KotlinSource] = {}

    def get(self, text: str) -> KotlinSource:
        document = self._documents.get(text)
        if document is None:
            document = KotlinSource(text, self._parser)
            self._documents[text] = document
        return document
