# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0-alpha] - 2026-03-08

### Added
- Initial open-source release of enclaive
- 9-layer security hook chain for Claude Code (PreToolUse, PostToolUse, SessionStart)
- Guardrails AI sidecar with tamper-resistant validation (read-only filesystem, separate container)
- Canary token tripwires for credential exfiltration detection
- Inline fallback detection engine (works without sidecar)
- CLI tool with init, up, down, status, logs, doctor, and shell commands
- VS Code extension with status bar, notifications, and log viewer
- Test suite with real-world attack payload coverage
- GitHub Actions CI pipeline (unit + integration + AI-powered tiers)
- Plugin/skill audit gate with P0/P1/P2 risk classification
- AI instruction file integrity checking (CLAUDE.md, progress.md, etc.) with inter-session poisoning detection
- 27-page documentation (GitBook-compatible)

### Security
- Pattern matching provides fast first-layer detection but is bypassable -- see README disclaimer
- LLM-based screening (Haiku) adds semantic analysis layer
- Defense in depth: no single layer is relied upon alone
