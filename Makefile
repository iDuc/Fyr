XCODE_DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
SCHEME ?= Fyr
PROJECT ?= Fyr.xcodeproj
DERIVED_DATA ?= /Volumes/ThunderSloerie/BuildArtifacts/Fyr/DerivedData
# Builds need no device.
BUILD_DESTINATION ?= generic/platform=iOS Simulator
# Tests need a concrete iOS 27.1+ simulator. On SloerieServer, run them inside a
# reservation (`make test-reserved`), which sets SIMULATOR_UDID.
TEST_DESTINATION ?= $(if $(SIMULATOR_UDID),id=$(SIMULATOR_UDID),)
SIM_DEVICE ?= duo
SIM_AGENT ?= codex
SIMULATORS ?= /Users/kat/.local/bin/sloerie-simulators
# e.g. SIM_FLAGS=--allow-booted when you booted the device yourself.
SIM_FLAGS ?=

XCODEBUILD = scripts/xcodebuild-fyr.sh -project "$(PROJECT)" -scheme "$(SCHEME)" \
	-derivedDataPath "$(DERIVED_DATA)" -jobs 2

export XCODE_DEVELOPER_DIR

.PHONY: doctor verify build test test-ui build-reserved test-reserved test-ui-reserved clean list

doctor:
	@scripts/codex-doctor.sh

verify: doctor list build-reserved test-reserved

build:
	@$(XCODEBUILD) -destination "$(BUILD_DESTINATION)" build

# Unit and integration tests (FyrTests).
test:
	@if [ -z "$(TEST_DESTINATION)" ]; then \
		echo "No test simulator: run 'make test-reserved' or set TEST_DESTINATION=id=<udid>."; exit 2; \
	fi
	@$(XCODEBUILD) -destination "$(TEST_DESTINATION)" -only-testing:FyrTests \
		-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 test

# UI tests against the fake bridge on 127.0.0.1 (FyrUITests).
test-ui:
	@if [ -z "$(TEST_DESTINATION)" ]; then \
		echo "No test simulator: run 'make test-ui-reserved' or set TEST_DESTINATION=id=<udid>."; exit 2; \
	fi
	@# On an iPhone Duo, start unfolded (another session may have left it closed).
	@if [ -n "$(SIMULATOR_UDID)" ] && [ -x "$(HOME)/.local/bin/hinge" ] && xcrun simctl list devices | grep -q "$(SIMULATOR_UDID)) (Booted)" && xcrun simctl list devices | grep "$(SIMULATOR_UDID)" | grep -q Duo; then \
		"$(HOME)/.local/bin/hinge" -d "$(SIMULATOR_UDID)" open || true; fi
	@$(XCODEBUILD) -destination "$(TEST_DESTINATION)" -only-testing:FyrUITests \
		-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 test

# Shared Mac mini: hold a heavy reservation for the whole build or test run.
build-reserved:
	@$(SIMULATORS) run --heavy $(SIM_FLAGS) --device "$(SIM_DEVICE)" --agent "$(SIM_AGENT)" \
		--task "Fyr build" -- $(MAKE) build

test-reserved:
	@$(SIMULATORS) run --heavy $(SIM_FLAGS) --device "$(SIM_DEVICE)" --agent "$(SIM_AGENT)" \
		--task "Fyr tests" -- $(MAKE) test

test-ui-reserved:
	@$(SIMULATORS) run --heavy $(SIM_FLAGS) --device "$(SIM_DEVICE)" --agent "$(SIM_AGENT)" \
		--task "Fyr UI tests" -- $(MAKE) test-ui

clean:
	@$(XCODEBUILD) clean

list:
	@scripts/xcodebuild-fyr.sh -list -project "$(PROJECT)"
