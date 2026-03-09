#!/bin/bash
# Temporary bypass for all guards via host-controlled read-only mount.
#
# HOW TO USE (from the HOST, not inside the sandbox):
#   1. Create bypass files on the host:
#        mkdir -p /tmp/sandbox-guard-bypass
#        touch /tmp/sandbox-guard-bypass/bypass-write-guard
#        touch /tmp/sandbox-guard-bypass/bypass-memory-guard
#        touch /tmp/sandbox-guard-bypass/bypass-exfil-guard
#        touch /tmp/sandbox-guard-bypass/bypass-audit-gate
#
#   2. Mount into the sandbox (add to docker-compose.yml sandbox volumes):
#        - /tmp/sandbox-guard-bypass:/etc/sandbox-guards:ro
#
#   3. To re-enable guards, remove the bypass files on the host:
#        rm /tmp/sandbox-guard-bypass/bypass-*
#
# The read-only mount means the agent CANNOT create or remove these files.
# Only the host operator can control guard bypass.

echo "[INFO] Guard bypass is now controlled via host-side read-only mount."
echo "  Bypass dir: /etc/sandbox-guards/ (read-only inside sandbox)"
echo "  See this script's comments for setup instructions."
echo ""
echo "  Current bypass status:"
for guard in bypass-write-guard bypass-memory-guard bypass-exfil-guard bypass-audit-gate; do
    if [ -f "/etc/sandbox-guards/$guard" ]; then
        echo "    $guard: BYPASSED"
    else
        echo "    $guard: ACTIVE"
    fi
done
