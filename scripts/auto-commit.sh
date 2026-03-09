#!/bin/bash
INTERVAL=${1:-60}
echo "[auto-commit] Saving every ${INTERVAL}s"
while true; do
    sleep "$INTERVAL"
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        git add -A && git commit -m "auto-save: $(date -u +%Y-%m-%dT%H:%M:%SZ)" 2>/dev/null \
            && echo "[auto-commit] Saved" || true
    fi
done
