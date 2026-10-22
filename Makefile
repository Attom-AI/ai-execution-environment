.DEFAULT_GOAL := help

.PHONY: help bootstrap doctor validate repos-clone repos-status repos-fetch

help:
	@printf '%s\n' \
	  'bootstrap     Create local directories and run environment checks' \
	  'doctor        Check required workspace tools' \
	  'validate      Validate configuration and shell scripts' \
	  'repos-clone   Clone repositories missing from repos/' \
	  'repos-status  Show branch and working-tree state for each repository' \
	  'repos-fetch   Fetch and prune remote refs without changing branches'

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

