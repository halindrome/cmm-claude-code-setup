# Test entry point for cmm-claude-code-setup. Each tests/test-*.sh is
# self-contained and exits non-zero on failure; this just runs them all.

TESTS := $(sort $(wildcard tests/test-*.sh))

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
