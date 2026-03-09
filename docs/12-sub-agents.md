# Sub-Agents, Agent Teams & Multi-Agent Patterns

Claude Code has three distinct multi-agent systems, each suited to different problems. This page covers all three, when to use which, and how they interact with the sandbox security model.

## Which Pattern to Use

| I need to... | Use | Why |
|---|---|---|
| Search/explore the codebase faster | **Built-in subagents** (automatic) | Explore subagent is read-only, uses Haiku (cheap), fires automatically |
| Run 3-7 independent tasks in parallel | **Built-in subagents** via Task tool | Same session, isolated context windows, results flow back to you |
| Have agents coordinate and communicate | **Agent Teams** | Shared task list, peer-to-peer messaging, direct teammate interaction |
| Work on separate git branches simultaneously | **Agent tool** with `isolation: "worktree"` | True process-level isolation, independent commit histories |
| Run a long autonomous loop overnight | **Agent tool** or [ralph-wiggum plugin](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) | See [Autonomous Loop Security](11-autonomous-loop-security.md) for threat model |

Most work should start with built-in subagents. Graduate to Agent Teams when agents need to coordinate. Use worktree isolation when you need branch-level separation.

---

## 1. Built-in Subagents (Always Available)

Claude Code automatically delegates to specialized subagents when appropriate. You don't need to configure anything — they're built in.

### Default Subagents

**Explore** — Fast, read-only agent for searching and analyzing codebases. Uses the cheaper model (Haiku). Claude delegates here when it needs to find files, search code, or understand structure without making changes. You'll see this fire automatically when you ask broad questions about your codebase.

**Plan** — Codebase research for planning mode. When you're in plan mode and Claude needs to understand your code before proposing changes, it delegates research here.

**General-purpose** — Full-capability agent for complex multi-step tasks requiring both exploration and modification. Claude delegates here when the task needs reading, reasoning, and writing across multiple files.

### Using the Task Tool Directly

You can explicitly request subagent parallelism in your prompts:

```
Read all 5 config files in parallel and summarize the differences.
```

```
Research the authentication, database, and API layers simultaneously,
then give me a unified architecture summary.
```

Claude will spawn up to 7 subagents concurrently via the Task tool. Each gets its own context window and returns results to the main session.

### Custom Subagents

Create your own subagents with custom prompts, tool restrictions, and model routing. Define them in `.claude/agents/`:

```yaml
# .claude/agents/security-reviewer.yml
name: security-reviewer
description: Reviews code changes for security vulnerabilities
model: claude-sonnet-4-20250514
tools:
  - Read
  - Glob
  - Grep
  - WebFetch
# No Write/Edit/Bash — this agent is read-only
prompt: |
  You are a security reviewer. Analyze code for:
  - Injection vulnerabilities (SQL, command, template)
  - Authentication and authorization flaws
  - Credential exposure and path traversal
  Report findings with severity ratings and file locations.
```

```yaml
# .claude/agents/test-writer.yml
name: test-writer
description: Writes tests for new or modified code
model: claude-sonnet-4-20250514
tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
prompt: |
  You are a test engineer. When given code to test:
  - Read the implementation thoroughly
  - Write comprehensive unit tests
  - Run the tests to verify they pass
  - Achieve >80% branch coverage
```

Claude automatically delegates to your custom subagents when the task matches their description. You can route cheap tasks to Sonnet or Haiku to control costs.

### Subagent Memory

Custom subagents can have persistent memory that accumulates across sessions:

```yaml
# .claude/agents/security-reviewer.yml (add to existing)
name: security-reviewer
description: Reviews code with project-specific pattern knowledge
memory:
  scope: project   # user, project, or local
```

Ask the subagent to consult its memory before starting work ("check your memory for patterns you've seen before") and to update it after completing a task. Over time, this builds a knowledge base that makes the subagent more effective for your specific codebase.

> **Persistence risk:** Subagent memory files persist across sessions. A prompt-injected subagent could write malicious instructions into its memory that affect future sessions — the same inter-session poisoning risk as Ralph loop progress files. The `memory-integrity.sh` SessionStart hook automatically checksums these files between sessions and screens changes through Haiku for injection detection. See [Hook Scripts Reference](09-hook-scripts.md).

### Subagent Security Properties

- **Hooks fire on subagent tool calls.** Your PreToolUse write guard, audit gate, and PostToolUse injection screen all apply to subagent actions. This is the key security advantage over worktree scripts.
- **Tool restrictions are enforced.** A custom subagent defined with only `Read, Glob, Grep` genuinely cannot write files, even with `--dangerously-skip-permissions` active.
- **Subagents cannot spawn other subagents.** No recursive delegation chains.
- **Context is isolated.** A subagent only sees what's explicitly passed to it plus what it reads — not your full conversation history.

You can log subagent activity using the `SubagentStop` hook event:

```json
{
  "hooks": {
    "SubagentStop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "echo \"[$(date -u +%H:%M:%S)] Subagent completed\" >> .audit-logs/subagent-activity.log"
          }
        ]
      }
    ]
  }
}
```

---

## 2. Agent Teams (Experimental — Opt-in)

Agent Teams allow multiple Claude Code sessions to work as a coordinated team. Unlike subagents (which report back to a single parent), teammates communicate directly with each other through a shared task list and mailbox system.

### Enable Agent Teams

Agent Teams are experimental and disabled by default. Add to `.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

Or set the environment variable: `export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`

### Using Agent Teams

Describe the team you want in natural language:

```
Create an agent team to refactor the payment module:
- Teammate 1: API layer (src/api/payments/)
- Teammate 2: Database migrations (db/migrations/)
- Teammate 3: Test coverage (tests/payments/)
Each teammate should own their files. Don't edit the same files.
```

Claude creates a team lead (your session), spawns teammates, distributes tasks, and coordinates results. Teammates message each other directly — sharing type definitions, flagging blockers, confirming interfaces.

### Best Practices for Agent Teams

**Plan first, team second.** Use plan mode (cheap) to design the work breakdown, then hand the plan to a team for parallel execution. The plan gives you a cost checkpoint before spinning up teammates.

**Assign file ownership.** The biggest source of Agent Teams failures is multiple teammates editing the same file. Design task boundaries around file or directory ownership.

**Use broad permissions or `--dangerously-skip-permissions`.** Teammates inherit the lead's permission settings. If the lead requires prompts, teammates stall with nobody to approve them. Inside a Docker Sandbox, full permissions are safe.

**Monitor with keyboard shortcuts.** `Shift+Up/Down` cycles through teammates in in-process mode. `Ctrl+T` shows the shared task list. `Enter` views a teammate's session. `Escape` interrupts.

### Agent Teams Limitations

- **Experimental:** Breaking changes may occur between Claude Code versions
- **No session resumption:** `/resume` doesn't restore in-process teammates
- **No nested teams:** Teammates cannot spawn their own teams
- **One team per session:** Clean up the current team before starting a new one
- **Token cost:** A 3-teammate team uses roughly 3-4x the tokens of a single session
- **Task status can lag:** Teammates sometimes fail to mark tasks complete; nudge the lead if tasks appear stuck
- **No file-level locking:** Work around this through task design — assign file ownership

### Agent Teams Security Properties

- **Teammates inherit all permissions** from the lead, including `--dangerously-skip-permissions`. This cannot be scoped per-teammate.
- **Teammates auto-load CLAUDE.md, MCP servers, and skills** from the project, but not the lead's conversation history.
- **Hooks fire independently per teammate.** Each teammate triggers PreToolUse/PostToolUse hooks on its own tool calls. Your write guard, audit gate, and injection screen protect all teammates.
- **The sandbox is the security boundary**, not per-teammate permissions. A compromised teammate has the same access as any other session in the sandbox.

---

## 3. Worktree Isolation (Native Agent Tool)

Use the Agent tool with `isolation: "worktree"` for branch-level isolation. This creates a temporary git worktree so the agent works on an isolated copy of the repo.

### When to Use Worktree Isolation

- You want agents working on **separate git branches** with independent commit histories
- You need to **merge results via PR** rather than having agents edit a shared working tree
- You want to **compare competing approaches** on separate branches and pick the best one

### Usage

Use the Agent tool directly:

```
Agent tool with:
  isolation: "worktree"
  run_in_background: true
  prompt: "Implement JWT authentication in src/auth/"
```

Or use the helper script for manual worktree creation:

```bash
./scripts/create-worktree.sh feature-auth
```

### Worktree Security Properties

- Each worktree inherits `.claude/settings.json` from git, so hooks are automatically present.
- If you use `.claude/settings.local.json` (gitignored), copy it manually.
- Each agent gets its own context window and API quota.

---

## Combining Patterns

The patterns compose well. A common production setup:

```
Docker Sandbox (microVM)
└── Main Claude session
    ├── Built-in Explore subagent (automatic, read-only, cheap)
    ├── Custom security-reviewer subagent (read-only, Sonnet)
    ├── Agent Team (3 teammates on shared feature)
    │   ├── Teammate: backend API
    │   ├── Teammate: frontend components
    │   └── Teammate: integration tests
    └── Background agent with worktree isolation (long-running refactor on another branch)
```

The Agent Team and Ralph loop run concurrently inside the same sandbox. All share the same network deny-policy, credential proxy, and microVM isolation. Hooks fire on every tool call from every agent, teammate, and subagent.

---

## Security Summary

| | Hooks fire? | Inherits permissions? | Can communicate? | Isolated context? |
|---|---|---|---|---|
| **Built-in subagents** | Yes, same hooks as parent | Yes (can restrict tools) | Returns to parent only | Yes, own context window |
| **Agent Team teammates** | Yes, independent per teammate | Yes (cannot restrict) | Yes, direct messaging + shared tasks | Yes, own context window |
| **Worktree agents** | Yes, same hooks as parent | Yes (inherits from parent) | Returns to parent only | Yes, isolated worktree |

The sandbox is always the security boundary. Per-agent tool restrictions and hooks are defense-in-depth.
