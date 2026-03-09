"""ML ensemble disagreement policy.

When multiple ML models produce different results, this module determines
the final decision based on the configured ensemble mode.

Modes:
  block (default): If EITHER model flags -> BLOCK (conservative)
  pass: If only ONE model flags -> WARN; both must flag to BLOCK
"""


def apply_ensemble_policy(sentinel_flags, sentinel_score, pg2_flags, pg2_score, mode='block'):
    """Apply ensemble disagreement policy.

    Args:
        sentinel_flags: True if Sentinel v2 detected injection, None if unavailable
        sentinel_score: Sentinel v2 confidence score, None if unavailable
        pg2_flags: True if Prompt Guard 2 detected injection, None if unavailable
        pg2_score: Prompt Guard 2 confidence score, None if unavailable
        mode: 'block' (conservative) or 'pass' (permissive)

    Returns:
        dict with:
            blocked: bool
            severity: 'P0' | 'P1' | None
            reason: str
    """
    available = []
    if sentinel_flags is not None:
        available.append(('Sentinel v2', sentinel_flags, sentinel_score))
    if pg2_flags is not None:
        available.append(('Prompt Guard 2', pg2_flags, pg2_score))

    if not available:
        return {'blocked': False, 'severity': None, 'reason': 'No ML models available'}

    flagging = [name for name, flags, _ in available if flags]
    scores = {name: score for name, _, score in available if score is not None}

    if len(flagging) == len(available) and len(flagging) > 0:
        score_str = ', '.join(f"{n}={scores.get(n, '?'):.3f}" for n in flagging)
        return {
            'blocked': True,
            'severity': 'P0',
            'reason': f"ML ensemble unanimous: {', '.join(flagging)} ({score_str})",
        }
    elif len(flagging) > 0:
        score_str = ', '.join(f"{n}={scores.get(n, '?'):.3f}" for n in flagging)
        if mode == 'block':
            return {
                'blocked': True,
                'severity': 'P0',
                'reason': f"ML ensemble (block mode): {', '.join(flagging)} flagged ({score_str})",
            }
        else:
            return {
                'blocked': False,
                'severity': 'P1',
                'reason': f"ML ensemble (pass mode): {', '.join(flagging)} flagged ({score_str}) — WARN only",
            }
    else:
        return {'blocked': False, 'severity': None, 'reason': 'ML ensemble: no flags'}
