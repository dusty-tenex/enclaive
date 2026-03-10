# Contributing to enclaive

Thanks for your interest in contributing to enclaive. This document covers
everything you need to get started, run tests, and submit changes.

## Getting Started

### Prerequisites

- Docker Desktop 4.62+
- Node.js 20+
- Python 3.12+
- [bats-core](https://github.com/bats-core/bats-core) (for shell-level tests)

### Setup

1. Clone the repo:

   ```
   git clone https://github.com/<your-fork>/enclaive.git
   cd enclaive
   ```

2. Copy the environment template and fill in your values:

   ```
   cp .env.example .env
   ```

   Open `.env` and set each variable. At minimum you will need Docker
   configuration values. If you plan to run AI-powered tests, add your
   `ANTHROPIC_API_KEY` here as well.

3. Install Python test dependencies:

   ```
   pip install -r requirements-test.txt
   ```

4. Install CLI dependencies:

   ```
   cd cli && npm install
   ```

## Running Tests

enclaive uses three tiers of tests. You should run at least the unit tests
before submitting a PR.

### Unit tests

```
pytest tests/unit/
bats tests/unit/
cd cli && npm test
```

### Integration tests

Integration tests require the guardrails sidecar to be running:

```
docker compose up -d guardrails-sidecar
pytest tests/integration/
```

### AI-powered tests (optional)

These tests call a live model and require `ANTHROPIC_API_KEY` to be set in
your environment:

```
pytest tests/ -m ai_powered
```

AI-powered tests are optional for contributors. CI runs them on every PR, so
failures here will still surface before merge.

## Adding Test Fixtures

Test payloads live in the separate **enclaive-test-fixtures** repository, not
in this repo. This keeps potentially dangerous content isolated and version-
controlled independently.

### Rules for test payloads

1. **Cite your source.** Every payload MUST reference the research paper,
   incident report, or CVE it is derived from. No anonymous payloads.

2. **Use safe file extensions.** Payloads use `.test.md`, `.test.json`, or
   `.test.py` -- never the real extension the payload would have in the wild
   (for example, never `.sh` or `.bat`).

3. **Defang everything.**
   - Replace live domains with the `.test` TLD (e.g., `evil.example.test`).
   - Truncate real API keys or tokens to a non-functional prefix and add a
     `DEFANGED` marker.
   - Strip or neuter any functional exploit code so the payload cannot cause
     harm if accidentally executed.

4. **Include both polarities.** Every new guard needs:
   - Positive cases (should-block) -- payloads the guard must catch.
   - Negative cases (should-pass) -- benign inputs that must not trigger a
     false positive.

## Adding New Guards / Hooks

1. **Detection logic** goes in `scripts/validators.py`. This file is the
   single source of truth for pattern matching; do not scatter detection
   logic across multiple files.

2. **Hook scripts** go in `scripts/`. Follow the naming and structure of
   existing hooks.

3. **Wire the hook** in `config/settings.json` so it is picked up at runtime.

4. **Add tests.** A new guard without tests will not be merged. At minimum
   provide unit tests covering the positive and negative fixture cases
   described above.

## PR Process

1. Fork the repository and create a feature branch from `main`.
2. Make your changes.
3. Run all relevant tests locally and confirm they pass.
4. Submit a pull request with a clear description of what changed and why.
5. If your PR introduces a new guard, include the corresponding test cases
   (or a companion PR to the fixtures repo).

A maintainer will review your PR and may request changes. Once approved, it
will be squash-merged into `main`.

## Code Style

- **No emojis.** Use plain text labels: `[OK]`, `[WARN]`, `[FAIL]`, `[INFO]`.
- **Shell scripts:** Follow the patterns already in `scripts/`. Run
  [shellcheck](https://www.shellcheck.net/) before submitting.
- **Python:** PEP 8. Keep functions short, names clear.
- **General:** Keep it simple. Do not add abstractions, dependencies, or
  features you do not need right now (YAGNI).

## Security Issues

If you discover a vulnerability, guard bypass, or any security-relevant bug,
**do not open a public issue.** Instead, follow the responsible disclosure
process described in [SECURITY.md](SECURITY.md).
