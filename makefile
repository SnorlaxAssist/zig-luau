.PHONY: test docs

test:
	zig build test --summary failures

docs:
	zig build docs
