# Test entry point for cmm-claude-code-setup. Each tests/test-*.sh is
# self-contained and exits non-zero on failure; this just runs them all.

TESTS := $(sort $(wildcard tests/test-*.sh))

# Window for `make measure`, in days. Override: make measure DAYS=120
DAYS ?= 30

# An empty TESTS would run nothing and exit 0 — a partial checkout or a `make -C`
# from the wrong root would report clean having verified nothing. Fail loudly instead.
.PHONY: test
test:
	$(if $(TESTS),,$(error no tests/test-*.sh found — run make from the repository root))
	@fail=0; \
	for t in $(TESTS); do \
	  if bash "$$t" >/dev/null 2>&1; then \
	    echo "  PASS  $$t"; \
	  else \
	    echo "  FAIL  $$t"; fail=1; \
	  fi; \
	done; \
	if [ $$fail -ne 0 ]; then \
	  echo ""; \
	  echo "Some tests failed. Re-run one for detail:  bash tests/<name>.sh"; \
	fi; \
	exit $$fail

# Measure whether the enforcement stack reaches the conversation stream and
# whether agents change behaviour when it does. Read-only: walks the local
# Claude Code transcripts under ~/.config/claude-code/projects/.
#
# Use it as a BEFORE/AFTER check around any hook change. The number that matters
# is the STRONG anti-pattern rate falling *without* the WEAK rate rising to
# absorb it — that would be migration (head/tail -> sed/awk ranges), not
# improvement. Both scripts report hooks that EMITTED; a hook that exits 0
# silently leaves no trace, so absence is not proof it did not run.
.PHONY: measure
measure:
	@python3 scripts/analyze-enforcement.py $(DAYS)
	@echo ""
	@python3 scripts/analyze-antipatterns.py $(DAYS)
