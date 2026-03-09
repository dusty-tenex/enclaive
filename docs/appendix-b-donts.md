# Appendix B: What NOT to Do

- **Never run `--dangerously-skip-permissions` on your host machine** — this is the one rule that every real-world incident confirms
- **Never mount `~/.ssh` or `~/.aws` into any sandbox/container** — use proxy-based credential injection instead
- **Never mount `/var/run/docker.sock`** — this gives the agent control of your host Docker
- **Never mount your entire home directory** — defeats the purpose of isolation
- **Never use `--policy allow` with untrusted repos** — prompt injection in code comments can exfiltrate anything reachable
- **Never skip the network policy step** — even with microVM isolation, an unrestricted network lets an agent push secrets to attacker-controlled remotes
- **Never install unaudited skills or plugins** — Snyk's February 2026 audit found 13% contained critical malicious payloads. Always use the audit gate
- **Never leave `.env` files with third-party secrets in the workspace** — even though the Anthropic API key stays on the host, any `.env` in your project syncs into the sandbox. Move secrets to the credential proxy or environment-variable injection
- **Never blindly run host-side commands after an agent session** — review `git diff` before running `make`, `npm install`, `pip install .`, or `just` on the host
- **Never assume sandbox updates happen automatically** — rebuild templates and recreate sandboxes periodically when Claude Code releases security patches
