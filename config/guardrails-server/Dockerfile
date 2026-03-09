# Guardrails AI sidecar -- runs the validation server on port 8000.
# Models and validators loaded once at startup, warm for every request.
# Read-only filesystem in production: the agent cannot tamper with it.
FROM python:3.12-slim@sha256:ccc7089399c8bb65dd1fb3ed6d55efa538a3f5e7fca3f5988ac3b5b87e593bf0

WORKDIR /app

# Install guardrails + detect-secrets + ML dependencies (pinned versions -- CG-5)
RUN pip install --no-cache-dir \
    guardrails-ai==0.9.1 \
    guardrails-api==0.2.1 \
    "rich<14.0.0" \
    detect-secrets==1.5.0 \
    gunicorn==22.0.0 \
    uvicorn==0.34.0 \
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
# Pass via BuildKit secret to avoid leaking token in image layers:
#   docker build --secret id=guardrails_token,env=GUARDRAILS_TOKEN
RUN --mount=type=secret,id=guardrails_token \
    GUARDRAILS_TOKEN=$(cat /run/secrets/guardrails_token 2>/dev/null) && \
    if [ -n "$GUARDRAILS_TOKEN" ]; then \
      guardrails configure --token "$GUARDRAILS_TOKEN" --disable-metrics --disable-remote-inferencing && \
      guardrails hub install hub://guardrails/secrets_present --quiet && \
      guardrails hub install hub://guardrails/guardrails_pii --quiet && \
      guardrails hub install hub://guardrails/detect_jailbreak --quiet && \
      guardrails hub install hub://guardrails/unusual_prompt --quiet && \
      guardrails hub install hub://guardrails/detect_pii --quiet && \
      echo "[OK] Hub validators installed"; \
    else \
      echo "[WARN] GUARDRAILS_TOKEN not set -- Hub validators not installed"; \
    fi

# Download ML models at build time (both require HF_TOKEN -- Sentinel v2 went gated)
RUN --mount=type=secret,id=hf_token \
    HF_TOKEN=$(cat /run/secrets/hf_token 2>/dev/null) && \
    if [ -n "$HF_TOKEN" ]; then \
      HF_TOKEN="$HF_TOKEN" python3 -c "from transformers import pipeline; pipeline('text-classification', model='protectai/sentinel-v2')" && \
      echo "[OK] Sentinel v2 model cached" && \
      HF_TOKEN="$HF_TOKEN" python3 -c "from transformers import pipeline; pipeline('text-classification', model='meta-llama/Prompt-Guard-2-86M')" && \
      echo "[OK] Prompt Guard 2 model cached"; \
    else \
      echo "[WARN] HF_TOKEN not set -- ML models not cached (Sentinel v2, Prompt Guard 2)"; \
    fi

COPY config.py /app/config.py
COPY warmup.py /app/warmup.py

# Non-root user (CG-3)
RUN useradd -r guardrails
USER guardrails

EXPOSE 8000

# Production: warmup models then start gunicorn with uvicorn ASGI workers
# Dev: guardrails start --config config.py
CMD python3 /app/warmup.py && gunicorn \
    --bind 0.0.0.0:8000 \
    --timeout 30 \
    --workers 2 \
    --worker-class uvicorn.workers.UvicornWorker \
    "guardrails_api.app:create_app(None, 'config.py')"
