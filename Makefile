SHELL := /bin/bash
XCB = xcodebuild -project ThermalWatch.xcodeproj -scheme ThermalWatch -quiet -allowProvisioningUpdates
APP = build/Build/Products/Release/ThermalWatch.app

.PHONY: project test build install run

project:
	xcodegen generate --quiet

test: project
	xcodebuild -project ThermalWatch.xcodeproj -scheme ThermalWatch -allowProvisioningUpdates -destination "platform=macOS" -derivedDataPath build test 2>&1 | grep -E "^(✔|✘|􀢄|􁁛|􀟈)|error:|Test run|TEST (SUCCEEDED|FAILED)|recorded an issue" ; exit $${PIPESTATUS[0]}

build: project
	$(XCB) -configuration Debug -derivedDataPath build build

# The helper only works from /Applications (SMAppService requirement).
install: project
	$(XCB) -configuration Release -derivedDataPath build build
	-killall ThermalWatch 2>/dev/null; true
	rm -rf /Applications/ThermalWatch.app
	ditto $(APP) /Applications/ThermalWatch.app

run:
	open /Applications/ThermalWatch.app
