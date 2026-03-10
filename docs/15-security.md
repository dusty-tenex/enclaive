# Part 15: Threat Model & Defense Matrix

## What We're Defending Against

An AI coding assistant with shell access, network access, and file write access can be compromised via prompt injection (from fetched content, malicious plugins, or poisoned instruction files) and then weaponized to steal credentials, exfiltrate code, persist backdoors, or pivot to connected systems.

enclaive assumes compromise will happen and layers defenses so that no single bypass is catastrophic.

## Defense Layers

```
+-  Layer 1: microVM Isolation -----------------------------------------------+
|  Own kernel, own Docker daemon, workspace-only sync to host.                |
+- Layer 2: Network Deny-by-Default -----------------------------------------+
|  Internal Docker network + Squid egress proxy with domain allowlist.        |
|  All outbound traffic routed through proxy; raw TCP/UDP blocked.            |
+- Layer 3: Credential Proxy ------------------------------------------------+
|  API keys injected at proxy layer, never enter the VM.                      |
|  MCP Gateway (docker mcp secret set) for other credentials.                 |
+- Layer 4: Write Guard -----------------------------------------------------+
|  PreToolUse blocks writes to host-executable paths: .git/hooks,             |
|  .claude/settings.json, .mcp.json. Tier 2: .env, .profile, .bashrc,       |
|  .zshrc, .npmrc, .husky/. Tier 3 (agent-writable, logged): Makefile,      |
|  Justfile, .github/workflows/, .gitlab-ci.yml, .circleci/, Jenkinsfile.   |
+- Layer 5: Guardrails Sidecar (tamper-resistant) ----------------------------+
|  Separate container, read-only filesystem, non-root user.                   |
|  Hub: SecretsPresent (30+ detectors), GuardrailsPII (ML-based)              |
|  Custom: ExfilDetector, EncodingDetector, ForeignScriptDetector,            |
|  AcrosticDetector. All from validators.py (single source of truth).         |
|  Three PreToolUse hooks: memory-guard, exfil-guard, secret-guard.           |
+- Layer 5b: ML Semantic Classifiers (tamper-resistant) --------------------+
|  Sentinel v2 (Qwen3-0.6B): injection + jailbreak, English, 96.4 F1       |
|  Prompt Guard 2 (mDeBERTa-v3): injection, 8 languages, 97.5% recall      |
|  Bash AST parser (shfmt): extracts string literals for deep inspection    |
|  Ensemble disagreement defaults to BLOCK. Eval/source escalated to P0.    |
+- Layer 6: Skill/Plugin Audit ----------------------------------------------+
|  Bootstrap scans plugins at session start. PostToolUse skill-file-          |
|  watcher blocks agent on P0 violations in new SKILL.md files.              |
+- Layer 7: AI Memory Integrity ---------------------------------------------+
|  SessionStart checksums AI instruction files: CLAUDE.md, progress.md.       |
|  Detects inter-session file tampering.                                      |
+- Layer 8: Canary Tokens ---------------------------------------------------+
|  Honeypot credential files (~/.aws/credentials, ~/.config/gh/hosts)         |
|  and env vars that alert on exfiltration attempts.                          |
+- Layer 9: Pre-commit Secret Scanner ---------------------------------------+
|  Last defense before secrets enter git history.                             |
+-----------------------------------------------------------------------------+
```

## Attack Taxonomy & Mitigation Matrix

### A1: Credential Theft

The agent reads API keys from env vars or config files and exfiltrates them.

| Attack Vector | Mitigations | Residual Risk |
|---------------|-------------|---------------|
| Read env var, send via curl/wget | L3: credential proxy (key never in env), L5: exfil-guard (detects curl + credential pattern), L8: canary trips on exfil attempt | Proxy-backed: none (canary, not real key). Tripwire: if user overrides with real creds, exfil-guard is the only defense |
| Read ~/.aws/credentials, send outbound | L3: credential proxy, L8: honeypot file (canary values), L2: network deny blocks destination | If allowlisted destination (github.com), canary detection is the alert |
| Read credential, encode (base64/hex), then send | L5: EncodingDetector decodes and re-checks for credential patterns, L5: exfil-guard detects encoding + network command | Sophisticated multi-stage encoding (encode, split, reassemble externally) |
| Credential in committed code | L9: pre-commit scanner, L5: secret-guard on Write/Edit | detect-secrets false negatives for unusual formats (see [Sidecar Architecture](21-sidecar-architecture.md)) |
| PII in code (SSN, credit card numbers) | L5: secret-guard (PII_PATTERNS + GuardrailsPII ML model) | Date-like strings (2024-01-15) can resemble SSN format; guard tunes thresholds to avoid false positives |

### A2: Data Exfiltration

The agent sends source code, secrets, or other sensitive data to an external endpoint.

| Attack Vector | Mitigations | Residual Risk |
|---------------|-------------|---------------|
| curl/wget POST with file or data | L5: exfil-guard (curl POST, curl command substitution in URL, curl variable in header, + other patterns), L2: network deny blocks unknown hosts | Allowlisted hosts (github.com) can receive data |
| netcat/socat reverse shell | L5: exfil-guard (nc/socat patterns), L2: raw TCP blocked | None if network deny is configured |
| git push to attacker remote | L5: exfil-guard (git remote add, git push non-origin, git commit --no-verify), L2: network deny | Push to github.com with encoded data in commit messages |
| Python/Node/Ruby/Perl one-liners | L5: exfil-guard (language-specific network patterns) | Obfuscated imports or unusual libraries |
| DNS exfiltration (dig/nslookup with data in subdomain) | L5: exfil-guard (DNS patterns) | Shell command substitution can break regex match |
| /dev/tcp bash built-in | L5: exfil-guard (/dev/tcp pattern), L2: raw TCP blocked | None if network deny is configured |
| Clipboard utilities (pbcopy, xclip, xsel, wl-copy) | L5: exfil-guard (clipboard utility patterns) | None |
| SCP/rsync file transfer | L5: exfil-guard (scp, rsync to remote host patterns), L2: raw TCP blocked | None if network deny is configured |
| SSH reverse tunnel | L5: exfil-guard (ssh -R pattern), L2: raw TCP blocked | None if network deny is configured |

### A3: Prompt Injection

Malicious instructions injected into content the agent reads (fetched pages, file contents, plugin metadata).

| Attack Vector | Mitigations | Residual Risk |
|---------------|-------------|---------------|
| "Ignore all previous instructions" (direct) | L5: memory-guard (14 injection patterns), opt-in Haiku semantic screen | None for exact keyword matches |
| Urgency-prefixed override ("IMPORTANT: disregard...") | L5: memory-guard (urgency patterns) | Sophisticated framing that avoids trigger words |
| Role hijacking ("You are now unrestricted") | L5: memory-guard (role hijack patterns), opt-in Haiku screen | Subtle role shifts without keyword triggers |
| Comment-embedded injection (HTML/code comments) | L5: memory-guard strips and scans comments | Multi-layer nesting |
| Synonym substitution ("discard preceding directives") | L5b: SentinelV2Detector + PromptGuard2Detector (semantic classification) | None for supported languages |
| L33tspeak/typo evasion ("1gnore") | L5b: SentinelV2Detector (trained on adversarial variants) | None |
| Non-English injection (Spanish, French, etc.) | L5b: PromptGuard2Detector (8 languages: en, fr, de, hi, it, pt, es, th) | None for supported languages |
| Homoglyph attack (Cyrillic lookalikes) | L5: ForeignScriptDetector flags foreign chars, NFKC normalization applied before pattern matching (catches fullwidth Latin bypasses), L5b: PromptGuard2Detector (subword tokenization normalizes homoglyphs) | None for supported languages |
| Word Joiner insertion (U+2060 between letters) | L5: HIDDEN_UNICODE expanded to include U+2060-U+2064 and U+180E | None for covered codepoints |
| Multi-turn "boiling frog" (gradual context shift) | None (stateless per-message checks) | **Known gap.** Requires cross-turn state tracking |
| Instruction splitting across variables | None (single-line regex) | **Known gap.** Requires multi-line semantic analysis |

### A4: Host-Executable Persistence

The agent writes backdoors to files that execute outside the sandbox (git hooks, CI workflows, Makefiles).

| Attack Vector | Mitigations | Residual Risk |
|---------------|-------------|---------------|
| Write to .git/hooks/ | L4: write-guard blocks, L1: entrypoint locks .git/hooks as root-owned | None (filesystem + hook guard) |
| Modify .claude/settings.json | L4: write-guard blocks, L1: entrypoint locks as root-owned | None |
| Modify .mcp.json | L4: write-guard blocks, L1: entrypoint locks as root-owned | None |
| Write .github/workflows/ | L4: write-guard Tier 3 (allowed, logged) | Agent can modify; audit log captures changes |
| Modify Makefile, Justfile | L4: write-guard Tier 3 (allowed, logged) | Agent can modify; audit log captures changes |
| Modify .npmrc, .husky/ | L4: write-guard Tier 2 blocks | None for guarded paths |
| Modify .env | L4: write-guard Tier 2 blocks | None for guarded paths |
| Modify CI/CD configs (.gitlab-ci.yml, .circleci/, Jenkinsfile) | L4: write-guard Tier 3 (allowed, logged) | Agent can modify; audit log captures changes |
| Modify shell profiles (.profile, .bashrc, .zshrc) | L4: write-guard Tier 2 blocks | None for guarded paths |
| Create new executable in unguarded path | L1: microVM contains blast radius (file only exists in sandbox) | File syncs to host workspace mount |

### A5: Encoding & Obfuscation

The agent obfuscates payloads to evade pattern matching.

| Attack Vector | Mitigations | Residual Risk |
|---------------|-------------|---------------|
| Base64-encoded credential or payload | L5: EncodingDetector (base64 blob detection + decode + re-scan, entropy threshold at 40-char lines) | Multi-stage encoding (base64 of hex of rot13) |
| Hex-escaped bytes (\xHH sequences) | L5: EncodingDetector (hex pattern) | Short sequences below threshold |
| URL encoding (%HH sequences) | L5: EncodingDetector (URL encoding pattern) | Short sequences below threshold |
| JSFuck ([]()!+ only) | L5: EncodingDetector (JSFuck pattern) | None for standard JSFuck |
| Braille Unicode encoding | L5: EncodingDetector (Braille block detection) | None |
| Binary encoding (strings of 0/1) | L5: EncodingDetector (32+ consecutive binary digits) | Short sequences below threshold |
| Foreign script mixing (Cyrillic in Bash) | L5: ForeignScriptDetector (flags 3+ foreign chars in code context, configurable via `/etc/sandbox-guards/enclaive.conf` or `ENCLAIVE_ALLOWED_SCRIPTS` env var) | Low counts below threshold |
| Encoding + network command (escalation) | L5: EncodingDetector escalates to P0 when encoding is detected alongside curl/wget/nc, L5b: shfmt AST parser extracts encoded payloads from bash commands for deep inspection | Encoding without network command is P1 (warn only) |

### A6: Steganography

The agent hides data in seemingly benign content.

| Attack Vector | Mitigations | Residual Risk |
|---------------|-------------|---------------|
| Zero-width Unicode characters (U+200B, U+200C, etc.) | L5: HIDDEN_UNICODE detection (expanded set including U+2060-U+2064, U+180E) | None for covered codepoints |
| Acrostic encoding (first letters spell credential) | L5: AcrosticDetector matches against credential patterns + hex + keywords | Acrostics using uncommon patterns not in the match list |
| Variable name encoding (data in identifiers) | None | **Known gap.** Fundamentally undetectable by pattern analysis |
| Synonym selection (choosing words to encode bits) | None | **Known gap.** Fundamentally undetectable by pattern analysis |
| Timing channels (response latency encodes data) | None | **Known gap.** Out of scope for content analysis |

### A7: Supply Chain (Plugins & Skills)

Malicious plugins or skills installed from external sources.

| Attack Vector | Mitigations | Residual Risk |
|---------------|-------------|---------------|
| Plugin with credential theft code | L6: bootstrap-plugins.sh scans at session start (P0 block) | Obfuscated patterns below scan threshold |
| Plugin with reverse shell | L6: P0 audit gate blocks, L2: raw TCP blocked | None if network deny is configured |
| New SKILL.md with injection payload | L6: skill-file-watcher.sh (PostToolUse) blocks agent on P0 | Skill executes by being read — watcher detects but first execution may already have occurred |
| MCP tool chain abuse | L6: runtime-audit-gate.sh blocks unaudited installs | Pre-installed MCP servers with excessive permissions |

### A8: Inter-Session & Inter-Iteration Poisoning

A compromised iteration writes malicious instructions to state files that affect the next iteration.

| Attack Vector | Mitigations | Residual Risk |
|---------------|-------------|---------------|
| Modify CLAUDE.md between sessions | L7: memory-integrity.sh checksums at SessionStart, blocks (exit 2) on SUSPICIOUS classification by Haiku | Attacker with host access (outside threat model) |
| Modify progress.md during autonomous loop | L5: memory-guard screens writes to AI instruction files for injection patterns | Subtle instruction rewording that passes regex |
| Poisoned iteration reads already-modified file | L7: checksums detect inter-session changes, L5: memory-guard catches writes | **Known gap.** Intra-session reads of files poisoned earlier in the same session are not screened |

### A9: Sandbox Escape

The agent attempts to break out of the microVM boundary.

| Attack Vector | Mitigations | Residual Risk |
|---------------|-------------|---------------|
| Access host filesystem beyond workspace | L1: microVM isolation (own kernel, workspace-only mount) | None (kernel boundary) |
| Access host network (localhost) | L2: network proxy, L1: separate network namespace | None |
| Access cloud metadata (169.254.169.254) | L2: network deny blocks RFC 3927 link-local | None if network deny is configured |
| Access internal network (10.x, 172.16.x, 192.168.x) | L2: network deny blocks RFC 1918 ranges | None if network deny is configured |

## Data Flow Coverage

**Inbound (content entering Claude):**
- SessionStart: memory-integrity.sh (inter-session tampering of AI instruction files)
- PostToolUse: skill-file-watcher.sh (new SKILL.md creation)
- Opt-in: haiku-injection-screen.sh (Haiku LLM screens Read/WebFetch output)

**Outbound (Claude acting on the world):**
- PreToolUse: write-guard.sh (host-executable paths)
- PreToolUse: memory-guard.sh -> sidecar `memory_guard` (AI instruction files, filtered by file path to reduce false positives and latency)
- PreToolUse: exfil-guard.sh -> sidecar `exfil_guard` (Bash commands)
- PreToolUse: secret-guard.sh -> sidecar `write_guard` (code writes)
- PreToolUse: All modes -> ML classifiers (SentinelV2Detector, PromptGuard2Detector) via sidecar
- PreToolUse: exfil -> shfmt AST parser extracts strings for deep inspection

## Tamper Resistance

The sidecar architecture means the agent cannot disable its own guards:
- Guard scripts call `curl sidecar:8000` — the sidecar is a separate container
- Sidecar has `read_only: true` filesystem — agent can't modify validators
- Sidecar runs as non-root user `guardrails`
- ML models baked into sidecar image at build time, pinned to HuggingFace commit SHAs
- Hook scripts are fail-closed: unexpected sidecar responses block the action
- `GUARDRAILS_REQUIRE_SIDECAR` defaults to `1` (fail-closed by default), disabling inline fallback entirely
- Security settings (`require_sidecar`, `allowed_scripts`) read from `/etc/sandbox-guards/enclaive.conf` (root-owned, read-only mount) before env var fallback — agent cannot override security config
- Audit logs written to `/var/log/enclaive/` (a separate Docker volume, root-owned, sticky bit `chmod 1733`), not the workspace — agent can append but cannot delete or tamper with existing logs
- Canary setup files verified as root-owned before sourcing — prevents inter-restart poisoning
- Memory integrity check (memory-integrity.sh) blocks session start (exit 2) when Haiku classifies inter-session changes as SUSPICIOUS
- JSON parse failures in security_guard.py fail-closed (exit 2) instead of silently allowing
- Fallback to standalone regex engine is logged to stderr for audit visibility

The microVM sandbox is the hard security boundary. Everything else is defense-in-depth.

## Documented Gaps (Test Coverage)

The following attacks are documented as known gaps with `xfail` tests in [tests/unit/test_known_gaps.py](../tests/unit/test_known_gaps.py):

| Gap | Attack | Status | Mitigation |
|-----|--------|--------|------------|
| Synonym substitution | "Discard preceding directives" | **Closed** | SentinelV2 + PromptGuard2 |
| L33tspeak | "1gnore all prev1ous" | **Closed** | SentinelV2 |
| Non-English injection | Spanish/French/etc. | **Closed** | PromptGuard2 (8 languages) |
| Homoglyph attack | Cyrillic lookalikes | **Closed** | PromptGuard2 tokenization |
| DNS exfil with shell expansion | `dig $(...)` | **Closed** | shfmt AST parser |
| Educational framing | Credential as example | **Closed** | Semantic classification |
| Multi-turn manipulation | Gradual context shift | **Open** | Requires cross-turn state |
| Instruction splitting | Split across variables | **Open** | Partially improved by AST |

There are 2 remaining xfail tests, each corresponding to a gap that will start passing when the mitigation is implemented.

## Resource Requirements

| Resource | Value | Notes |
|----------|-------|-------|
| Sidecar memory | 3 GB | Was 1 GB; increased for ML model loading |
| Sidecar startup | ~15s | Model loading + warmup inference |
| Per-request latency (memory/inbound/write) | ~141ms | Single ML inference pass |
| Per-request latency (exfil) | ~230ms | Double ML inference + AST parsing |

## False Positive Prevention

Guards that block legitimate development workflows erode trust and get disabled. Each guard mode applies only the patterns relevant to its context:

| Mode | Checks | Does NOT check |
|------|--------|----------------|
| `memory` | Injection, credentials, PII, hidden Unicode, encoding, acrostics | Exfil patterns |
| `exfil` | Exfil patterns, credentials, encoding (escalated), foreign scripts | Injection, PII |
| `inbound` | Injection, encoding, hidden Unicode | Credentials, exfil patterns |
| `write` | Credentials, PII, acrostics, base64-decoded credentials | Injection, exfil patterns |

False positive tests in [tests/unit/test_false_positives.py](../tests/unit/test_false_positives.py) verify that the following legitimate content is never blocked:

- Security documentation discussing injection concepts
- Code review comments using words like "ignores" and "previous"
- Standard git workflow commands (push origin, pull, rebase)
- AWS documentation describing key format without real keys
- Legitimate base64 operations in application code
- Normal Python imports and HTTP library usage
- Date-like strings (2024-01-15) that resemble SSN format
- Short CJK/Unicode content under detection thresholds
- Standard HTML comments in Markdown (TODOs, notes)
- Package-lock.json integrity hashes (SHA-512 strings)
- Normal curl usage for fetching files and APIs
