# Appendix A: Devcontainer Fallback

If you can't use Docker Sandboxes (Docker Desktop < 4.62, or CI/CD pipelines), the devcontainer approach still works. It provides container-level (not microVM-level) isolation with manual iptables firewalling.

See the [Anthropic reference devcontainer](https://github.com/anthropics/claude-code/tree/main/.devcontainer) for the official baseline, or the [Trail of Bits devcontainer](https://github.com/trailofbits/claude-code-devcontainer) for a security-focused variant.

## Comparison

| Feature | Docker Sandboxes | Devcontainer |
|---------|-----------------|-------------|
| Isolation | microVM (own kernel) | Container (shared kernel) |
| Docker-in-Docker | Own daemon, works natively | Requires privileged mode or socket |
| Network filtering | Built-in proxy + `docker sandbox network proxy` | Manual iptables/ipset |
| Credentials | Proxy injection (never in VM) | Mounted or env var (inside container) |
| Setup | One command | Dockerfile + devcontainer.json + firewall script |
| Container escape risk | Stays inside VM | Escapes to host kernel |
