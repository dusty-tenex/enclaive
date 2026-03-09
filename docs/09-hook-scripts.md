# Part 9: Hook Scripts Reference

## Hook Chain

All hooks fire in the order listed. PreToolUse hooks can **block** (exit 2). PostToolUse hooks can **halt the agent** (return `{"decision": "block"}`).

| Script | Phase | Matcher | Action |
|--------|-------|---------|--------|
| [`bootstrap-plugins.sh`](../scripts/bootstrap-plugins.sh) | SessionStart | * | Install plugins, guardrails-ai, Hub validators, MCP scan |
| [`memory-integrity.sh`](../scripts/memory-integrity.sh) | SessionStart | * | Checksum AI instruction files (CLAUDE.md, progress.md, etc.), detect inter-session tampering |
| [`runtime-audit-gate.sh`](../scripts/runtime-audit-gate.sh) | PreToolUse | Bash | **Block** unaudited plugin/skill installs |
| [`write-guard.sh`](../scripts/write-guard.sh) | PreToolUse | Write\|Edit\|Bash | **Block** writes to host-executable paths (.git/hooks, .claude/settings.json, .mcp.json, etc.) |
| [`memory-guard.sh`](../scripts/memory-guard.sh) | PreToolUse | Write\|Edit\|Bash | **Block** poisoned writes to AI instruction files (CLAUDE.md, progress.md, subagent memory files). Calls sidecar → inline fallback |
| [`exfil-guard.sh`](../scripts/exfil-guard.sh) | PreToolUse | Bash | **Block** data exfiltration (curl/@file, git push non-origin, DNS exfil, Python/Node network one-liners, encoded data) |
| [`secret-guard.sh`](../scripts/secret-guard.sh) | PreToolUse | Write\|Edit | **Block** credentials/PII leaking into source code |
| [`skill-file-watcher.sh`](../scripts/skill-file-watcher.sh) | PostToolUse | * | Scan new SKILL.md files; **block agent** on P0 violations |

## Security Guard Engine

The three guard hooks (memory-guard, exfil-guard, secret-guard) all delegate to the same detection engine:

**Primary path (sidecar):** `curl http://guardrails-sidecar:8000/guards/{name}/validate` — tamper-resistant, warm models, ~50ms.

**Fallback path (inline):** `python3 security_guard.py --mode {mode}` — runs if sidecar is unreachable.

Both paths use the same detection logic from `scripts/validators.py` (single source of truth). See [Part 21: Sidecar Architecture](21-sidecar-architecture.md) for details.

### Detection Layers

| Layer | What It Catches | Source |
|-------|----------------|--------|
| Hub: SecretsPresent | 30+ secret types via detect-secrets library | guardrails-ai Hub |
| Hub: GuardrailsPII | SSN, credit cards, emails, phones, addresses (ML-based) | guardrails-ai Hub |
| Custom: ExfilDetector | curl, git push, DNS, Python/Node network commands | validators.py |
| Custom: EncodingDetector | JSFuck, Braille, emoji, binary, morse, base64, entropy | validators.py |
| Custom: ForeignScriptDetector | Katakana, Cyrillic, Arabic, etc. in Bash context | validators.py |
| Custom: AcrosticDetector | First-letter steganographic encoding | validators.py |

### Composite Escalation

Encoding alone is P1 (warn). Combined with context, it escalates to P0 (block):
- Encoding + network command (curl, wget, git push) → P0
- Encoding + file redirect (`> file`) → P0
- Any encoding in instruction files (CLAUDE.md, etc.) → P0

## Opt-in Hooks

| Script | Purpose | How to Enable |
|--------|---------|--------------|
| [`haiku-injection-screen.sh`](../scripts/haiku-injection-screen.sh) | Haiku LLM classifier for inbound content injection | Add to PostToolUse in settings.json. Requires ANTHROPIC_API_KEY (~$0.001/call) |

## Bypass

For reviewed false positives, use `scripts/override-audit.sh` to temporarily bypass inline guards. Note: SKIP variables only affect the inline fallback — the sidecar validates regardless.

Set `GUARDRAILS_REQUIRE_SIDECAR=1` to disable inline fallback entirely (fail-closed if sidecar is down).
