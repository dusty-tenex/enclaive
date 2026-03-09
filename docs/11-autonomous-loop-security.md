# Part 11: Autonomous Loop Security

Autonomous loop plugins (e.g., [ralph-wiggum](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum)) let Claude iterate on a task unattended. enclAIve does not implement its own loop — use whichever plugin or technique fits your workflow. This page documents the security risks that apply to **any** autonomous loop pattern and how enclAIve's guards mitigate them.

## The Risk: Inter-Iteration Poisoning

Any loop that persists state to disk (progress files, task definitions, memory files) is vulnerable to the **ZombieAgent** pattern:

1. Iteration N is compromised by prompt injection (e.g., from fetched content)
2. The compromised iteration writes malicious instructions into a state file (`progress.md`, `RALPH.md`, etc.)
3. Iteration N+1 reads that file and follows the poisoned instructions
4. The attack persists across iterations without further injection

This is the same inter-session poisoning risk that affects any AI instruction file — autonomous loops just make it more dangerous because there is no human reviewing between iterations.

## How enclAIve Mitigates This

| Guard | What it does |
|-------|-------------|
| `memory-guard.sh` | Screens every write to AI instruction files (CLAUDE.md, progress.md, RALPH.md, subagent memory) for injection patterns. Calls sidecar first, inline fallback second. |
| `memory-integrity.sh` | Checksums AI instruction files at session start. Detects tampering that occurred between sessions. |
| `write-guard.sh` | Blocks writes to host-executable paths, preventing a poisoned iteration from installing git hooks or modifying CI. |
| `exfil-guard.sh` | Limits what a compromised iteration can exfiltrate, even if poisoned. |
| Network deny-by-default | Restricts outbound connections to allowlisted domains, containing blast radius. |
| microVM isolation | The sandbox itself is the hard boundary — a fully compromised loop cannot escape the VM. |

## Residual Risk

- **Intra-session poisoning**: memory-guard catches writes but not reads. If a file is already poisoned when the iteration starts, the guard cannot help.
- **Allowlisted channel exfil**: A poisoned iteration can push encoded data to github.com if it is on the allowlist.
- **Subtle instruction modification**: Regex-based guards catch obvious injection patterns but can miss sophisticated rewording. The Haiku classifier (opt-in) adds a semantic layer.

## Recommendations

1. **Review git diffs between iterations** — `git log --oneline -10` and spot-check diffs if behavior seems off.
2. **Set iteration limits** — most loop plugins support `--max-iterations`. Use it.
3. **Enable `GUARDRAILS_REQUIRE_SIDECAR=1`** — ensures tamper-resistant validation for every write, no inline fallback.
4. **Use the Haiku screening layer** — opt-in via `haiku-injection-screen.sh` for semantic injection detection on inbound content.
