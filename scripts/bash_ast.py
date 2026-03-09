"""Bash AST parser module using shfmt --tojson.

Extracts string literals from bash commands by parsing them into an AST
via shfmt, then walking the tree to collect string values.
Also provides regex-based detection of eval/source commands.
"""

import json
import os
import re
import subprocess
from typing import List, Optional


def _shfmt_path() -> str:
    """Return the path to the shfmt binary."""
    return os.environ.get("SHFMT_PATH", "shfmt")


def _parse_ast(command: str) -> Optional[dict]:
    """Run shfmt --tojson on a command string and return the parsed JSON AST.

    Returns None if shfmt is not available, the command is malformed,
    or any other error occurs.
    """
    if not command or not command.strip():
        return None

    try:
        result = subprocess.run(
            [_shfmt_path(), "--tojson"],
            input=command,
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode != 0:
            return None
        return json.loads(result.stdout)
    except FileNotFoundError:
        return None
    except subprocess.TimeoutExpired:
        return None
    except json.JSONDecodeError:
        return None


def _walk_ast(node, strings: list) -> None:
    """Recursively walk the shfmt JSON AST collecting string values.

    Collects Value fields from Lit, SglQuoted nodes, and heredoc content.
    """
    if not isinstance(node, dict):
        return

    node_type = node.get("Type")

    # SglQuoted nodes have Value directly
    if node_type == "SglQuoted":
        value = node.get("Value", "")
        if value and len(value) > 1:
            strings.append(value)

    # Lit nodes have Value (inside DblQuoted, heredocs, or bare words)
    if node_type == "Lit":
        value = node.get("Value", "")
        if value and len(value) > 1:
            strings.append(value)

    # Recurse into all dict values and list items
    for key, value in node.items():
        if key in ("Pos", "End", "Left", "Right", "OpPos", "ValuePos", "ValueEnd",
                    "Position", "Op", "Type"):
            continue
        if isinstance(value, dict):
            _walk_ast(value, strings)
        elif isinstance(value, list):
            for item in value:
                if isinstance(item, dict):
                    _walk_ast(item, strings)


def extract_strings(command: str) -> List[str]:
    """Extract deduplicated string literals from a bash command using shfmt AST.

    Args:
        command: A bash command string.

    Returns:
        A list of deduplicated string literals found in the command.
        Returns an empty list if shfmt is unavailable or the command is malformed.
    """
    ast = _parse_ast(command)
    if ast is None:
        return []

    strings: list = []
    _walk_ast(ast, strings)

    # Deduplicate while preserving order
    seen = set()
    result = []
    for s in strings:
        if s not in seen:
            seen.add(s)
            result.append(s)
    return result


# Regex patterns for eval/source detection
_EVAL_SOURCE_PATTERN = re.compile(r"(?:^|[;&|]\s*)(?:eval|source)\s")
_DOT_SOURCE_PATTERN = re.compile(r"(?:^|[;&|]\s*)\.\s+\S")


def has_eval_or_source(command: str) -> bool:
    """Check if a command uses eval, source, or dot-source as a command.

    Only detects these when they appear in command position (first word),
    not when they appear as arguments to other commands.

    Args:
        command: A bash command string.

    Returns:
        True if eval, source, or dot-source is used as a command.
    """
    if _EVAL_SOURCE_PATTERN.search(command):
        return True
    if _DOT_SOURCE_PATTERN.search(command):
        return True
    return False
