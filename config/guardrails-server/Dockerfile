# Guardrails AI sidecar -- runs the validation server on port 8000.
# Models and validators loaded once at startup, warm for every request.
# Read-only filesystem in production: the agent cannot tamper with it.
FROM python:3.12-slim@sha256:2be8daddfd700d5336eb090a2bc6c65b8fc5e60ead845ef7e4862529d8c129c4

WORKDIR /app

# Install guardrails + detect-secrets + ML dependencies (pinned versions -- CG-5)
RUN pip install --no-cache-dir \
    guardrails-ai==0.9.1 \
    guardrails-api==0.2.1 \
    detect-secrets==1.5.0 \
    gunicorn==22.0.0 \
    transformers==4.47.0 \
    safetensors==0.4.5 && \
    pip install --no-cache-dir \
    torch --extra-index-url https://download.pytorch.org/whl/cpu && \
    python3 -c "import guardrails; import detect_secrets; import transformers; print('Core packages verified')"

# Install shfmt binary
ARG SHFMT_VERSION=3.10.0
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates && \
    ARCH=$(dpkg --print-architecture) && \
    curl -fsSL "https://github.com/mvdan/sh/releases/download/v${SHFMT_VERSION}/shfmt_v${SHFMT_VERSION}_linux_${ARCH}" \
      -o /usr/local/bin/shfmt && \
    chmod +x /usr/local/bin/shfmt && \
    shfmt --version && \
    apt-get purge -y curl && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

# Install Hub validators (free API key from hub.guardrailsai.com)
# Pass --build-arg GUARDRAILS_TOKEN=your-token, or set env before build.
ARG GUARDRAILS_TOKEN=""
RUN if [ -n "$GUARDRAILS_TOKEN" ]; then \
      guardrails configure --token "$GUARDRAILS_TOKEN" --enable-metrics false && \
      guardrails hub install hub://guardrails/secrets_present --quiet && \
      guardrails hub install hub://guardrails/guardrails_pii --quiet && \
      guardrails hub install hub://guardrails/detect_jailbreak --quiet && \
      guardrails hub install hub://guardrails/unusual_prompt --quiet && \
      guardrails hub install hub://guardrails/detect_pii --quiet && \
      echo "[OK] Hub validators installed"; \
    else \
      echo "[WARN] GUARDRAILS_TOKEN not set -- Hub validators not installed"; \
    fi

# Download Sentinel v2 model at build time (no token needed)
RUN python3 -c "from transformers import pipeline; pipeline('text-classification', model='protectai/sentinel-v2')" && \
    echo "[OK] Sentinel v2 model cached"

# Download Prompt Guard 2 model at build time (needs HF_TOKEN)
ARG HF_TOKEN=""
RUN if [ -n "$HF_TOKEN" ]; then \
      HF_TOKEN="$HF_TOKEN" python3 -c "from transformers import pipeline; pipeline('text-classification', model='meta-llama/Prompt-Guard-2-86M')" && \
      echo "[OK] Prompt Guard 2 model cached"; \
    else \
      echo "[WARN] HF_TOKEN not set -- Prompt Guard 2 model not cached"; \
    fi

COPY config.py /app/config.py
COPY warmup.py /app/warmup.py

# Non-root user (CG-3)
RUN useradd -r guardrails
USER guardrails

EXPOSE 8000

# Production: warmup models then start gunicorn with 2 workers (CPU-bound validation)
# Dev: guardrails start --config config.py
CMD python3 /app/warmup.py && gunicorn \
    --bind 0.0.0.0:8000 \
    --timeout 30 \
    --workers 2 \
    --worker-class gthread \
    --threads 4 \
    "guardrails_api.app:create_app(None, 'config.py')"
