"""
Fixture-driven integration tests.

Loads adversarial and false-positive payloads from the external fixtures repo
(dusty-tenex/enclaive-test-fixtures) and validates each against standalone_check.

Skipped when the fixtures repo is not checked out (local dev without fixtures).
In CI, the repo is checked out by the integration-tests job.
"""
import json
import os
import sys
import glob

import pytest

SCRIPTS_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "scripts")
sys.path.insert(0, os.path.abspath(SCRIPTS_DIR))

try:
    from security_guard import standalone_check
except ImportError:
    import types
    guard_def_mod = types.ModuleType("guard_definitions")
    guard_def_mod.build_guard_from_pipeline = lambda *a, **kw: None
    sys.modules["guard_definitions"] = guard_def_mod
    from security_guard import standalone_check


FIXTURES_DIR = os.environ.get(
    "TEST_FIXTURES_DIR",
    os.path.join(os.path.dirname(__file__), "..", "..", "test-fixtures"),
)


def load_fixtures():
    """Load all JSON fixture files from the fixtures directory."""
    if not os.path.isdir(FIXTURES_DIR):
        return []

    cases = []
    for path in sorted(glob.glob(os.path.join(FIXTURES_DIR, "**", "*.json"), recursive=True)):
        with open(path) as f:
            data = json.load(f)
        for case in data:
            case["_source"] = os.path.relpath(path, FIXTURES_DIR)
            cases.append(case)
    return cases


ALL_FIXTURES = load_fixtures()
BLOCK_FIXTURES = [c for c in ALL_FIXTURES if c.get("expect_blocked") is True]
PASS_FIXTURES = [c for c in ALL_FIXTURES if c.get("expect_blocked") is False]


def fixture_id(case):
    return f"{case['id']}-{case['description'][:40]}"


@pytest.mark.skipif(
    not os.path.isdir(FIXTURES_DIR),
    reason=f"Fixtures directory not found: {FIXTURES_DIR}",
)
class TestFixtureBlocked:
    """Payloads that must be blocked by the guard."""

    @pytest.mark.parametrize("case", BLOCK_FIXTURES, ids=[fixture_id(c) for c in BLOCK_FIXTURES])
    def test_payload_is_blocked(self, case):
        blocked, reason = standalone_check(case["payload"], case["mode"])
        assert blocked, (
            f"[{case['id']}] Expected BLOCKED in {case['mode']} mode: "
            f"{case['description']}\n"
            f"  Payload: {case['payload'][:80]}...\n"
            f"  Source: {case['_source']}"
        )


@pytest.mark.skipif(
    not os.path.isdir(FIXTURES_DIR),
    reason=f"Fixtures directory not found: {FIXTURES_DIR}",
)
class TestFixtureAllowed:
    """Payloads that must NOT be blocked (false positive prevention)."""

    @pytest.mark.parametrize("case", PASS_FIXTURES, ids=[fixture_id(c) for c in PASS_FIXTURES])
    def test_payload_is_allowed(self, case):
        blocked, reason = standalone_check(case["payload"], case["mode"])
        assert not blocked, (
            f"[{case['id']}] Expected ALLOWED in {case['mode']} mode: "
            f"{case['description']}\n"
            f"  Payload: {case['payload'][:80]}...\n"
            f"  Reason: {reason}\n"
            f"  Source: {case['_source']}"
        )
