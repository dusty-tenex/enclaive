# Guardrails AI sidecar — runs the validation server on port 8000.
# Models and validators loaded once at startup, warm for every request.
# Read-only filesystem in production: the agent cannot tamper with it.
FROM python:3.12-slim@sha256:2be8daddfd700d5336eb090a2bc6c65b8fc5e60ead845ef7e4862529d8c129c4

WORKDIR /app

# Install guardrails + detect-secrets (pinned versions — CG-5)
RUN pip install --no-cache-dir \
    guardrails-ai==0.9.1 \
    guardrails-api==0.2.1 \
    detect-secrets==1.5.0 \
    gunicorn==22.0.0 && \
    python3 -c "import guardrails; import detect_secrets; print('Core packages verified')"

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

COPY config.py /app/config.py

# Non-root user (CG-3)
RUN useradd -r guardrails
USER guardrails

EXPOSE 8000

# Production: gunicorn with 2 workers (CPU-bound validation)
# Dev: guardrails start --config config.py
CMD ["gunicorn", \
     "--bind", "0.0.0.0:8000", \
     "--timeout", "30", \
     "--workers", "2", \
     "--worker-class", "gthread", \
     "--threads", "4", \
     "guardrails_api.app:create_app(None, 'config.py')"]
