"""
Shared guard composition logic. Defines which validators run for each guard mode.

Used by:
  - scripts/security_guard.py (inline fallback)
  - config/guardrails-server/config.py (sidecar)

Single source of truth for guard pipelines. Do not duplicate this logic.
"""

# Guard mode -> list of (validator_type, kwargs) tuples
# validator_type is either a hub validator key or a custom validator key
GUARD_PIPELINES = {
    "memory": [
        ("hub:jailbreak", {}),
        ("hub:unusual", {}),
        ("hub:secrets", {}),
        ("hub:pii", {}),
        ("hub:detect_pii", {}),
        ("custom:EncodingDetector", {"escalate_memory": True}),
        ("custom:AcrosticDetector", {}),
        ("custom:SentinelV2Detector", {}),
        ("custom:PromptGuard2Detector", {}),
    ],
    "exfil": [
        ("hub:secrets", {}),
        ("custom:ExfilDetector", {"use_ast": True}),
        ("custom:EvalSourceEscalator", {}),
        ("custom:EncodingDetector", {"escalate_network": True, "escalate_redirect": True}),
        ("custom:ForeignScriptDetector", {}),
        ("custom:AcrosticDetector", {}),
        ("custom:SentinelV2Detector", {}),
        ("custom:PromptGuard2Detector", {}),
    ],
    "inbound": [
        ("hub:jailbreak", {}),
        ("hub:unusual", {}),
        ("custom:EncodingDetector", {}),
        ("custom:ForeignScriptDetector", {}),
        ("custom:SentinelV2Detector", {}),
        ("custom:PromptGuard2Detector", {}),
    ],
    "write": [
        ("hub:secrets", {}),
        ("hub:pii", {}),
        ("hub:detect_pii", {}),
        ("custom:AcrosticDetector", {}),
        ("custom:SentinelV2Detector", {}),
        ("custom:PromptGuard2Detector", {}),
    ],
}


def build_guard_from_pipeline(mode, hub_validators, custom_validators, Guard, OnFailAction):
    """Build a guardrails-ai Guard from the pipeline definition.

    Args:
        mode: Guard mode (memory, exfil, inbound, write)
        hub_validators: dict of hub_key -> callable that returns validator instance
        custom_validators: dict of custom_key -> validator class
        Guard: guardrails.Guard class
        OnFailAction: guardrails.OnFailAction enum
    """
    pipeline = GUARD_PIPELINES.get(mode)
    if not pipeline:
        return None

    E = OnFailAction.EXCEPTION
    guard = Guard(name=f'{mode}_guard')
    added = False

    for vtype, kwargs in pipeline:
        if vtype.startswith("hub:"):
            key = vtype[4:]
            if key in hub_validators:
                try:
                    guard = guard.use(hub_validators[key]())
                    added = True
                except Exception:
                    pass
        elif vtype.startswith("custom:"):
            key = vtype[7:]
            if key in custom_validators:
                guard = guard.use(custom_validators[key](on_fail=E, **kwargs))
                added = True

    return guard if added else None
