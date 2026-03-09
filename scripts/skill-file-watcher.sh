#!/bin/bash
# PostToolUse hook: scans any SKILL.md created/modified regardless of method.
set -euo pipefail
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SKILLS_DIR="${PROJECT_DIR}/.claude/skills"
# Stamp file in protected location — /var/log/enclaive is root-owned with sticky bit
STAMP_FILE="${ENCLAIVE_AUDIT_DIR:-/var/log/enclaive}/.skill-scan-stamp"
# Fallback for non-Docker environments
[ -d "$(dirname "$STAMP_FILE")" ] || STAMP_FILE="/tmp/.skill-scan-stamp"

case "$TOOL" in
    Write|Edit|MultiEdit|Bash) ;;
    *) exit 0 ;;
esac

if [ ! -f "$STAMP_FILE" ]; then
    date +%s > "$STAMP_FILE"
    exit 0
fi

NEW_SKILLS=$(find "$SKILLS_DIR" -name "SKILL.md" -newer "$STAMP_FILE" -type f 2>/dev/null)
if [ -z "$NEW_SKILLS" ]; then
    exit 0
fi

echo "[SCAN] Skill file watcher: new/modified SKILL.md detected" >&2

export AUDIT_LOG_DIR="${PROJECT_DIR}/.audit-logs"
source "${PROJECT_DIR}/scripts/skill-audit.sh" 2>/dev/null || exit 0

BLOCKED=false
while IFS= read -r skill_file; do
    echo "  Scanning: $skill_file" >&2
    CONTENT=$(cat "$skill_file")
    if echo "$CONTENT" | python3 -c "import sys; exit(0 if any(ord(c) in {0x200b,0x200c,0x200d,0xfeff,0x180e}|set(range(0x202a,0x202f))|set(range(0x2060,0x2065)) for c in sys.stdin.read()) else 1)" 2>/dev/null; then
        echo "  [ALERT] P0: Hidden Unicode characters in $skill_file" >&2
        BLOCKED=true
    fi
    if echo "$CONTENT" | grep -qiE '(base64\s+[-dD]|b64decode|atob|btoa|Buffer\.from.*base64)'; then
        echo "  [ALERT] P0: Base64 encoded payload in $skill_file" >&2
        BLOCKED=true
    fi
    if echo "$CONTENT" | grep -qiE '(\.ssh|\.aws|\.env|PRIVATE KEY|API_KEY|api[_-]?key)'; then
        echo "  [ALERT] P0: Credential access pattern in $skill_file" >&2
        BLOCKED=true
    fi
    if echo "$CONTENT" | grep -qiE '(nc -|bash -i|/dev/tcp|reverse.shell|mkfifo)'; then
        echo "  [ALERT] P0: Reverse shell pattern in $skill_file" >&2
        BLOCKED=true
    fi
    if echo "$CONTENT" | grep -qiE '(eval\(|exec\(|Function\(|child_process|subprocess)'; then
        echo "  [WARN] P1: Code execution pattern in $skill_file — review manually" >&2
    fi
done <<< "$NEW_SKILLS"

date +%s > "$STAMP_FILE"

if [ "$BLOCKED" = true ]; then
    echo "  [GUARD] SKILL FILE WATCHER: P0 violation — blocking agent from proceeding." >&2
    echo "  Suspicious files: $NEW_SKILLS" >&2
    echo "  Remove the malicious SKILL.md and investigate the source." >&2
    # PostToolUse: return decision:block to stop the agent from continuing
    jq -n '{"decision": "block", "reason": "P0 security violation detected in newly created SKILL.md file. The file may contain hidden Unicode, base64 payloads, credential access patterns, or reverse shell commands. Remove the suspicious file before continuing."}'
fi
exit 0
