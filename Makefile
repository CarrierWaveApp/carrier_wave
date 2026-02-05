.PHONY: build build-device test test-unit test-log-management test-performance test-performance-quick devices install launch deploy clean lint format format-check setup-hooks release warnings

DEVICE_NAME := theseus
BUNDLE_ID := com.jsvana.FullDuplex
PROJECT := CarrierWave.xcodeproj
SCHEME := CarrierWave
SIMULATOR := iPhone 17 Pro

# Find the most recent DerivedData directory for this project
DERIVED_DATA = $(shell ls -td ~/Library/Developer/Xcode/DerivedData/CarrierWave-* 2>/dev/null | head -n1)

# Build for simulator (default)
build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)' build

# Build for device
build-device:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS,name=$(DEVICE_NAME)' build

# Run all tests
test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)' test

# Run unit tests only (excludes performance tests)
test-unit:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)' \
		-skip-testing:CarrierWaveTests/QSOStatisticsPerformanceTests \
		test

# Run log management tests only
test-log-management:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)' \
		-only-testing:CarrierWaveTests/LoggingSessionManagerTests \
		-only-testing:CarrierWaveTests/LoggingSessionTests \
		-only-testing:CarrierWaveTests/ServicePresenceTests \
		-only-testing:CarrierWaveTests/MetadataModeTests \
		-only-testing:CarrierWaveTests/DeduplicationServiceTests \
		-only-testing:CarrierWaveTests/ImportServiceTests \
		test

# Run quick performance tests (for CI - 50k QSOs, ~1-2 min)
test-performance-quick:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)' \
		-only-testing:CarrierWaveTests/QSOStatisticsPerformanceTests/testQuickStatisticsPerformance \
		test

# Run full performance tests (pre-release validation - 500k QSOs, ~5-10 min)
test-performance:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)' \
		-only-testing:CarrierWaveTests/QSOStatisticsPerformanceTests \
		test

# List available devices
devices:
	xcrun xctrace list devices

# Install app on device (requires build-device first)
install:
	xcrun devicectl device install app --device $(DEVICE_NAME) \
		"$(DERIVED_DATA)/Build/Products/Debug-iphoneos/CarrierWave.app"

# Launch app on device
launch:
	xcrun devicectl device process launch --device $(DEVICE_NAME) $(BUNDLE_ID)

# Build, install, and launch on device
deploy: build-device install launch

# Clean build artifacts
clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
	rm -rf ~/Library/Developer/Xcode/DerivedData/CarrierWave-*

# Lint Swift files
lint:
	swiftlint lint --strict 2>&1 | rg -v "Linting"

# Format Swift files
format:
	swiftformat .

# Check formatting without modifying files
format-check:
	swiftformat --lint .

# Setup pre-commit hooks (call from project root)
setup-hooks:
	@echo "Adding pre-commit script to git hooks..."
	@echo '#!/usr/bin/env bash' > .git/hooks/pre-commit.local
	@echo 'scripts/pre-commit.sh' >> .git/hooks/pre-commit.local
	@chmod +x .git/hooks/pre-commit.local
	@echo "Done. The bd hook will call scripts/pre-commit.sh"
	@echo ""
	@echo "To enable, add this to your bd pre-commit hook or run:"
	@echo "  ./scripts/pre-commit.sh"

# Release a new version (creates git tag and notifies Discord)
# Usage: make release VERSION=1.15.0
release:
ifndef VERSION
	$(error VERSION is required. Usage: make release VERSION=1.15.0)
endif
	./scripts/release.sh $(VERSION)

# Show all build warnings (sorted and deduplicated)
warnings:
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)' \
		build 2>&1 | \
		grep -E "warning:" | \
		sed 's|^.*/CarrierWave/|CarrierWave/|' | \
		sort -u
