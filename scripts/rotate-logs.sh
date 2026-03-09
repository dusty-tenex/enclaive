#!/bin/bash
# Rotate audit and agent logs to prevent disk exhaustion
AUDIT_DIR=".audit-logs"
AGENT_DIR="agent_logs"
MAX_AUDIT_FILES=200
MAX_AGENT_AGE_DAYS=7

if [ -d "$AUDIT_DIR" ]; then
    COUNT=$(find "$AUDIT_DIR" -name "*.json" -type f | wc -l)
    if [ "$COUNT" -gt "$MAX_AUDIT_FILES" ]; then
        find "$AUDIT_DIR" -name "*.json" -type f -printf '%T@ %p\n' \
            | sort -n | head -n "$((COUNT - MAX_AUDIT_FILES))" \
            | awk '{print $2}' | xargs rm -f
        echo "[rotate] Pruned $((COUNT - MAX_AUDIT_FILES)) old audit logs"
    fi
fi

if [ -d "$AGENT_DIR" ]; then
    find "$AGENT_DIR" -name "*.log" -mtime +$MAX_AGENT_AGE_DAYS -exec gzip {} \; 2>/dev/null
    echo "[rotate] Compressed agent logs older than ${MAX_AGENT_AGE_DAYS}d"
fi
