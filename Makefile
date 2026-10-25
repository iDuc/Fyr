XCODE_DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
DESTINATION ?= platform=iOS Simulator,name=iPhone 17
SCHEME ?= Fyr
PROJECT ?= Fyr.xcodeproj

export XCODE_DEVELOPER_DIR

.PHONY: bootstrap doctor verify build test clean list

bootstrap:
	@scripts/bootstrap-mac-mini.sh

doctor:
	@scripts/codex-doctor.sh

verify: doctor list build test

build:
	@scripts/xcodebuild-fyr.sh -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" build

test:
	@if find . -maxdepth 3 \( -name '*Tests.swift' -o -name '*UITests.swift' \) | grep -q .; then \
		scripts/xcodebuild-fyr.sh -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" test; \
	else \
		printf "No test sources found; skipping xcodebuild test.\\n"; \
	fi

clean:
	@scripts/xcodebuild-fyr.sh -project "$(PROJECT)" -scheme "$(SCHEME)" clean

list:
	@scripts/xcodebuild-fyr.sh -list -project "$(PROJECT)"
