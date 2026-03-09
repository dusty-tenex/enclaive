# Part 21: Guardrails Sidecar Architecture

## Overview

The security guard system runs as two components:

1. **Guardrails Sidecar** — a separate Docker container running the guardrails-ai validation server. Tamper-resistant (read-only filesystem, separate container, non-root user). Models loaded once at startup, warm for every request (~50ms per validation).

2. **Inline Fallback** — `scripts/security_guard.py` runs inside the sandbox when the sidecar is unavailable. Same detection logic (imports from `scripts/validators.py`), but tamper-vulnerable because the agent has Bash access.

```
┌─── Sandbox Container ──────────────┐    ┌─── Guardrails Sidecar ──────┐
│                                     │    │  (read_only: true)           │
│  Claude Agent                       │    │                              │
│    │ PreToolUse hook                │    │  guardrails-api server       │
│    ▼                                │    │  ├── SecretsPresent (Hub)    │
│  memory-guard.sh                    │    │  ├── GuardrailsPII (Hub)     │
│    ├── curl sidecar:8000  ──────────┼───►│  ├── ExfilDetector (custom)  │
│    │   ~50ms, tamper-resistant          │    │  ├── EncodingDetector        │
│    │                                │    │  ├── ForeignScriptDetector   │
│    └── OR python3 security_guard.py │    │  └── AcrosticDetector        │
│        (fallback if sidecar down)   │    │                              │
└─────────────────────────────────────┘    └──────────────────────────────┘
```

## Why a Sidecar?

**Tamper resistance.** The inline path runs inside the sandbox where the agent has Bash access. A prompt-injected agent could `rm security_guard.py` or `echo 'exit 0' > memory-guard.sh`. The sidecar is a separate container the agent cannot touch.

**Performance.** Every inline invocation spawns Python, imports guardrails, and loads ML models (~300-500ms cold start). The sidecar loads once and serves warm requests (~50ms).

**Fail-closed design.** Hook scripts use `jq '.validation_passed // false'` — if the sidecar returns anything unexpected, the hook blocks (not allows). Set `GUARDRAILS_REQUIRE_SIDECAR=1` to disable the inline fallback entirely.

## Guard Pipelines

Each mode has a named guard exposed at `POST /guards/{name}/validate`:

| Guard | Mode | Hub Validators | Custom Validators |
|-------|------|---------------|-------------------|
| `memory_guard` | Writes to CLAUDE.md, etc. | DetectJailbreak, UnusualPrompt, SecretsPresent, GuardrailsPII, DetectPII | EncodingDetector [escalated], AcrosticDetector |
| `exfil_guard` | Bash commands | SecretsPresent | ExfilDetector, EncodingDetector [escalated], ForeignScriptDetector, AcrosticDetector |
| `inbound_guard` | Content read from files/web | DetectJailbreak, UnusualPrompt | EncodingDetector, ForeignScriptDetector |
| `write_guard` | Code file writes | SecretsPresent, GuardrailsPII, DetectPII | AcrosticDetector |

## Single Source of Truth

All detection patterns and custom validator classes live in `scripts/validators.py`. Both `security_guard.py` (inline) and the sidecar's `config.py` import from it. The sidecar mounts it read-only via docker compose.

## Deployment

```bash
# Primary: docker compose
cp .env.example .env   # add ANTHROPIC_API_KEY, GUARDRAILS_TOKEN
docker compose up -d
docker compose exec sandbox claude

# Standalone (no sidecar, inline only)
./setup.sh ~/my-project
cd ~/my-project && claude
```

## Monitoring

- **Health:** `curl http://localhost:8000/health`
- **Audit logs:** Sidecar logs to `/var/log/guardrails/` (volume-mounted). Inline logs to `.audit-logs/security-guard.jsonl`.
- **Hub status:** Sidecar prints loaded validators at startup: `[guardrails-sidecar] Hub validators: ['secrets', 'pii', 'detect_pii', 'jailbreak', 'unusual']`

## Extending

Add validators to `config/guardrails-server/config.py`:

```python
from validators import _VALIDATORS
from guardrails import Guard, OnFailAction

# Add a new custom validator to the exfil guard
exfil_guard = exfil_guard.use(MyNewDetector(on_fail=OnFailAction.EXCEPTION))
```

Or add Hub validators:

```bash
guardrails hub install hub://guardrails/toxic_language
# Then import in config.py and add to the appropriate guard
```

## detect-secrets Limitations

The `SecretsPresent` Hub validator uses Yelp's `detect-secrets` library. While it has 30+ detector plugins, academic benchmarks (arXiv 2307.00714) show regex+entropy tools have systematic blind spots:

- **Missing patterns:** Database connection strings (postgres://), Bearer tokens in prose, multi-line private keys, short passwords, generic API keys without provider prefixes
- **Entropy miscalibration:** Short tokens and tokens with repetitive patterns fall below the entropy threshold
- **File type gaps:** Binary files, Jupyter notebooks, and non-standard config extensions may be skipped
- **Contextual blindness:** Cannot distinguish real secrets from examples, test fixtures, or revoked keys

Our mitigation: `validators.py` includes `CREDENTIAL_PATTERNS` that catch what `detect-secrets` misses (DB connection strings, JWTs, GitLab/npm/Slack-specific tokens). The `EncodingDetector` catches base64-encoded secrets. Both run alongside `detect-secrets` in the same Guard pipeline.
