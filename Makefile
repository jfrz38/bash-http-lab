.DEFAULT_GOAL := help

SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c

BASH_FILES := bin/bash-http $(wildcard lib/*.sh) $(wildcard middleware/*.sh) $(wildcard handlers/*.sh) $(wildcard handlers/persistence/*.sh) $(wildcard tests/*.sh) $(wildcard tests/unit/*.sh) $(wildcard tests/integration/*.sh) $(wildcard tests/fixtures/handlers/*.sh)
HOST ?= 127.0.0.1
PORT ?= 8080
OPENAPI_FILE ?= openapi.yaml
COMPOSE ?= docker compose

.PHONY: help
help: ## List public targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {sub("\\\\n",sprintf("\n%22c"," "), $$2);printf " \033[36m%-20s\033[0m  %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: test test-unit test-integration
test: test-unit test-integration ## Run all tests

test-unit: ## Run unit tests
	@for test_file in tests/unit/test-*.sh; do bash "$$test_file"; done

test-integration: ## Run integration tests (requires curl and socat)
	@for test_file in tests/integration/test-*.sh; do bash "$$test_file"; done

.PHONY: lint format format-check
lint: ## Run ShellCheck
	@shellcheck -x -P SCRIPTDIR $(BASH_FILES)

format: ## Format Bash files with shfmt
	@shfmt -w $(BASH_FILES)

format-check: ## Verify Bash formatting
	@shfmt -d $(BASH_FILES)

.PHONY: run check
run: ## Start the local server (OPENAPI_FILE=openapi.yaml HOST=127.0.0.1 PORT=8080)
	@./bin/bash-http serve "$(OPENAPI_FILE)" --host "$(HOST)" --port "$(PORT)"

check: lint format-check test ## Run lint, formatting checks, and all tests

.PHONY: container-build container-check container-up container-down
container-build: ## Build runtime and test container images
	@$(COMPOSE) --profile test build

container-check: ## Run all checks and smoke-test the runtime image in containers
	@check_project="bash-http-lab-check-$${GITHUB_RUN_ID:-local}-$$$$"; \
		cleanup() { \
			status=$$?; \
			if ((status != 0)); then \
				$(COMPOSE) --project-name "$$check_project" logs --no-color server >&2 || true; \
			fi; \
			$(COMPOSE) --project-name "$$check_project" --profile test down --volumes --remove-orphans >/dev/null 2>&1 || true; \
			exit "$$status"; \
		}; \
		trap cleanup EXIT; \
		$(COMPOSE) --project-name "$$check_project" --profile test run --build --rm -T test; \
		$(COMPOSE) --project-name "$$check_project" up --build --wait server; \
		$(COMPOSE) --project-name "$$check_project" exec -T server curl --fail --silent http://127.0.0.1:8080/health >/dev/null

container-up: ## Start the containerized server (PORT=8080)
	@$(COMPOSE) up --build --wait server

container-down: ## Stop and remove sandbox containers
	@$(COMPOSE) --profile test down --remove-orphans
