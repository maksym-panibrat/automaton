.PHONY: check test lint fmt clean

check: lint test

lint:
	@command -v shellcheck >/dev/null || { echo "shellcheck required"; exit 1; }
	@find hooks tools lib tests -name '*.sh' -print0 | xargs -0 shellcheck -x

test:
	@bash tests/test-hooks.sh

fmt:
	@command -v shfmt >/dev/null && find hooks tools lib tests -name '*.sh' -print0 | xargs -0 shfmt -w -i 2 -ci || echo "shfmt not installed; skipping"

clean:
	@find . -name '*.tmp' -delete
