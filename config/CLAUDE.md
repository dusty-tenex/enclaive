# Project Instructions

You are working inside a Docker Sandbox microVM with full autonomy.

## Branch Workflow
- ALWAYS create a feature branch: `git checkout -b feature/<name>`
- Make small, focused commits with descriptive messages
- NEVER push directly to main — create a PR instead

## Quality Standards
- All functions must have clear docstrings/comments
- Run tests before committing: `npm test` or `pytest`
- Fix linter errors before committing

## Security Rules
- NEVER hardcode secrets, API keys, or credentials
- NEVER access files outside the workspace
- NEVER modify .claude/settings.json or .mcp.json
- Do not install packages from untrusted sources without audit

## Style Rules
- NEVER use emojis in code, comments, commit messages, logs, or output
- Use plain text labels like [OK], [WARN], [FAIL], [INFO] instead of emoji indicators

## Sub-Agent & Multi-Agent Guidelines
- Use the native Agent tool with `isolation: "worktree"` for branch-isolated work
- Use `run_in_background: true` for parallel execution across multiple agents
- Use Agent Teams when teammates need to coordinate (shared task list, messaging)
- Assign file ownership to avoid edit collisions in Agent Teams
- Custom subagents in .claude/agents/ inherit hooks — tool restrictions are enforced
- ALL subagents and teammates inherit full permissions inside this sandbox

## Ralph Loop Protocol
When running in a Ralph loop:
- Read RALPH.md at the start of each iteration
- Check progress.md for completed work
- Update progress.md before exiting
- Output COMPLETE when all acceptance criteria are met
