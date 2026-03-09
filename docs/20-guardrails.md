# Part 20: Prompt Injection & Exfiltration Guardrails

## Architecture

The guardrails system uses the open-source [guardrails-ai](https://github.com/guardrails-ai/guardrails) framework with a sidecar deployment pattern. See [Part 21](21-sidecar-architecture.md) for the full architecture.

## Hub Validators

These are community-maintained validators from the [Guardrails Hub](https://hub.guardrailsai.com). Free API key required (sign up with GitHub at hub.guardrailsai.com).

### SecretsPresent

Uses Yelp's [detect-secrets](https://github.com/Yelp/detect-secrets) library with 30+ secret detector plugins:

```bash
guardrails hub install hub://guardrails/secrets_present
```

Catches: Anthropic/OpenAI/AWS/GitHub/Slack/npm/GitLab API keys, private keys, high-entropy strings, passwords in key-value pairs.

**Known limitations:** Misses database connection strings, Bearer tokens in prose, multi-line private keys, short passwords, JWTs in nested JSON. Our `CREDENTIAL_PATTERNS` in `validators.py` cover these gaps.

### GuardrailsPII

Uses Presidio + GLiNER for ML-based PII detection:

```bash
guardrails hub install hub://guardrails/guardrails_pii
```

Catches: SSNs, credit cards, emails, phone numbers, addresses, dates, names — with contextual understanding (not just regex).

### DetectJailbreak

ML-based jailbreak detector using a locally-running trained model (no external API dependencies):

```bash
guardrails hub install hub://guardrails/detect_jailbreak
```

Catches: Prompt injection attempts, jailbreak patterns, role-play exploits, instruction override attempts.

### UnusualPrompt

Detects psychological manipulation and jailbreak prompt patterns:

```bash
guardrails hub install hub://guardrails/unusual_prompt
```

Catches: Social engineering patterns, manipulation techniques, unusual prompt structures that indicate adversarial intent.

### DetectPII (Presidio)

Microsoft Presidio-based PII detection — a second PII engine alongside GuardrailsPII for defense-in-depth:

```bash
guardrails hub install hub://guardrails/detect_pii
```

Catches: SSNs, credit cards, emails, phone numbers, addresses, names — using Presidio's recognition engine (different detection approach than GLiNER).

## Custom Validators

These live in `scripts/validators.py` and cover detection categories the Hub doesn't have:

### ExfilDetector
Catches Bash command exfiltration: `curl -d @.env`, `git push evil`, `python3 -c "urllib..."`, DNS exfil via `dig`, `node -e "fetch(...)"`.

### EncodingDetector
Catches encoded data regardless of scheme: JSFuck, Braille Unicode, emoji byte mapping, binary strings, Morse code, base64 blobs, hex escapes, URL encoding, high-entropy segments. Uses Shannon entropy analysis.

**Composite escalation:** Encoding + network command = P0 (block). Encoding + file redirect = P0. Encoding in instruction files = P0.

### ForeignScriptDetector
Catches foreign script characters in Bash/code context where they shouldn't appear: Katakana, Hiragana, Cyrillic, Arabic, Thai, Devanagari, Hangul, Runic, Ogham. Detects phonetic transliteration of secrets (e.g., API key spelled out in katakana).

### AcrosticDetector
Catches first-letter steganography: acrostics that spell credential patterns, sensitive terms (password, secret, token), or form hex strings.

## Haiku Semantic Classifier (opt-in)

For Tier 3-4 attacks that bypass all pattern and statistical analysis (natural language steganography, semantic encoding), the `haiku-injection-screen.sh` script sends content to Claude Haiku for classification. This is opt-in because it requires API calls (~$0.001/call, ~500ms latency).

To enable, add to PostToolUse hooks in `.claude/settings.json`:

```json
{
  "matcher": "Read|WebFetch|Bash|Grep",
  "hooks": [{
    "type": "command",
    "command": "./scripts/haiku-injection-screen.sh",
    "timeout": 15
  }]
}
```

## Configuration

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `GUARDRAILS_SIDECAR_URL` | `http://guardrails-sidecar:8000` | Sidecar endpoint |
| `GUARDRAILS_REQUIRE_SIDECAR` | unset | If `1`, hooks refuse inline fallback |
| `GUARD_BYPASS_DIR` | `/tmp/sandbox-guard-bypass` | Host directory mounted read-only for guard bypass |
| `SECURITY_GUARD_HAIKU` | unset | If `1`, enable Haiku L5 in inline mode |
