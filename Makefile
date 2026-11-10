APP := build/RimeScreenWords.app
BIN := $(APP)/Contents/MacOS/RimeScreenWords
SWIFTC := xcrun swiftc -swift-version 5 -target $(shell uname -m)-apple-macos14
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning | awk '/"Apple Development:/ && !/CSSMERR/ {print $$2; exit}')

.PHONY: build run check install-rime
build: $(BIN)

$(BIN): $(wildcard Sources/*.swift) Info.plist Makefile
	mkdir -p "$(APP)/Contents/MacOS"
	cp Info.plist "$(APP)/Contents/"
	$(SWIFTC) -O -parse-as-library Sources/*.swift -o "$@"
	codesign --force --sign "$(or $(SIGN_IDENTITY),-)" "$(APP)"

run: build
	open "$(APP)"

install-rime:
	/usr/bin/ruby scripts/install.rb
	"/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --reload

check:
	bash Tests/check.sh
