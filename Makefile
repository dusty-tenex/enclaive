# enclAIve — Makefile
# Convenience targets for common operations.

PROJECT ?= ~/my-project
SANDBOX_NAME ?= claude-$(shell basename $(PROJECT))

.PHONY: help setup launch stop destroy logs network-log worktree docs clean build-template bypass-guards reset-guards

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-16s\033[0m %s\n", $$1, $$2}'

setup: ## Run the full installer (usage: make setup PROJECT=~/my-project)
	./setup.sh $(PROJECT)

launch: ## Enter an existing sandbox
	docker sandbox run $(SANDBOX_NAME)

stop: ## Stop the sandbox (preserves state)
	docker sandbox stop $(SANDBOX_NAME)

destroy: ## Destroy the sandbox completely
	docker sandbox rm $(SANDBOX_NAME)

logs: ## Show sandbox network logs
	docker sandbox network log $(SANDBOX_NAME)

worktree: ## Create a worktree (usage: make worktree BRANCH=feature-auth)
	cd $(PROJECT) && ./scripts/create-worktree.sh $(BRANCH)

build-template: ## Build standalone template (auto-fetches digest and delta hash)
	@echo "Pulling latest claude-code sandbox template..."
	docker pull docker/sandbox-templates:claude-code
	$(eval DIGEST := $(shell docker inspect --format='{{index .RepoDigests 0}}' docker/sandbox-templates:claude-code | sed 's/.*@sha256://'))
	@echo "Detected digest: $(DIGEST)"
	$(eval ARCH := $(shell uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/'))
	@echo "Detected arch: $(ARCH)"
	@echo "Fetching git-delta sha256 for $(ARCH)..."
	$(eval DELTA_URL := https://github.com/dandavison/delta/releases/download/0.18.2/git-delta_0.18.2_$(ARCH).deb)
	$(eval DELTA_SHA := $(shell curl -sfL $(DELTA_URL) | shasum -a 256 | cut -d' ' -f1))
	@echo "Delta sha256: $(DELTA_SHA)"
	@sed 's/<REPLACE-WITH-CURRENT-DIGEST>/$(DIGEST)/' config/Dockerfile.standalone-template | \
		sed 's/<SHA256-FOR-YOUR-ARCH>/$(DELTA_SHA)/' > Dockerfile.standalone
	@echo "[OK] Generated: Dockerfile.standalone"
	@echo "   Build with: docker build -f Dockerfile.standalone -t my-sandbox ."

bypass-guards: ## Create guard bypass files (for reviewed installs)
	@mkdir -p /tmp/sandbox-guard-bypass
	@touch /tmp/sandbox-guard-bypass/bypass-write-guard
	@touch /tmp/sandbox-guard-bypass/bypass-memory-guard
	@touch /tmp/sandbox-guard-bypass/bypass-exfil-guard
	@touch /tmp/sandbox-guard-bypass/bypass-audit-gate
	@echo "[WARN] All guards bypassed. Run 'make reset-guards' to re-enable."

reset-guards: ## Remove guard bypass files (re-enable all guards)
	@rm -f /tmp/sandbox-guard-bypass/bypass-*
	@echo "[OK] All guards re-enabled."

docs: ## Serve documentation locally with GitBook
	npx gitbook serve

clean: ## Remove build artifacts
	rm -rf _book node_modules Dockerfile.standalone
