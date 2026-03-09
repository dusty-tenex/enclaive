---
name: skill-audit
description: >
  Static security auditor for skills and plugins. Detects hooks abuse,
  prompt injection, credential access, data exfiltration, and dangerous
  permissions. Run before installing any third-party skill or plugin.
---

# Skill Security Audit

## When to Use
Run this audit on ANY skill or plugin before installation.

## Checks (in priority order)

### P0 — Block Immediately
- Hidden/invisible Unicode characters (zero-width spaces, RTL overrides)
- Base64 encoded payloads in markdown
- Credential file access (.env, ~/.ssh, ~/.aws, API keys)
- Network calls to non-standard domains
- Reverse shell patterns (nc, bash -i, /dev/tcp)
- eval(), exec(), Function() with dynamic input
- File access outside workspace (../../, /etc/, ~/)

### P1 — Review Carefully
- MCP server definitions (check URL destinations)
- Hook definitions (PreToolUse hooks that modify tool inputs)
- Scripts that read stdin (potential for injection relay)
- Fetch/curl/wget to external URLs
- Environment variable reads beyond standard vars
- Dynamic code generation or template rendering

### P2 — Note for Awareness
- Large encoded blobs (images, binaries)
- Obfuscated variable names or control flow
- Complex regex patterns (potential ReDoS)
- Excessive file system traversal

## Output Format
Rate each finding as P0/P1/P2 and recommend BLOCK, REVIEW, or ALLOW.
