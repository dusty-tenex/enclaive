# Semantic Security Layer + Bash AST Parser — Design

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add ML-based injection/jailbreak classifiers and a bash AST parser to close 6 of 8 known detection gaps documented in `tests/unit/test_known_gaps.py`.

**Architecture:** Two transformer models (Sentinel v2, Prompt Guard 2 86M) deployed inside the existing guardrails sidecar container, plus the `shfmt` Go binary for bash AST parsing. All controlled via `enclaive.conf` with secure defaults. No new services.

**Tech Stack:** HuggingFace transformers, PyTorch (CPU), protectai/sentinel-v2, meta-llama/Prompt-Guard-2-86M, mvdan/sh (shfmt)

---

## Models

### Sentinel v2

- **Source:** `protectai/sentinel-v2` (HuggingFace, pinned to commit SHA)
- **Architecture:** Qwen3-0.6B, 596M parameters
- **Capability:** Injection + jailbreak detection, English
- **Latency:** ~38ms (CPU)
- **F1:** 96.4 average
- **License:** Elastic License 2.0

### Prompt Guard 2 86M

- **Source:** `meta-llama/Prompt-Guard-2-86M` (HuggingFace, pinned to commit SHA)
- **Architecture:** mDeBERTa-v3-base, 86M parameters
- **Capability:** Injection detection, 8 languages (English, French, German, Hindi, Italian, Portuguese, Spanish, Thai)
- **Latency:** ~92ms (CPU)
- **Recall:** 97.5% at 1% FPR
- **License:** Llama 4 Community License (requires Meta terms acceptance, needs `HF_TOKEN`)

### shfmt AST Parser

- **Source:** `mvdan/sh` (GitHub release binary)
- **Command:** `shfmt --tojson`
- **Output:** JSON AST of bash commands
- **Latency:** ~10ms
- **Size:** ~15MB static binary
- **Purpose:** Extract string literals from bash commands for deep inspection by ML classifiers

## Deployment

All three components run inside the existing guardrails sidecar container. No new services, no new network hops.

- Models baked into Docker image at build time (pinned to HuggingFace commit SHAs, checksums verified post-download)
- `shfmt` binary copied into image from GitHub release
- Models loaded eagerly at startup via warmup script
- `HF_TOKEN` build arg required for Prompt Guard 2 (Llama license). Same pattern as existing `GUARDRAILS_TOKEN` — graceful skip if not provided.

## Configuration

All settings in `config/guards/enclaive.conf` (root-owned, read-only mount — agent cannot modify):

```ini
# Existing
require_sidecar=1
allowed_scripts=

# ML models (all enabled by default)
ml_sentinel_v2=1
ml_prompt_guard_2=1
bash_ast_parser=1

# Confidence thresholds (recommended: 0.80-0.95)
# WARNING: values above 0.95 will miss most attacks
ml_sentinel_threshold=0.85
ml_prompt_guard_threshold=0.90

# When ML models disagree: block (default, safer) or pass (permissive)
ml_ensemble_mode=block
```

**Startup validation:** If any threshold > 0.95, log a warning: `"WARNING: threshold {value} will miss most attacks — recommended range 0.80-0.95"`.

## Guard Pipeline (all four modes)

```python
GUARD_PIPELINES = {
    "memory": [
        ("hub:jailbreak", {}), ("hub:unusual", {}),
        ("hub:secrets", {}), ("hub:pii", {}), ("hub:detect_pii", {}),
        ("custom:EncodingDetector", {"escalate_memory": True}),
        ("custom:AcrosticDetector", {}),
        ("custom:SentinelV2Detector", {}),
        ("custom:PromptGuard2Detector", {}),
    ],
    "exfil": [
        ("hub:secrets", {}),
        ("custom:ExfilDetector", {"use_ast": True}),
        ("custom:EncodingDetector", {"escalate_network": True, "escalate_redirect": True}),
        ("custom:ForeignScriptDetector", {}),
        ("custom:AcrosticDetector", {}),
        ("custom:SentinelV2Detector", {}),
        ("custom:PromptGuard2Detector", {}),
    ],
    "inbound": [
        ("hub:jailbreak", {}), ("hub:unusual", {}),
        ("custom:EncodingDetector", {}),
        ("custom:ForeignScriptDetector", {}),
        ("custom:SentinelV2Detector", {}),
        ("custom:PromptGuard2Detector", {}),
    ],
    "write": [
        ("hub:secrets", {}), ("hub:pii", {}), ("hub:detect_pii", {}),
        ("custom:AcrosticDetector", {}),
        ("custom:SentinelV2Detector", {}),
        ("custom:PromptGuard2Detector", {}),
    ],
}
```

## Data Flow

```
Hook script (bash)
  -> curl sidecar:8000/guards/{mode}/validate
    -> regex validators (existing, ~1ms)
    -> hub validators (existing, ~50ms)
    -> ML validators (new, parallel via ThreadPoolExecutor):
        |-- Sentinel v2 inference (~38ms)
        +-- Prompt Guard 2 inference (~92ms)
    -> [exfil mode only] shfmt AST parse (~10ms)
        -> extract string literals from AST
        -> re-run ML classifiers on extracted strings (~90ms)
    -> ensemble disagreement check (if models disagree, apply ml_ensemble_mode)
    -> aggregate results -> P0/P1/pass
```

**Parallel inference:** Uses `concurrent.futures.ThreadPoolExecutor`. PyTorch releases the GIL during forward passes, so thread-based parallelism works.

**Double inference on exfil:** Intentional. The raw command gives context (curl? scp?), the extracted strings catch embedded payloads (injection in heredoc, encoded payload in echo). Latency budget accounts for this.

## Latency Budget

```
memory/inbound/write:  ~141ms  (regex ~1ms + hub ~50ms + ML parallel ~90ms)
exfil:                 ~230ms  (regex ~1ms + hub ~50ms + AST ~10ms + 2x ML parallel ~180ms)
```

## Eval/Source Escalation

If `eval`, `source`, or `. ` (dot-source) appears in a bash command, escalate to P0 regardless of other analysis. These commands execute computed strings that the AST parser cannot inspect.

## Health Checks

Two-stage health check on the sidecar:

- `GET /health` — returns 200 immediately (process alive)
- `GET /ready` — returns 200 only after all models are loaded

Hook scripts check `/ready`. During startup warmup (~15s), hooks receive "sidecar warming up" message and block (fail-closed, not a silent pass).

## Ensemble Disagreement Policy

When `ml_ensemble_mode=block` (default):
- Both models flag -> P0 BLOCK
- One model flags, one passes -> P0 BLOCK (conservative)
- Both models pass -> PASS

When `ml_ensemble_mode=pass`:
- Both models flag -> P0 BLOCK
- One model flags, one passes -> P1 WARN
- Both models pass -> PASS

This raises the bar for adaptive attacks — evading both classifiers simultaneously is significantly harder than evading one.

## Resource Requirements

| Resource | Current | After |
|----------|---------|-------|
| Sidecar memory | 1 GB | 3 GB |
| Sidecar disk | ~500 MB | ~2.5 GB (models baked in) |
| Startup time | ~3s | ~15s (model loading + warmup) |
| Per-request latency (memory/inbound/write) | ~51ms | ~141ms |
| Per-request latency (exfil) | ~51ms | ~230ms |

## AST Parser Limitations

`shfmt --tojson` parses bash syntax but diverges from actual shell interpretation in edge cases:
- `eval "$(echo payload | base64 -d)"` — shfmt sees `eval` as a command, not the decoded payload. Mitigated by eval/source escalation rule.
- Process substitution edge cases — rare in practice
- Dynamic variable expansion (`${!var}`) — fundamentally requires execution tracing

These are documented limitations. The AST parser improves coverage but is not a complete solution for computed strings.

## Known Gaps Addressed

| Gap (xfail test) | Fixed by | Why |
|---|---|---|
| Synonym substitution | Sentinel v2 + Prompt Guard 2 | Semantic understanding, not keyword matching |
| Non-English injection | Prompt Guard 2 (8 languages) | Multilingual mDeBERTa model |
| L33tspeak | Sentinel v2 | Trained on adversarial variants |
| Educational framing | Sentinel v2 + Prompt Guard 2 | Intent classification beyond surface patterns |
| Homoglyph attack | Prompt Guard 2 (tokenizer normalizes) | Subword tokenization is homoglyph-resistant |
| DNS exfil with shell expansion | shfmt AST parser | Parses `$(...)` as command substitution node |

**Still gaps (2 of 8):**
- **Multi-turn manipulation** — requires cross-turn state tracking, out of scope for per-message classifiers
- **Instruction splitting across variables** — partially improved by AST parser, but fundamentally requires execution tracing

## Testing Strategy

- 6 of 8 existing xfail tests should start passing; update 2 remaining with revised comments
- New unit tests per ML validator: threshold boundary, enabled/disabled config, model-not-found graceful degradation
- New unit tests for AST parser: simple commands, pipes, command substitution, heredocs, malformed input
- New unit tests for ensemble disagreement: both-flag, one-flag, both-pass, config toggle
- New unit tests for eval/source escalation
- False positive regression: run existing `test_false_positives.py` suite against ML classifiers
- Integration test: end-to-end sidecar request with ML models
- Startup validation test: threshold > 0.95 warning

## Security Review (Dreadnode)

All findings from staff security engineer review addressed:

| # | Finding | Severity | Resolution |
|---|---------|----------|------------|
| 1 | Model output trust — adaptive attacks evade single classifier | P0 | Ensemble disagreement policy: default to BLOCK when models disagree |
| 2 | AST parser TOCTOU — shfmt vs actual shell divergence | P0 | Eval/source escalation rule + documented limitations |
| 3 | Model loading DoS — 15s startup window | P0 | Two-stage health check (/health + /ready), fail-closed during warmup |
| 4 | Threshold config footgun | P1 | Config comments with safe ranges + startup warning if > 0.95 |
| 5 | Prompt Guard 2 license | P1 | HF_TOKEN build arg, graceful skip pattern |
| 6 | No model version pinning | P1 | Pin to HuggingFace commit SHAs, verify checksums |
| 7 | Parallel ML inference mechanism | P2 | ThreadPoolExecutor (PyTorch releases GIL) |
| 8 | Double inference on exfil | P2 | Intentional, latency budget corrected to ~230ms |
