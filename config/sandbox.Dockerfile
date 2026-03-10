# enclaive sandbox -- Claude Code workspace with hooks and guards pre-installed.
# Runs as root initially (entrypoint locks paths), then drops to sandbox user.
FROM node:20-slim

WORKDIR /home/sandbox

# System dependencies: git, curl, jq, gosu, python3 (for guard scripts)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    jq \
    gosu \
    python3 \
    python3-pip \
    bash \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create sandbox user (non-root, used after entrypoint drops privileges)
RUN useradd -m -s /bin/bash sandbox

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code

# Copy guard scripts, config, canary setup into the image
COPY scripts/ /home/sandbox/.sandbox-scripts/
COPY config/sandbox-entrypoint.sh /home/sandbox/entrypoint.sh
COPY config/CLAUDE.md config/RALPH.md config/settings.json /home/sandbox/.sandbox-config/
COPY config/canary/setup-canaries.sh /home/sandbox/.sandbox-canary/setup-canaries.sh

RUN chmod +x /home/sandbox/entrypoint.sh \
    && chmod +x /home/sandbox/.sandbox-scripts/*.sh 2>/dev/null || true

ENTRYPOINT ["/home/sandbox/entrypoint.sh"]
CMD ["bash"]
