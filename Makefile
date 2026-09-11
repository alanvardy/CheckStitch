# Destination precedence: an explicit SIM= (command line or environment) wins;
# otherwise this worktree's dedicated simulator from .simulator_id (created by
# the addworktree/takeoff fish functions); otherwise the shared default device.
SIM_FROM_WORKTREE := $(shell test -f .simulator_id && printf 'platform=iOS Simulator,id=%s' "$$(cat .simulator_id)")
SIM ?= $(if $(SIM_FROM_WORKTREE),$(SIM_FROM_WORKTREE),platform=iOS Simulator,name=iPhone 17)
SCHEME := CheckStitch
CONFIGURATION := Debug
DERIVED_DATA := DerivedData
APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphonesimulator/$(SCHEME).app

.PHONY: build run clean

build:
	xcodebuild -scheme '$(SCHEME)' \
	  -destination '$(SIM)' \
	  -configuration '$(CONFIGURATION)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  build

run: build
	bash scripts/run-simulator.sh '$(SIM)' '$(APP)'

clean:
	xcodebuild -scheme '$(SCHEME)' -destination '$(SIM)' clean
