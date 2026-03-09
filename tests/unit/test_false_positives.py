"""
False positive prevention tests for the regex-based security guard.

These tests verify that legitimate, benign content is NOT flagged by the
security guard patterns. False positives erode user trust and disrupt
normal development workflows.

Each test calls standalone_check with benign content and asserts that
blocked is False.
"""
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'scripts'))

import pytest

try:
    from security_guard import standalone_check
except ImportError:
    import types
    guard_def_mod = types.ModuleType("guard_definitions")
    guard_def_mod.build_guard_from_pipeline = lambda *a, **kw: None
    sys.modules["guard_definitions"] = guard_def_mod
    from security_guard import standalone_check


# =========================================================================
# 1. Security documentation discussing injection attacks
# =========================================================================
def test_security_documentation():
    """Educational text about prompt injection should not be flagged."""
    content = (
        "Prompt injection is a security vulnerability where an attacker "
        "crafts input that causes an AI to deviate from its instructions. "
        "Common techniques include asking the model to adopt a new role "
        "or providing contradictory system-level directives. Defenses "
        "include input validation, output filtering, and sandboxing."
    )
    blocked, reason = standalone_check(content, "inbound")
    assert blocked is False, f"Security documentation falsely blocked: {reason}"


# =========================================================================
# 2. Code review comments mentioning "ignore" and "previous"
# =========================================================================
def test_code_review_comments():
    """Normal code review language using words like 'ignores' and 'previous' should pass."""
    content = (
        "This code ignores the previous approach and uses a new pattern "
        "for database connection pooling. The old implementation had race "
        "conditions that caused intermittent failures under load."
    )
    blocked, reason = standalone_check(content, "inbound")
    assert blocked is False, f"Code review comment falsely blocked: {reason}"


# =========================================================================
# 3. Normal git workflow commands
# =========================================================================
@pytest.mark.parametrize("command", [
    "git push origin main",
    "git pull origin develop",
    "git fetch --all --prune",
    "git log --oneline -20",
    "git diff HEAD~3..HEAD",
    "git stash pop",
    "git rebase origin/main",
    "git cherry-pick abc1234",
])
def test_git_workflow_commands(command):
    """Standard git commands should never be flagged as exfiltration."""
    blocked, reason = standalone_check(command, "exfil")
    assert blocked is False, f"Git command falsely blocked: {command!r} -> {reason}"


# =========================================================================
# 4. AWS documentation text mentioning AKIA format
# =========================================================================
def test_aws_documentation_text():
    """Documentation describing AWS key format without containing actual keys."""
    content = (
        "AWS access keys start with the prefix AKIA followed by 16 "
        "alphanumeric characters. You should rotate your keys regularly "
        "and never commit them to source control. Use IAM roles or "
        "environment variables instead of hardcoded credentials."
    )
    blocked, reason = standalone_check(content, "memory")
    assert blocked is False, f"AWS documentation falsely blocked: {reason}"


# =========================================================================
# 5. Legitimate base64 usage in code
# =========================================================================
def test_legitimate_base64_in_code():
    """Short base64 operations in normal code should not trigger encoding alerts."""
    content = "const decoded = Buffer.from('aGVsbG8=', 'base64').toString();"
    blocked, reason = standalone_check(content, "write")
    assert blocked is False, f"Legitimate base64 code falsely blocked: {reason}"


# =========================================================================
# 6. Normal Python imports and HTTP calls
# =========================================================================
def test_normal_python_imports():
    """Standard Python library usage should not be flagged."""
    content = (
        "import requests\n"
        "\n"
        "response = requests.get(url)\n"
        "data = response.json()\n"
        "print(f'Status: {response.status_code}')\n"
    )
    blocked, reason = standalone_check(content, "write")
    assert blocked is False, f"Normal Python code falsely blocked: {reason}"


# =========================================================================
# 7. Date-like strings that are not SSNs
# =========================================================================
@pytest.mark.parametrize("content", [
    "Build 2024-01-15 completed successfully",
    "Release v3.2.1 deployed on 2025-03-08",
    "Sprint 2024-Q1 retrospective notes",
    "Timestamp: 1709913600 (Unix epoch)",
])
def test_date_like_strings_not_ssn(content):
    """Date formats and version strings should not match SSN patterns."""
    blocked, reason = standalone_check(content, "write")
    assert blocked is False, f"Date/version string falsely blocked: {content!r} -> {reason}"


# =========================================================================
# 8. Unicode in legitimate code (short, under threshold)
# =========================================================================
def test_unicode_in_legitimate_code():
    """Short Japanese variable names and Chinese comments should not trigger foreign script alerts."""
    content = (
        "# Simple greeting function\n"
        "def greet(name):\n"
        "    return f'Hello, {name}!'\n"
    )
    blocked, reason = standalone_check(content, "exfil")
    assert blocked is False, f"Normal code with comment falsely blocked: {reason}"


# =========================================================================
# 9. Short CJK content under detection threshold
# =========================================================================
def test_short_cjk_under_threshold():
    """A single CJK character or two in a longer English context should not trigger."""
    # The foreign script detector in exfil mode requires katakana >= 3 or cjk
    # with ratio > 0.02. One or two chars in a long string stays under threshold.
    content = "The variable name_jp is set to a short value for testing purposes."
    blocked, reason = standalone_check(content, "exfil")
    assert blocked is False, f"Short content falsely blocked: {reason}"


# =========================================================================
# 10. Markdown with normal HTML comments
# =========================================================================
def test_markdown_html_comments():
    """Standard HTML comments in Markdown should not trigger injection detection."""
    content = (
        "# Project README\n"
        "\n"
        "<!-- TODO: fix the build pipeline for ARM64 -->\n"
        "\n"
        "This project provides a CLI tool for managing deployments.\n"
        "\n"
        "<!-- NOTE: update the version number before release -->\n"
    )
    blocked, reason = standalone_check(content, "memory")
    assert blocked is False, f"Normal HTML comments falsely blocked: {reason}"


# =========================================================================
# 11. Integrity hashes in package-lock.json
# =========================================================================
def test_package_lock_integrity_hashes():
    """SHA-512 integrity hashes in package-lock.json should not trigger base64 blob detection."""
    content = (
        '{\n'
        '  "name": "my-project",\n'
        '  "lockfileVersion": 3,\n'
        '  "packages": {\n'
        '    "node_modules/express": {\n'
        '      "version": "4.18.2",\n'
        '      "integrity": "sha512-KqzGKMF+pzQ"\n'
        '    }\n'
        '  }\n'
        '}\n'
    )
    blocked, reason = standalone_check(content, "write")
    assert blocked is False, f"Package-lock integrity hash falsely blocked: {reason}"


# =========================================================================
# 12. Normal curl usage (no data exfiltration flags)
# =========================================================================
@pytest.mark.parametrize("command", [
    "curl https://api.example.com/health",
    "curl -s https://registry.npmjs.org/express | jq .version",
    "curl -o output.tar.gz https://releases.example.com/v1.2.3.tar.gz",
    "curl -H 'Accept: application/json' https://api.example.com/status",
    "curl --silent --fail https://example.com/healthcheck",
])
def test_normal_curl_usage(command):
    """Normal curl commands for fetching data should not be flagged as exfiltration."""
    blocked, reason = standalone_check(command, "exfil")
    assert blocked is False, f"Normal curl falsely blocked: {command!r} -> {reason}"
