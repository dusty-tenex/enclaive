#!/usr/bin/env python3
"""
Claude Code Security Guard — inline fallback for when the sidecar is unavailable.

Imports all detection logic from validators.py (single source of truth).
Uses guardrails-ai Guard pipeline when available, regex fallback when not.

Modes: memory | exfil | inbound | write
Exit:  0 = allow, 2 = block
"""
import sys, os, re, json, datetime, argparse

# Import shared detection logic (single source of truth)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from validators import (
    INJECTION_PATTERNS, EXFIL_PATTERNS, CREDENTIAL_PATTERNS, PII_PATTERNS,
    ENCODING_PATTERNS, HIDDEN_UNICODE, match_patterns, count_unicode_ranges,
    shannon_entropy,
)

# ═══════════════════════════════════════════════════════════════════════
# Guardrails-ai framework + Hub detection
# ═══════════════════════════════════════════════════════════════════════
HAS_GUARDRAILS = False
hub = {}
try:
    from guardrails import Guard, OnFailAction
    HAS_GUARDRAILS = True
    E = OnFailAction.EXCEPTION
except ImportError:
    pass

if HAS_GUARDRAILS:
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

from guard_definitions import build_guard_from_pipeline

def build_guard(mode):
    if not HAS_GUARDRAILS: return None
    from validators import _VALIDATORS
    if not _VALIDATORS: return None
    return build_guard_from_pipeline(mode, hub, _VALIDATORS, Guard, OnFailAction)

# ═══════════════════════════════════════════════════════════════════════
# Standalone fallback (same patterns, no framework)
# ═══════════════════════════════════════════════════════════════════════
def standalone_check(content, mode):
    f = []
    if mode == "memory":
        f.extend(match_patterns(content, INJECTION_PATTERNS))
        f.extend(match_patterns(content, CREDENTIAL_PATTERNS))
        f.extend(match_patterns(content, ENCODING_PATTERNS))
        f.extend(match_patterns(content, PII_PATTERNS))
        if HIDDEN_UNICODE.search(content): f.append("Hidden Unicode")
        for c in re.findall(r'<!--([\s\S]*?)-->', content):
            for pat, label in INJECTION_PATTERNS[:4]:
                if re.search(pat, c): f.append(f"In comment: {label}"); break
        lines = [l.strip() for l in content.split('\n') if l.strip()]
        if len(lines) >= 4:
            fc = ''.join(l[0] for l in lines if l); fl = fc.lower()
            for pat, label in CREDENTIAL_PATTERNS:
                if re.search(pat, fc): f.append(f"Acrostic: {label}")
            if len(fc) >= 8 and re.match(r'^[0-9a-fA-F]+$', fc):
                f.append(f"Hex acrostic: {fc[:16]}")
            for term in [r'password',r'secret',r'api.?key',r'token',r'private',r'credential']:
                if re.search(term, fl): f.append(f"Acrostic: '{term}'")
    elif mode == "exfil":
        f.extend(match_patterns(content, EXFIL_PATTERNS))
        f.extend(match_patterns(content, CREDENTIAL_PATTERNS))
        f.extend(match_patterns(content, ENCODING_PATTERNS))
        counts = count_unicode_ranges(content); total = len(content)
        if total > 20:
            jf = sum(1 for c in content if c in '[]()!+')
            if jf > 50 and jf/total > 0.6: f.append("JSFuck")
            if counts.get('braille',0) > 5: f.append("Braille")
            if counts.get('emoji',0) > 20 and counts['emoji']/total > 0.05: f.append("Emoji encoding")
            mo = sum(1 for c in content if c in '.-/ ')
            if mo > 50 and mo/total > 0.8: f.append("Morse")
            if re.search(r'[01]{32,}', content.replace(' ','')): f.append("Binary")
            for m in re.finditer(r'[A-Za-z0-9+/]{40,}={0,2}', content): f.append("Base64 blob")
            for k,t in [('katakana',3),('hiragana',3),('cyrillic',5),('arabic',3),('hangul',3)]:
                if counts.get(k,0) >= t: f.append(f"{k} script")
    elif mode == "inbound":
        f.extend(match_patterns(content, INJECTION_PATTERNS))
        f.extend(match_patterns(content, ENCODING_PATTERNS))
        if HIDDEN_UNICODE.search(content): f.append("Hidden Unicode")
    elif mode == "write":
        f.extend(match_patterns(content, CREDENTIAL_PATTERNS))
        f.extend(match_patterns(content, PII_PATTERNS))
        lines = [l.strip() for l in content.split('\n') if l.strip()]
        if len(lines) >= 4:
            fl = ''.join(l[0] for l in lines if l).lower()
            for term in [r'password',r'secret',r'api.?key',r'token',r'private',r'credential']:
                if re.search(term, fl): f.append(f"Acrostic: '{term}'")
        for m in re.finditer(r'[A-Za-z0-9+/]{16,}={0,2}', content):
            try:
                import base64
                dec = base64.b64decode(m.group()).decode('utf-8', errors='ignore')
                df = match_patterns(dec, CREDENTIAL_PATTERNS)
                if df: f.extend(f"In base64: {x}" for x in df)
            except: pass
    return (bool(f), "; ".join(f))

# ═══════════════════════════════════════════════════════════════════════
# Hook input extraction
# ═══════════════════════════════════════════════════════════════════════
MEMORY_FILES = {"CLAUDE.md","RALPH.md","progress.md","MEMORY.md","SOUL.md"}
def is_memory_file(fp):
    bn = os.path.basename(fp)
    return (bn in MEMORY_FILES or
            (".claude/agents/" in fp and "/memory/" in fp) or
            (".claude/skills/" in fp and fp.endswith(".md")))

def extract(hook, mode):
    tool = hook.get("tool_name",""); content = file_path = ""
    ti = hook.get("tool_input", {})
    if tool in ("Write","Edit","MultiEdit"):
        file_path = ti.get("file_path","") or ti.get("path","")
        content = ti.get("content","") or ti.get("new_string","")
    elif tool == "Bash":
        cmd = ti.get("command","")
        if mode == "exfil": return "bash_command", cmd
        # For memory/write modes: detect target file path, then validate the
        # FULL command as content. Parsing bash to extract just the payload
        # is unreliable — validate everything the command contains.
        m = re.search(r'>\s*([^\s|&;]+)', cmd)
        if m: file_path = m.group(1)
        if not file_path:
            for pat in [r'(?:cp|mv)\s+\S+\s+(\S*(?:CLAUDE\.md|RALPH\.md|progress\.md|\.claude/skills/\S*|\.claude/agents/\S*))',
                        r'tee\s+(\S*(?:CLAUDE\.md|RALPH\.md|\.claude/skills/\S*|\.claude/agents/\S*))',
                        r'(?:echo|printf|cat)\s.*>\s*(\S*(?:CLAUDE\.md|RALPH\.md|progress\.md|\.claude/skills/\S*|\.claude/agents/\S*))']:
                m = re.search(pat, cmd)
                if m: file_path = m.group(1); break
            if re.search(r'tar\s+.*(?:\.claude/skills|\.claude/agents)', cmd): file_path = ".claude/skills/SKILL.md"
            if re.search(r'(?:curl|wget)\s.*(?:\.claude/skills|\.claude/agents|CLAUDE\.md|RALPH\.md)', cmd):
                file_path = file_path or "CLAUDE.md"
        # Always validate the full command — don't try to extract substrings
        content = cmd
    elif tool in ("Read","WebFetch","Grep") and mode == "inbound":
        content = hook.get("tool_response",""); file_path = ti.get("file_path","") or "tool_output"
    return file_path, content

# ═══════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["memory","exfil","inbound","write"], required=True)
    args = parser.parse_args()
    try: hook = json.loads(sys.stdin.read())
    except: sys.exit(0)
    # Bypass only via host-controlled read-only mount (agent cannot write to this path)
    bypass_files = {"memory": "bypass-memory-guard", "exfil": "bypass-exfil-guard",
                    "write": "bypass-write-guard", "inbound": "bypass-inbound-guard"}
    bypass = bypass_files.get(args.mode)
    if bypass and os.path.isfile(f"/etc/sandbox-guards/{bypass}"): sys.exit(0)
    file_path, content = extract(hook, args.mode)
    if not content or len(content) < 10: sys.exit(0)
    if args.mode == "memory" and not is_memory_file(file_path): sys.exit(0)

    blocked, reason = False, ""
    guard = build_guard(args.mode)
    if guard is not None:
        try:
            result = guard.validate(content)
            if not result.validation_passed:
                blocked = True; reason = str(getattr(result, 'error', 'Validation failed'))
        except Exception as e:
            blocked = True; reason = str(e)
    else:
        blocked, reason = standalone_check(content, args.mode)

    if not blocked: sys.exit(0)

    project_dir = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())
    audit_dir = os.path.join(project_dir, ".audit-logs"); os.makedirs(audit_dir, exist_ok=True)
    log = {"timestamp": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
           "mode": args.mode, "file": file_path, "tool": hook.get("tool_name",""),
           "action": "BLOCKED", "reason": reason[:500],
           "engine": "guardrails-ai" if guard else "standalone"}
    with open(os.path.join(audit_dir, "security-guard.jsonl"), "a") as f:
        f.write(json.dumps(log) + "\n")

    print(f"[GUARD] SECURITY GUARD [{args.mode.upper()}]: Blocked", file=sys.stderr)
    print(f"  Reason: {reason[:300]}", file=sys.stderr)
    print(f"  File: {file_path}", file=sys.stderr)
    print(f"  To bypass (host-side only): touch /etc/sandbox-guards/{bypass}", file=sys.stderr)
    sys.exit(2)

if __name__ == "__main__": main()
