# compiler/Makefile
#
# Per-side entry points for the Go transpiler module. The top-level
# repo Makefile (added later in Phase 02) calls these targets via
# `make -C compiler <target>`. Targets here must therefore be
# self-contained and assume `compiler/` is the working directory.
#
# Targets:
#   test       — race-enabled unit tests for every package in the module.
#   coverage   — atomic-mode coverage profile + `go tool cover -func`
#                summary; artifact lands at compiler/coverage.out.
#   lint       — golangci-lint (config: ../.golangci.yml, added by the
#                Phase 02 linting task). Until that task lands, this is
#                a soft no-op so `make ci` does not block the coverage
#                roadmap item.
#   clean      — remove the coverage profile and any built binaries.

.PHONY: test coverage lint clean

GO ?= go
# Resolve the repo root from this Makefile's location so the targets
# work regardless of the caller's CWD (`make -C compiler ...` from root,
# direct invocation from compiler/, CI checkout layouts, etc.).
COMPILER_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ROOT := $(abspath $(COMPILER_DIR)/..)

test:
	$(GO) test -race -count=1 ./...

coverage:
	$(ROOT)/tools/coverage_go.sh

lint:
	$(ROOT)/tools/lint_go.sh

clean:
	rm -f $(COMPILER_DIR)/coverage.out
	rm -rf $(COMPILER_DIR)/bin
