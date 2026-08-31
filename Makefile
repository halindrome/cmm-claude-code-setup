# Test entry point for cmm-claude-code-setup. Each tests/test-*.sh is
# self-contained and exits non-zero on failure; this just runs them all.

TESTS := $(sort $(wildcard tests/test-*.sh))

.PHONY: test
test:
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
