# Appendix C: Domain Allowlist Reference

| Domain | Purpose | Required? |
|--------|---------|-----------|
| `api.anthropic.com` | Claude API | Yes |
| `sentry.io` | Crash reporting | Optional |
| `statsig.com` / `events.statsig.com` | Feature flags | Optional |
| `statsig.anthropic.com` | Anthropic analytics | Optional |
| `registry.npmjs.org` | npm packages | If using npm |
| `github.com` / `api.github.com` | Git operations | If using GitHub |
| `pypi.org` / `files.pythonhosted.org` | Python packages | If using pip |
| `rubygems.org` | Ruby gems | If using Ruby |
| `dl.google.com` | Chrome/Puppeteer | If using browser tools |

> **Intentionally omitted:** `*.githubusercontent.com` — serves raw file content from *all* public GitHub repos. Adding it allows a prompt-injected agent to fetch and execute arbitrary code. Only add it if your workflow requires raw GitHub content.
