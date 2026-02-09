BINARY = ClaudeAvatar
SOURCES = $(shell find Sources -name '*.swift')
BUILD_DIR = .build/release
SDK = $(shell xcrun --show-sdk-path)

.PHONY: build clean install

build: $(BUILD_DIR)/$(BINARY)

$(BUILD_DIR)/$(BINARY): $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	swiftc \
		-O \
		-sdk $(SDK) \
		-target arm64-apple-macosx13.0 \
		-framework AppKit \
		-framework QuartzCore \
		-o $(BUILD_DIR)/$(BINARY) \
		$(SOURCES)
	@echo "Built $(BUILD_DIR)/$(BINARY)"

clean:
	rm -rf $(BUILD_DIR)

install: build
	@mkdir -p $(HOME)/.local/bin
	cp $(BUILD_DIR)/$(BINARY) $(HOME)/.local/bin/
	@echo "Installed to $(HOME)/.local/bin/$(BINARY)"
