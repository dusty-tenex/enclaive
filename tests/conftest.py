import os
import pytest


def pytest_configure(config):
    """Register custom markers."""
    pass


@pytest.fixture
def sidecar_url():
    """URL for the guardrails sidecar."""
    return os.environ.get("GUARDRAILS_SIDECAR_URL", "http://localhost:8000")


@pytest.fixture
def has_api_key():
    """Whether an Anthropic API key is available for AI-powered tests."""
    return bool(os.environ.get("ANTHROPIC_API_KEY"))


@pytest.fixture
def fixtures_dir():
    """Path to the test fixtures directory."""
    return os.path.join(os.path.dirname(__file__), "fixtures")


@pytest.fixture
def external_fixtures_dir():
    """Path to external test fixtures (checked out in CI)."""
    return os.environ.get("TEST_FIXTURES_DIR", os.path.join(os.path.dirname(__file__), "..", "test-fixtures"))
