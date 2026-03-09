# Custom Templates

Instead of having Claude install tools every session, build a custom template with everything pre-loaded.

## Create the Dockerfile

A ready-to-customize Dockerfile is included at [`config/Dockerfile`](../config/Dockerfile). Copy it into your build directory:

```bash
mkdir -p enclaive-template
cp config/Dockerfile enclaive-template/Dockerfile
cp -r scripts/ enclaive-template/scripts/
cd enclaive-template
```

**Before building:** Replace `<REPLACE-WITH-CURRENT-DIGEST>` and `<SHA256-FOR-YOUR-ARCH>` with actual values. See comments in the Dockerfile for how to get them.

## Build and Use

```bash
docker build -t my-enclaive:latest .

# Generate SBOM for compliance (US EO 14028, EU CRA)
syft my-enclaive:latest -o spdx-json > sbom.spdx.json
# Or: docker scout sbom my-enclaive:latest --format spdx-json > sbom.spdx.json

# Launch with your custom template
docker sandbox run -t my-enclaive:latest claude ~/my-project
```

## Save a Running Sandbox

If you've already set up a sandbox perfectly (had Claude install tools, configure things, etc.):

```bash
docker sandbox save claude-my-project my-enclaive:v2
docker sandbox run -t my-enclaive:v2 claude ~/other-project
```

## Share Templates Across Machines

```bash
docker tag my-enclaive:v2 myorg/enclaive:v2
docker push myorg/enclaive:v2
docker sandbox run -t myorg/enclaive:v2 claude ~/project
```

## Bake Audited Plugins Into the Template

For zero-latency starts, pre-install audited plugins at image build time:

```dockerfile
FROM docker/sandbox-templates:claude-code@sha256:<REPLACE-WITH-CURRENT-DIGEST>
USER root
RUN apt-get update && apt-get install -y ripgrep fd-find jq tmux python3

COPY plugins.json /tmp/build/plugins.json
COPY scripts/skill-audit.sh /tmp/build/scripts/skill-audit.sh
COPY scripts/bootstrap-plugins.sh /tmp/build/scripts/bootstrap-plugins.sh

USER agent
RUN cd /tmp/build && \
    export CLAUDE_PROJECT_DIR=/tmp/build && \
    export AUDIT_LOG_DIR=/tmp/build/.audit-logs && \
    bash scripts/bootstrap-plugins.sh && \
    rm -rf /tmp/build

USER agent
```

If a plugin fails audit, the Docker build fails and you see exactly why in the build log.

> **Note:** When using docker compose, this configuration is handled automatically by the sandbox entrypoint. See [Quick Start](01-quick-start.md).
