BINARY_NAME := xcfb

.PHONY: all
all: build

.PHONY: build
build:
	@echo "Building $(BINARY_NAME)..."
	swift build

.PHONY: build-release
build-release:
	@echo "Building $(BINARY_NAME) release binary..."
	swift build -c release

.PHONY: test
test:
	@echo "Running tests..."
	swift test

.PHONY: format
format:
	@echo "Formatting Swift sources..."
	swift format -i -r Sources Tests Package.swift

.PHONY: format-check
format-check:
	@echo "Checking Swift formatting..."
	swift format lint -r Sources Tests Package.swift

.PHONY: generate-command-docs
generate-command-docs:
	@echo "Generating command docs..."
	python3 scripts/generate-command-docs.py

.PHONY: check-command-docs
check-command-docs:
	@echo "Checking command docs..."
	python3 scripts/generate-command-docs.py --check

.PHONY: check-package-surface
check-package-surface:
	@echo "Checking executable-only package surface..."
	python3 scripts/check-package-surface.py

.PHONY: check
check: test check-package-surface check-command-docs build-release

.PHONY: clean
clean:
	rm -rf .build
