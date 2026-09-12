# Destination precedence: an explicit SIM= (command line or environment) wins;
# otherwise this worktree's dedicated simulator from .simulator_id (created by
# the addworktree/takeoff fish functions); otherwise the shared default device.
SIM_FROM_WORKTREE := $(shell test -f .simulator_id && printf 'platform=iOS Simulator,id=%s' "$$(cat .simulator_id)")
SIM ?= $(if $(SIM_FROM_WORKTREE),$(SIM_FROM_WORKTREE),platform=iOS Simulator,name=iPhone 17)
MAC_SIM := platform=macOS
SCHEME := CheckStitch
CONFIGURATION := Debug
DERIVED_DATA := DerivedData
APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphonesimulator/$(SCHEME).app
MAC_APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(SCHEME).app

.PHONY: build build-mac run clean test test-unit test-ui

build:
	xcodebuild -scheme '$(SCHEME)' \
	  -destination '$(SIM)' \
	  -configuration '$(CONFIGURATION)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  build

# The macOS slice shares the source files with iOS but not the available API,
# so it needs its own compile even though nothing here launches it. Unsigned:
# signing would need the Mac profile to carry the App Group entitlement.
build-mac:
	xcodebuild -scheme '$(SCHEME)' \
	  -destination 'platform=macOS' \
	  -configuration '$(CONFIGURATION)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  CODE_SIGNING_ALLOWED=NO \
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
