# Destination precedence: an explicit SIM= (command line or environment) wins;
# otherwise this worktree's dedicated simulator from .simulator_id (created by
# the addworktree/takeoff fish functions); otherwise the shared default device.
SIM_FROM_WORKTREE := $(shell test -f .simulator_id && printf 'platform=iOS Simulator,id=%s' "$$(cat .simulator_id)")
SIM ?= $(if $(SIM_FROM_WORKTREE),$(SIM_FROM_WORKTREE),platform=iOS Simulator,name=iPhone 17)
MAC_SIM := platform=macOS
WATCH_SIM := generic/platform=watchOS Simulator
WATCH_SCHEME := CheckStitchWatch
SCHEME := CheckStitch
CONFIGURATION := Debug
DERIVED_DATA := DerivedData
# Gate legs compile with warnings as errors: a compiler warning fails the leg.
# scripts/test.sh and CI inherit this through the make recipes; local Xcode
# builds and project.pbxproj are untouched. `build-mac-signed`,
# run-watch.sh and run-devices.sh are device helpers and deliberately excluded.
WARNINGS_AS_ERRORS := SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES
APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphonesimulator/$(SCHEME).app
MAC_APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(SCHEME).app

.PHONY: build build-mac build-mac-signed run clean test test-unit test-ui watch-build

build:
	xcodebuild -scheme '$(SCHEME)' \
	  -destination '$(SIM)' \
	  -configuration '$(CONFIGURATION)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  build

# The macOS slice shares the source files with iOS but not the available API,
# so it needs its own compile. `build-mac` is the gate's unsigned compile leg
# (headless, no signing needed); `build-mac-signed` is the runnable macOS app,
# team-signed so CheckStitch/AppGroup.entitlements (incl. the KVS
# `com.apple.developer.ubiquity-kvstore-identifier`) lands in the embedded
# provisioning profile and the key-value store syncs through iCloud.
build-mac:
	xcodebuild -scheme '$(SCHEME)' \
	  -destination 'platform=macOS' \
	  -configuration '$(CONFIGURATION)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  CODE_SIGNING_ALLOWED=NO \
	  $(WARNINGS_AS_ERRORS) \
	  build

# Signed macOS leg. Requires the Mac provisioning profile for the development
# team; `-allowProvisioningUpdates` fetches it when it isn't cached yet.
build-mac-signed:
	xcodebuild -scheme '$(SCHEME)' \
	  -destination 'platform=macOS' \
	  -configuration '$(CONFIGURATION)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  -allowProvisioningUpdates \
	  build

# The watch target compiles the same package for watchOS. `generic/platform=watchOS
# Simulator` keeps this unsigned and sim-free; the real-watch build is run-watch.sh.
watch-build:
	xcodebuild -scheme '$(WATCH_SCHEME)' \
	  -destination '$(WATCH_SIM)' \
	  -configuration '$(CONFIGURATION)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  build

run: build
	bash scripts/run-simulator.sh '$(SIM)' '$(APP)'

test: test-unit test-ui

# Unit suites run on the macOS host: unsigned, no simulator boot, no App Group gap.
# `SWIFT_DEFAULT_ACTOR_ISOLATION` is not set on test targets, so suites opt in per-suite.
test-unit:
	xcodebuild -scheme '$(SCHEME)' \
	  -destination '$(MAC_SIM)' \
	  -configuration '$(CONFIGURATION)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  CODE_SIGNING_ALLOWED=NO \
	  -only-testing:CheckStitchTests \
	  test

# Exactly one UI smoke case, on this worktree's dedicated simulator (never a
# bare `name=` destination).
test-ui:
	xcodebuild -scheme '$(SCHEME)' \
	  -destination '$(SIM)' \
	  -configuration '$(CONFIGURATION)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  build-for-testing
	xcodebuild -scheme '$(SCHEME)' \
	  -destination '$(SIM)' \
	  -configuration '$(CONFIGURATION)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  -only-testing:CheckStitchUITests \
	  test-without-building

clean:
	xcodebuild -scheme '$(SCHEME)' -destination '$(SIM)' clean
