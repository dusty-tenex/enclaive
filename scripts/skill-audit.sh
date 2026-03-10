#!/bin/bash
# Shared skill/plugin audit library
# Usage: source this file, then call:
#   audit_url  "https://github.com/..."   → exit 0 (pass) or exit 2 (blocked)
#   audit_path "/tmp/plugin-dir"          → exit 0 (pass) or exit 2 (blocked)
#
# Reads config from plugins.json in the project root.

AUDIT_API="${SKILLAUDIT_API:-local}"
AUDIT_LOG="${AUDIT_LOG_DIR:-.audit-logs}"
mkdir -p "$AUDIT_LOG"

_scan_url() {
    local url="$1"
    curl -sf --max-time 15 -X POST "${AUDIT_API}/scan/url" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg u "$url" '{url: $u}')" 2>/dev/null || return 1
}

_scan_content() {
    local content="$1"
    curl -sf --max-time 15 -X POST "${AUDIT_API}/scan/content" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg c "$content" '{content: $c}')" 2>/dev/null || return 1
}

_check_risk() {
    local result="$1" name="$2"
    local level
    level=$(echo "$result" | jq -r '.risk_level // .riskLevel // "unknown"' 2>/dev/null)
    # Sanitize name to prevent path traversal in log filename
    local safe_name="${name//\//_}"
    local logfile
    logfile="${AUDIT_LOG}/$(date +%Y%m%d-%H%M%S%N)-$$-${safe_name}.json"
    echo "$result" > "$logfile"
    if echo "$level" | grep -qiE '(critical|high)'; then
        echo "  [ALERT] BLOCKED: $name → $level" >&2
        echo "$result" | jq -r '.findings // .threats // empty' 2>/dev/null >&2
        return 2
    fi
    echo "  [OK] $name → $level" >&2
    return 0
}

audit_url() {
    local url="$1" name="${2:-$(basename "$1" .git)}"
    echo "[SCAN] Scanning: $url" >&2
    if [ "$AUDIT_API" = "local" ]; then
        echo "  [INFO] Local mode — URL scanning skipped (clone and use audit_path instead)" >&2
        return 0
    fi
    local result
    result=$(_scan_url "$url") || {
        echo "  [WARN] SkillAudit API unreachable — BLOCKED (fail-closed)" >&2
        return 2
    }
    _check_risk "$result" "$name"
}

audit_path() {
    local dir="$1"
    local name="${2:-$(basename "$dir")}" found=0 blocked=0
    echo "[SCAN] Scanning local: $dir" >&2
    while IFS= read -r skill_file; do
        found=$((found + 1))
        local content
        content=$(cat "$skill_file")
        if [ "$AUDIT_API" = "local" ]; then
            if echo "$content" | python3 -c "import sys; exit(0 if any(ord(c) in {0x200b,0x200c,0x200d,0xfeff,0x180e}|set(range(0x202a,0x202f))|set(range(0x2060,0x2065)) for c in sys.stdin.read()) else 1)" 2>/dev/null; then
                echo "  [ALERT] P0: Hidden Unicode in ${name}:$(basename "$skill_file")" >&2
                blocked=$((blocked + 1)); continue
            fi
            if echo "$content" | grep -qE '(base64 -d|atob|Buffer\.from.*base64)'; then
                echo "  [ALERT] P0: Base64 payload in ${name}:$(basename "$skill_file")" >&2
                blocked=$((blocked + 1)); continue
            fi
            if echo "$content" | grep -qiE '(\.ssh|\.aws|\.env|PRIVATE KEY|API_KEY|api[_-]?key)'; then
                echo "  [ALERT] P0: Credential access in ${name}:$(basename "$skill_file")" >&2
                blocked=$((blocked + 1)); continue
            fi
            if echo "$content" | grep -qiE '(nc -|ncat |bash -i|/dev/tcp|/dev/udp|reverse.shell|mkfifo|socat\s)'; then
                echo "  [ALERT] P0: Reverse shell pattern in ${name}:$(basename "$skill_file")" >&2
                blocked=$((blocked + 1)); continue
            fi
            if echo "$content" | grep -qiE '(eval\(|exec\(|Function\(|child_process|subprocess)'; then
                echo "  [WARN] P1: Code execution pattern in ${name}:$(basename "$skill_file") — review manually" >&2
                echo "  [OK] ${name}:$(basename "$(dirname "$skill_file")") → no P0 violations; P1 noted above (local scan)" >&2
            else
                echo "  [OK] ${name}:$(basename "$(dirname "$skill_file")") → no known-bad patterns (local scan)" >&2
            fi
        else
            local result
            result=$(_scan_content "$content") || {
                echo "  [WARN] API unreachable for $skill_file — BLOCKED (fail-closed)" >&2
                blocked=$((blocked + 1)); continue
            }
            _check_risk "$result" "${name}:$(basename "$(dirname "$skill_file")")" || blocked=$((blocked + 1))
        fi
    done < <(find "$dir" -name "SKILL.md" -type f 2>/dev/null)

    while IFS= read -r script_file; do
        found=$((found + 1))
        local content
        content=$(cat "$script_file")
        if [ "$AUDIT_API" = "local" ]; then
            if echo "$content" | grep -qiE '(nc -|ncat |bash -i|/dev/tcp|/dev/udp|socat\s|curl.*\|.*sh|wget.*\|.*sh)'; then
                echo "  [ALERT] P0: Dangerous pattern in ${name}:$(basename "$script_file")" >&2
                blocked=$((blocked + 1))
            fi
        else
            local result
            result=$(_scan_content "$content") || continue
            _check_risk "$result" "${name}:$(basename "$script_file")" || blocked=$((blocked + 1))
        fi
    done < <(find "$dir" \( -name "hooks.json" -o -name "*.sh" -o -name "*.py" -o -name "*.ts" \) -type f 2>/dev/null | head -20)

    [ "$blocked" -gt 0 ] && return 2
    [ "$found" -eq 0 ] && echo "  [INFO] No auditable files found in $dir" >&2
    return 0
}
