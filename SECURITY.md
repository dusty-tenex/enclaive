# Security Policy

This is an alpha-stage project. The security boundaries are real but the
implementation is young. We appreciate anyone who takes the time to poke at it.

## Supported Versions

| Version       | Supported |
|---------------|-----------|
| v0.1.0-alpha  | Yes       |
| < v0.1.0-alpha| No        |

Only the latest alpha release receives security fixes. Older tags are
unsupported.

## Scope

### What counts as a security issue

- **Guard bypass** — input or output that evades a guard's screening logic.
- **Credential exfiltration** — any path that leaks secrets, API keys, or
  tokens out of the sandbox.
- **Injection survival** — prompt-injection payloads that pass through
  screening and reach a downstream model or tool intact.
- **Canary token detection evasion** — techniques that prevent a canary token
  from being detected when it should be.

If you can get data past a guard, exfiltrate a canary token, or inject instructions that survive screening — that's a valid security report and we want to hear about it.

### What does NOT count

- **Known gaps already documented in README** — if the README already calls
  something out as a limitation, it is not a new finding. Feel free to open a
  regular issue if you think the documented gap is more severe than described.
- **Issues with Docker Desktop itself** — bugs or vulnerabilities in Docker
  Desktop, the Docker Engine, or the underlying VM layer are outside our
  control. Report those upstream to Docker.

## Reporting a Vulnerability

### Preferred: GitHub Security Advisories

Open a draft advisory through the repository's **Security** tab on GitHub.
This keeps the report private until a fix is ready.

### Alternative: Email

Send details to the maintainer address listed in the repository. Include
enough information to reproduce the issue: steps, payloads, and the version
you tested against.

**Do not open a public issue for security vulnerabilities.** Public disclosure
before a fix is available puts users at risk.

## Response SLA

- **Acknowledgement** — within 48 hours of receipt.
- **Triage** — within 7 days we will confirm whether the report is accepted,
  request more information, or explain why it is out of scope.

These timelines are best-effort. This is an alpha-stage side project, not the
maintainer's day job. We will do our best.

## What Happens Next

Accepted reports follow this process:

1. We develop and test a fix on a private branch.
2. The fix is released in the next patch or minor version.
3. The reporter is credited in the CHANGELOG unless they prefer anonymity.
   Let us know your preference when you file the report.
4. Bypass reports become new test cases in the fixtures repo so the same
   class of issue is caught by CI going forward.

## Credit

We believe reporters deserve recognition. By default, your name (or handle)
and a short description of the finding will appear in the CHANGELOG entry for
the release that includes the fix. If you prefer to remain anonymous, just say
so in your report.
