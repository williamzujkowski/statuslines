# statuslines — one-command bootstrap and verify (AGENTS.md §10.3)
.DEFAULT_GOAL := help
SHELL := bash

BATS    ?= bats
SHFMT   ?= shfmt
SHCHECK ?= shellcheck

SH_FILES := statusline.sh bench/bench.sh $(shell find lib scripts -name '*.sh' 2>/dev/null) scripts/commit-msg

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

.PHONY: setup
setup: ## Install dev tooling and git hooks; report what is missing
	@bash scripts/setup.sh

.PHONY: check
check: lint fmt-check test bench ## Run the full gate (lint, format, tests, benchmark)
	@printf '\n\033[32mAll checks passed.\033[0m\n'

.PHONY: lint
lint: ## shellcheck every shell file
	@$(SHCHECK) -x --severity=style --shell=bash $(SH_FILES)
	@printf '\033[32mshellcheck clean\033[0m\n'

.PHONY: fmt
fmt: ## Format shell files in place
	@$(SHFMT) -w -i 2 -ci -bn $(SH_FILES)

.PHONY: fmt-check
fmt-check: ## Verify formatting without writing
	@$(SHFMT) -d -i 2 -ci -bn $(SH_FILES)
	@printf '\033[32mformatting clean\033[0m\n'

.PHONY: test
test: ## Run the bats suite
	@$(BATS) --print-output-on-failure test/

.PHONY: bench
bench: ## Measure render latency against the budget in AGENTS.md §4.4
	@bash bench/bench.sh

.PHONY: demo
demo: ## Render every theme against every fixture, to a real terminal
	@bash scripts/demo.sh

.PHONY: golden
golden: ## Regenerate golden files (review the diff before committing!)
	@bash scripts/regen-golden.sh

.PHONY: bundle
bundle: ## Build the single-file dist/statusline.sh
	@bash scripts/bundle.sh dist/statusline.sh
