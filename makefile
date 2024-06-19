.PHONY: test docs

test:
	zig build test --summary all

docs:
	zig build docs
