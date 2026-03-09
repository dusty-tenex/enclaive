"""
Guardrails API server configuration.

Imports all validators from the shared validators.py module (single source of truth).
Guard composition from guard_definitions.py (shared with inline fallback).
Mount /app/shared/ with validators.py and guard_definitions.py when running the sidecar.

Guards exposed at: POST http://localhost:8000/guards/{name}/validate
"""
import sys, os

# Import shared modules (mounted at /app/shared/ in Docker)
sys.path.insert(0, '/app/shared')
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'scripts'))  # dev fallback
from validators import _VALIDATORS
from guard_definitions import build_guard_from_pipeline

from guardrails import Guard, OnFailAction
E = OnFailAction.EXCEPTION

# -- Hub validators (loaded if installed) --
hub = {}
for mod_name, key, cls_name in [
    ('guardrails.hub', 'secrets', 'SecretsPresent'),
    ('guardrails.hub', 'pii', 'GuardrailsPII'),
    ('guardrails.hub', 'detect_pii', 'DetectPII'),
    ('guardrails.hub', 'jailbreak', 'DetectJailbreak'),
    ('guardrails.hub', 'unusual', 'UnusualPrompt'),
]:
    try:
        cls = getattr(__import__(mod_name, fromlist=[cls_name]), cls_name)
        hub[key] = lambda c=cls: c(on_fail=E)
    except Exception:
        pass

# -- Log what loaded --
print(f"[guardrails-sidecar] Hub validators: {list(hub.keys()) or 'none'}")
print(f"[guardrails-sidecar] Custom validators: {list(_VALIDATORS.keys()) if _VALIDATORS else 'none (guardrails-ai import failed)'}")
if not hub:
    print("[guardrails-sidecar] WARNING: No Hub validators loaded. Run: guardrails configure && guardrails hub install hub://guardrails/secrets_present")

# -- Build guards from shared definitions --
memory_guard = build_guard_from_pipeline("memory", hub, _VALIDATORS, Guard, OnFailAction)
exfil_guard = build_guard_from_pipeline("exfil", hub, _VALIDATORS, Guard, OnFailAction)
inbound_guard = build_guard_from_pipeline("inbound", hub, _VALIDATORS, Guard, OnFailAction)
write_guard = build_guard_from_pipeline("write", hub, _VALIDATORS, Guard, OnFailAction)
