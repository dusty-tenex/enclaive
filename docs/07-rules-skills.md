# Rules, Skills & CLAUDE.md

All project configuration files sync into the sandbox automatically via the workspace mount.

## CLAUDE.md

A ready-to-use template is at [`config/CLAUDE.md`](../config/CLAUDE.md). Copy it to your project root:

```bash
cp config/CLAUDE.md ~/my-project/CLAUDE.md
```

It enforces branch-based workflows, quality standards, and security rules. Customize it for your project.

## Project-Level Settings

The settings file at [`config/settings.json`](../config/settings.json) goes in `.claude/settings.json`:

```bash
mkdir -p ~/my-project/.claude
cp config/settings.json ~/my-project/.claude/settings.json
```

This grants `Bash(*)`, `Read(*)`, `Write(*)`, `Edit(*)` permissions and wires all security hooks. These permissions are **only safe inside a Docker Sandbox microVM.**

> **Warning:** If anyone clones your repo and opens it with Claude Code on bare metal, `Bash(*)` gives the agent full access to their machine. Consider adding a `SessionStart` hook that verifies the sandbox environment before proceeding.

## Custom Skills

```bash
mkdir -p .claude/skills

cat > .claude/skills/security-review.md << 'EOF'
# Security Review Skill
When asked to review code for security:
1. Check for injection vulnerabilities (SQL, command, template)
2. Verify input validation and sanitization
3. Check authentication and authorization patterns
4. Look for hardcoded secrets or credentials
5. Verify error handling doesn't leak sensitive info
6. Check for path traversal vulnerabilities
7. Review dependency versions for known CVEs
EOF
```

## Air-Gapped Skill Auditor

An air-gapped fallback auditor skill is included at [`config/skills/skill-audit/SKILL.md`](../config/skills/skill-audit/SKILL.md). Copy it to your project:

```bash
cp -r config/skills/ ~/my-project/.claude/skills/
```

This gives Claude itself the ability to audit skills without any network dependency.
