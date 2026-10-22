.DEFAULT_GOAL := help

MODE ?= auto
INTERFACE ?= unspecified
PROVIDER ?= auto

.PHONY: help setup-plan setup setup-status bootstrap doctor validate repos-clone repos-status repos-fetch

help:
	@printf '%s\n' \
	  'setup-plan    Inspect prerequisites and print an agent-guided setup plan' \
	  'setup         Materialize the selected setup profile without authenticating' \
	  'setup-status  Show locally saved setup preferences' \
	  'bootstrap     Create local directories and run environment checks' \
	  'doctor        Check required workspace tools' \
	  'validate      Validate configuration and shell scripts' \
	  'repos-clone   Clone repositories missing from repos/' \
	  'repos-status  Show branch and working-tree state for each repository' \
	  'repos-fetch   Fetch and prune remote refs without changing branches'

setup-plan:
	@SETUP_MODE="$(MODE)" AGENT_INTERFACE="$(INTERFACE)" GIT_PROVIDER="$(PROVIDER)" ./scripts/setup plan

setup:
	@SETUP_MODE="$(MODE)" AGENT_INTERFACE="$(INTERFACE)" GIT_PROVIDER="$(PROVIDER)" ./scripts/setup apply

setup-status:
	@./scripts/setup status

bootstrap:
	@./scripts/bootstrap

doctor:
	@./scripts/doctor

validate:
	@./scripts/validate

repos-clone:
	@./scripts/repos-clone

repos-status:
	@./scripts/repos-status

repos-fetch:
	@./scripts/repos-fetch

