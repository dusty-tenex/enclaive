"""
Shared detection patterns and validator classes for Claude Code Security Guard.

This is the single source of truth for all detection logic. Used by:
  - scripts/security_guard.py (inline fallback)
  - config/guardrails-server/config.py (sidecar)

Do NOT duplicate these patterns elsewhere. Import from this module.
"""
import os
import re
import math
import sys
from collections import Counter

# ═══════════════════════════════════════════════════════════════════════
# Pattern Libraries
# ═══════════════════════════════════════════════════════════════════════

INJECTION_PATTERNS = [
    (r'(?i)(ignore|disregard|forget)\s+(all\s+)?(previous|prior|above|earlier)\s+(instructions|rules|constraints|guidelines)', "Instruction override"),
    (r'(?i)(new|updated|revised|replacement)\s+(system\s*prompt|instructions|rules|directives)', "System prompt replacement"),
    (r'(?i)(you are now|from now on|your new\s+(role|identity|purpose|persona))', "Role hijacking"),
    (r'(?i)(do not|don.t|never)\s+(mention|report|tell|alert|warn|log|flag|disclose)', "Reporting suppression"),
    (r'(?i)(pretend|act as if|simulate|roleplay)\s+(you|that|being)', "Role-play injection"),
    (r'(?i)IMPORTANT:\s*(ignore|override|forget|disregard)', "Urgency-prefixed override"),
    (r'(?i)(sudo|admin|root)\s+(mode|access|override|privilege)', "Privilege escalation language"),
]

EXFIL_PATTERNS = [
    (r'curl\s+.*(-d|--data|--data-binary|--data-urlencode)\s+.*(@\.|[\$\(])', "curl sending file/variable data"),
    (r'curl\s+.*\|\s*base64', "curl with base64 encoding"),
    (r'wget\s+.*--post-(data|file)', "wget POST with data"),
    (r'git\s+remote\s+(add|set-url)\b', "Adding/changing git remote"),
    (r'git\s+push\s+(?!origin\b)\S+', "git push to non-origin remote"),
    (r'python3?\s+-c\s+.*(?:urlopen|requests\.(?:get|post)|socket)', "Python network one-liner"),
    (r'node\s+-e\s+.*(?:https?\.(?:get|request)|fetch|axios)', "Node network one-liner"),
    (r'(?:dig|nslookup|host)\s+\S*\.\S+\.\S+', "DNS lookup (potential exfil)"),
    (r'ping\s+-c\s+1\s+\$', "Ping with variable expansion"),
    (r'(?:nc|ncat|netcat)\s+(?:-[a-z]*\s+)*\S+\s+\d+', "Netcat connection"),
    (r'socat\s+.*(?:TCP|UDP|EXEC|SYSTEM)', "Socat network/exec"),
    (r'perl\s+-e\s+.*(?:socket|IO::Socket|LWP|HTTP)', "Perl network one-liner"),
    (r'ruby\s+-e\s+.*(?:Net::HTTP|TCPSocket|open-uri|URI\.open)', "Ruby network one-liner"),
    (r'curl\s+.*[?&]\w+=\$', "curl with variable in query string"),
    (r'(?:bash|sh|zsh)\s+.*(?:/dev/tcp|/dev/udp)/', "Shell /dev/tcp network access"),
    (r'curl\s+.*-X\s+POST\s+.*[\$\(\`@]', "curl POST with dynamic data"),
    (r'curl\s+[^|]*\$\(', "curl with command substitution in URL"),
    (r'curl\s+.*-H\s+["\']?[^"\']*\$', "curl with variable in header"),
    (r'git\s+commit\s+.*--no-verify', "git commit skipping hooks"),
    (r'(?:pbcopy|xclip|xsel|wl-copy)', "Clipboard exfiltration utility"),
    (r'scp\s+\S+\s+\S+@\S+:', "SCP file transfer to remote host"),
    (r'rsync\s+.*\S+@\S+:', "rsync to remote host"),
    (r'ssh\s+.*-R\s+\d+:', "SSH reverse tunnel"),
]

CREDENTIAL_PATTERNS = [
    (r'(?:sk-ant-|sk-)[a-zA-Z0-9_-]{20,}', "Anthropic API key"),
    (r'(?:ghp_|gho_|ghu_|ghs_|ghr_)[a-zA-Z0-9]{36,}', "GitHub token"),
    (r'xox[bpsa]-[a-zA-Z0-9-]+', "Slack token"),
    (r'AKIA[0-9A-Z]{16}', "AWS access key"),
    (r'-----BEGIN\s+(RSA\s+)?PRIVATE\s+KEY-----', "Private key"),
    (r'(?:glpat-)[a-zA-Z0-9\-_]{20,}', "GitLab token"),
    (r'(?:npm_)[a-zA-Z0-9]{30,}', "npm token"),
    (r'eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\.', "JWT token"),
    (r'(?:mongodb\+srv|postgres(?:ql)?|mysql|redis)://[^\s"\']+@[^\s"\']+', "DB connection string"),
    (r'(?:sk_test_|sk_live_|rk_test_|rk_live_)[a-zA-Z0-9_]{20,}', "Stripe API key"),
    (r'SG\.[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}', "SendGrid API key"),
    (r'AIzaSy[a-zA-Z0-9_-]{30,}', "Google API key"),
    (r'gsk_[a-zA-Z0-9_]{20,}', "Groq API key"),
    (r'xai-[a-zA-Z0-9_-]{20,}', "xAI API key"),
    (r'mist-[a-zA-Z0-9_-]{20,}', "Mistral API key"),
]

PII_PATTERNS = [
    (r'\b\d{3}-\d{2}-\d{4}\b', "SSN"),
    (r'\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b', "Credit card number"),
]

ENCODING_PATTERNS = [
    (r'(?:base64\s*(?:encode|decode|[-_.])|atob|btoa|Buffer\.from\s*\([^)]*,\s*["\']base64)', "Base64 operation"),
    (r'\\x[0-9a-fA-F]{2}(?:\\x[0-9a-fA-F]{2}){5,}', "Hex-escaped bytes"),
    (r'%[0-9a-fA-F]{2}(?:%[0-9a-fA-F]{2}){5,}', "URL-encoded bytes"),
    (r'\\u[0-9a-fA-F]{4}(?:\\u[0-9a-fA-F]{4}){3,}', "Unicode escapes"),
]

HIDDEN_UNICODE = re.compile(r'[\u200b\u200c\u200d\ufeff\u202a-\u202e\u2060-\u2064\u180e]')

# ═══════════════════════════════════════════════════════════════════════
# Statistical Helpers
# ═══════════════════════════════════════════════════════════════════════

def shannon_entropy(text):
    if not text: return 0.0
    freq = Counter(text); n = len(text)
    return -sum((c/n)*math.log2(c/n) for c in freq.values())

UNICODE_RANGES = {
    'emoji': (0x1F600,0x1F64F,0x1F300,0x1F5FF,0x1F680,0x1F6FF,0x1F900,0x1F9FF,0x2600,0x26FF,0x2700,0x27BF),
    'braille': (0x2800,0x28FF), 'cjk_unified': (0x4E00,0x9FFF), 'mathematical': (0x1D400,0x1D7FF),
    'katakana': (0x30A0,0x30FF), 'hiragana': (0x3040,0x309F), 'cyrillic': (0x0400,0x04FF),
    'arabic': (0x0600,0x06FF), 'thai': (0x0E00,0x0E7F), 'devanagari': (0x0900,0x097F),
    'hangul': (0xAC00,0xD7AF), 'runic': (0x16A0,0x16FF), 'ogham': (0x1680,0x169F),
}

def count_unicode_ranges(text):
    counts = {n: 0 for n in UNICODE_RANGES}
    for ch in text:
        cp = ord(ch)
        for name, rng in UNICODE_RANGES.items():
            if len(rng) == 2:
                if rng[0] <= cp <= rng[1]: counts[name] += 1
            else:
                for j in range(0, len(rng), 2):
                    if rng[j] <= cp <= rng[j+1]: counts[name] += 1; break
    return counts

def normalize_unicode(text):
    """NFKC-normalize text to defeat homoglyph attacks.

    Maps visually similar characters (e.g., Cyrillic 'i' U+0456) to their
    Latin equivalents before regex matching.
    """
    import unicodedata
    return unicodedata.normalize('NFKC', text)

def _load_allowed_scripts():
    """Load allowed scripts from root-owned config file, not env var.

    Config file at /etc/sandbox-guards/enclaive.conf is read-only mounted
    from the host — the agent cannot modify it.
    """
    conf_path = '/etc/sandbox-guards/enclaive.conf'
    try:
        with open(conf_path) as f:
            for line in f:
                line = line.strip()
                if line.startswith('allowed_scripts='):
                    val = line.split('=', 1)[1].strip()
                    return set(s.strip().lower() for s in val.split(',') if s.strip())
    except (FileNotFoundError, PermissionError):
        pass
    # Fallback to env var for non-Docker environments (development only)
    val = os.environ.get('ENCLAIVE_ALLOWED_SCRIPTS', '')
    return set(s.strip().lower() for s in val.split(',') if s.strip())

_ALLOWED_SCRIPTS = _load_allowed_scripts()

def _load_require_sidecar():
    """Load require_sidecar setting from root-owned config file."""
    conf_path = '/etc/sandbox-guards/enclaive.conf'
    try:
        with open(conf_path) as f:
            for line in f:
                line = line.strip()
                if line.startswith('require_sidecar='):
                    return line.split('=', 1)[1].strip()
    except (FileNotFoundError, PermissionError):
        pass
    return os.environ.get('GUARDRAILS_REQUIRE_SIDECAR', '1')

def _load_ml_config():
    """Load ML security settings from root-owned config file.

    Config file at /etc/sandbox-guards/enclaive.conf is read-only mounted
    from the host. Falls back to env vars for development environments.

    Returns a dict with keys: ml_sentinel_v2, ml_prompt_guard_2,
    bash_ast_parser, ml_sentinel_threshold, ml_prompt_guard_threshold,
    ml_ensemble_mode.
    """
    # Defaults (secure-by-default)
    defaults = {
        'ml_sentinel_v2': True,
        'ml_prompt_guard_2': True,
        'bash_ast_parser': True,
        'ml_sentinel_threshold': 0.85,
        'ml_prompt_guard_threshold': 0.90,
        'ml_ensemble_mode': 'block',
    }

    # Config key -> (conf file key, env var, type)
    key_map = {
        'ml_sentinel_v2':          ('ml_sentinel_v2',          'ENCLAIVE_ML_SENTINEL_V2',          'bool'),
        'ml_prompt_guard_2':       ('ml_prompt_guard_2',       'ENCLAIVE_ML_PROMPT_GUARD_2',       'bool'),
        'bash_ast_parser':         ('bash_ast_parser',         'ENCLAIVE_BASH_AST_PARSER',         'bool'),
        'ml_sentinel_threshold':   ('ml_sentinel_threshold',   'ENCLAIVE_ML_SENTINEL_THRESHOLD',   'float'),
        'ml_prompt_guard_threshold': ('ml_prompt_guard_threshold', 'ENCLAIVE_ML_PROMPT_GUARD_THRESHOLD', 'float'),
        'ml_ensemble_mode':        ('ml_ensemble_mode',        'ENCLAIVE_ML_ENSEMBLE_MODE',        'str'),
    }

    # Try config file first
    conf_path = '/etc/sandbox-guards/enclaive.conf'
    file_values = {}
    try:
        with open(conf_path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                if '=' not in line:
                    continue
                k, v = line.split('=', 1)
                file_values[k.strip()] = v.strip()
    except (FileNotFoundError, PermissionError):
        pass

    result = {}
    for key, (conf_key, env_var, typ) in key_map.items():
        raw = file_values.get(conf_key)
        if raw is None:
            raw = os.environ.get(env_var)

        if raw is None:
            result[key] = defaults[key]
            continue

        if typ == 'bool':
            result[key] = (raw != '0')
        elif typ == 'float':
            try:
                parsed = float(raw)
                if 0.0 <= parsed <= 1.0:
                    result[key] = parsed
                else:
                    result[key] = defaults[key]
                    print(f"WARNING: {key}={raw} outside valid range [0.0, 1.0] — using default {defaults[key]}", file=sys.stderr)
            except ValueError:
                result[key] = defaults[key]
        elif typ == 'str':
            if raw in ('block', 'pass'):
                result[key] = raw
            else:
                result[key] = defaults[key]

    # Warn if any threshold is dangerously high
    for tkey in ('ml_sentinel_threshold', 'ml_prompt_guard_threshold'):
        if result[tkey] > 0.95:
            print(f"WARNING: {tkey}={result[tkey]} will miss most attacks — recommended range 0.80-0.95", file=sys.stderr)

    return result

_ML_CONFIG = _load_ml_config()

def match_patterns(content, patterns):
    normalized = normalize_unicode(content)
    check_normalized = (normalized != content)
    results = []
    for pat, label in patterns:
        if re.search(pat, content):
            results.append(label)
        elif check_normalized and re.search(pat, normalized):
            results.append(label)
    return results

# ═══════════════════════════════════════════════════════════════════════
# Guardrails AI Validators (registered only when framework is available)
# ═══════════════════════════════════════════════════════════════════════

def register_validators():
    """Register custom validators with guardrails-ai. Call once at import time."""
    try:
        from guardrails.validators import Validator, PassResult, FailResult, register_validator
    except ImportError:
        return  # guardrails-ai not installed

    @register_validator(name="enclaive/exfil-detector", data_type="string")
    class ExfilDetector(Validator):
        """Bash command exfiltration detection with optional AST extraction."""
        def __init__(self, use_ast=False, **kw):
            super().__init__(**kw)
            self._use_ast = use_ast
        def _validate(self, value, metadata=None):
            f = match_patterns(value, EXFIL_PATTERNS)
            if self._use_ast and _ML_CONFIG.get('bash_ast_parser', True):
                try:
                    from bash_ast import extract_strings
                    extracted = extract_strings(value)
                    for s in extracted:
                        sf = match_patterns(s, EXFIL_PATTERNS)
                        f.extend(f"In AST string: {x}" for x in sf)
                        cf = match_patterns(s, CREDENTIAL_PATTERNS)
                        f.extend(f"In AST string: {x}" for x in cf)
                except Exception:
                    pass
            return FailResult(error_message=f"Exfil: {'; '.join(f)}") if f else PassResult()

    @register_validator(name="enclaive/encoding-detector", data_type="string")
    class EncodingDetector(Validator):
        """JSFuck, Braille, emoji, binary, morse, base64 blobs, high entropy."""
        def __init__(self, escalate_network=False, escalate_redirect=False,
                     escalate_memory=False, **kw):
            super().__init__(**kw)
            self._net = escalate_network; self._redir = escalate_redirect; self._mem = escalate_memory
        def _validate(self, value, metadata=None):
            f = []; total = len(value)
            if total < 20: return PassResult()
            f.extend(match_patterns(value, ENCODING_PATTERNS))
            counts = count_unicode_ranges(value)
            jf = sum(1 for c in value if c in '[]()!+')
            if jf > 50 and jf/total > 0.6: f.append("JSFuck encoding")
            bf = sum(1 for c in value if c in '><+-.,[]')
            if bf > 50 and bf/total > 0.7: f.append("Brainfuck encoding")
            if counts.get('emoji',0) > 20 and counts['emoji']/total > 0.05: f.append("Emoji encoding")
            if counts.get('braille',0) > 5: f.append("Braille encoding")
            if counts.get('mathematical',0) > 10: f.append("Math Unicode homoglyphs")
            mo = sum(1 for c in value if c in '.-/ ')
            if mo > 50 and mo/total > 0.8: f.append("Morse encoding")
            if re.search(r'[01]{32,}', value.replace(' ','')): f.append("Binary encoding")
            for m in re.finditer(r'[A-Za-z0-9+/]{40,}={0,2}', value): f.append(f"Base64 blob ({len(m.group())}ch)")
            for line in value.split('\n'):
                stripped = line.strip()
                if len(stripped) > 40 and shannon_entropy(stripped) > 5.5:
                    f.append("High-entropy segment"); break
            if not f: return PassResult()
            escalated = self._mem
            if self._net and re.search(r'(?:curl|wget|fetch|git\s+push|urlopen|requests\.|urllib|socket|dig\s|nc\s|node\s+-e)', value, re.I): escalated = True
            if self._redir and re.search(r'>\s*\S+', value): escalated = True
            tag = "Encoding [ESCALATED]" if escalated else "Encoding"
            return FailResult(error_message=f"{tag}: {'; '.join(f)}")

    @register_validator(name="enclaive/foreign-script-detector", data_type="string")
    class ForeignScriptDetector(Validator):
        """Foreign scripts in Bash/code context."""
        def __init__(self, **kw):
            super().__init__(**kw)
            self._allowed = _ALLOWED_SCRIPTS
        def _validate(self, value, metadata=None):
            if len(value) < 15: return PassResult()
            f = []; counts = count_unicode_ranges(value)
            for key, name, thr in [('katakana','Katakana',3),('hiragana','Hiragana',3),
                ('cyrillic','Cyrillic',5),('arabic','Arabic',3),('thai','Thai',3),
                ('devanagari','Devanagari',3),('hangul','Hangul',3),('runic','Runic',2),('ogham','Ogham',2)]:
                if key in self._allowed:
                    continue
                if counts.get(key,0) >= thr: f.append(f"{name} ({counts[key]}ch)")
            if 'cjk_unified' not in self._allowed:
                cjk = counts.get('cjk_unified',0)
                if 3 <= cjk <= 20 and cjk/len(value) > 0.02: f.append(f"CJK ({cjk}ch)")
            return FailResult(error_message=f"Foreign script: {'; '.join(f)}") if f else PassResult()

    @register_validator(name="enclaive/acrostic-detector", data_type="string")
    class AcrosticDetector(Validator):
        """First-letter steganographic encoding."""
        def __init__(self, **kw): super().__init__(**kw)
        def _validate(self, value, metadata=None):
            lines = [l.strip() for l in value.split('\n') if l.strip()]
            if len(lines) < 4: return PassResult()
            fc = ''.join(l[0] for l in lines if l); f = []
            for pat, label in CREDENTIAL_PATTERNS:
                if re.search(pat, fc): f.append(f"Acrostic matches {label}")
            if len(fc) >= 8 and re.match(r'^[0-9a-fA-F]+$', fc): f.append(f"Hex acrostic: {fc[:16]}")
            fl = fc.lower()
            for term in [r'password',r'secret',r'api.?key',r'token',r'private',r'credential',r'auth']:
                if re.search(term, fl): f.append(f"Acrostic spells '{term}'")
            return FailResult(error_message=f"Acrostic: {'; '.join(f)}") if f else PassResult()

    @register_validator(name="enclaive/sentinel-v2-detector", data_type="string")
    class SentinelV2Detector(Validator):
        """ML-based injection/jailbreak detection using ProtectAI Sentinel v2."""
        _pipeline = None
        _load_attempted = False

        def __init__(self, **kw):
            super().__init__(**kw)

        @classmethod
        def _get_pipeline(cls):
            if cls._load_attempted:
                return cls._pipeline
            cls._load_attempted = True
            try:
                from transformers import pipeline
                cls._pipeline = pipeline(
                    "text-classification",
                    model="protectai/sentinel-v2",
                    device=-1,
                    truncation=True,
                    max_length=512,
                )
            except Exception:
                cls._pipeline = None
            return cls._pipeline

        def _validate(self, value, metadata=None):
            if not _ML_CONFIG.get('ml_sentinel_v2', True):
                return PassResult()
            pipe = self._get_pipeline()
            if pipe is None:
                return PassResult()
            try:
                result = pipe(value[:512])[0]
                threshold = _ML_CONFIG.get('ml_sentinel_threshold', 0.85)
                if result['label'] == 'INJECTION' and result['score'] >= threshold:
                    return FailResult(
                        error_message=f"ML Sentinel v2: injection detected (score={result['score']:.3f}, threshold={threshold})"
                    )
            except Exception:
                pass
            return PassResult()

    @register_validator(name="enclaive/prompt-guard-2-detector", data_type="string")
    class PromptGuard2Detector(Validator):
        """ML-based injection detection using Meta Prompt Guard 2 86M. 8 languages."""
        _pipeline = None
        _load_attempted = False

        def __init__(self, **kw):
            super().__init__(**kw)

        @classmethod
        def _get_pipeline(cls):
            if cls._load_attempted:
                return cls._pipeline
            cls._load_attempted = True
            try:
                from transformers import pipeline
                cls._pipeline = pipeline(
                    "text-classification",
                    model="meta-llama/Prompt-Guard-2-86M",
                    device=-1,
                    truncation=True,
                    max_length=512,
                )
            except Exception:
                cls._pipeline = None
            return cls._pipeline

        def _validate(self, value, metadata=None):
            if not _ML_CONFIG.get('ml_prompt_guard_2', True):
                return PassResult()
            pipe = self._get_pipeline()
            if pipe is None:
                return PassResult()
            try:
                result = pipe(value[:512])[0]
                threshold = _ML_CONFIG.get('ml_prompt_guard_threshold', 0.90)
                if result['label'] == 'INJECTION' and result['score'] >= threshold:
                    return FailResult(
                        error_message=f"ML Prompt Guard 2: injection detected (score={result['score']:.3f}, threshold={threshold})"
                    )
            except Exception:
                pass
            return PassResult()

    @register_validator(name="enclaive/eval-source-escalator", data_type="string")
    class EvalSourceEscalator(Validator):
        """P0 escalation for eval/source/dot-source commands."""
        def __init__(self, **kw):
            super().__init__(**kw)
        def _validate(self, value, metadata=None):
            from bash_ast import has_eval_or_source
            if has_eval_or_source(value):
                return FailResult(
                    error_message="P0 ESCALATION: eval/source detected — computed strings cannot be AST-inspected"
                )
            return PassResult()

    return {
        'ExfilDetector': ExfilDetector,
        'EncodingDetector': EncodingDetector,
        'ForeignScriptDetector': ForeignScriptDetector,
        'AcrosticDetector': AcrosticDetector,
        'SentinelV2Detector': SentinelV2Detector,
        'PromptGuard2Detector': PromptGuard2Detector,
        'EvalSourceEscalator': EvalSourceEscalator,
    }

# Auto-register on import
_VALIDATORS = register_validators()
