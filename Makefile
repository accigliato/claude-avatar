BINARY = ClaudeAvatar
SOURCES = $(shell find Sources -name '*.swift')
BUILD_DIR = .build/release
SDK = $(shell xcrun --show-sdk-path)
FONT_SRC = Sources/ClaudeAvatar/Resources/sga-font.otf
AUDIO_SRC = Sources/ClaudeAvatar/Resources/fah.mp3

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
		-framework CoreText \
		-o $(BUILD_DIR)/$(BINARY) \
		$(SOURCES)
	@cp -f $(FONT_SRC) $(BUILD_DIR)/sga-font.otf 2>/dev/null || true
	@cp -f $(AUDIO_SRC) $(BUILD_DIR)/fah.mp3 2>/dev/null || true
	@echo "Built $(BUILD_DIR)/$(BINARY)"

clean:
	rm -rf $(BUILD_DIR)

install: build
	@mkdir -p $(HOME)/.local/bin
	cp $(BUILD_DIR)/$(BINARY) $(HOME)/.local/bin/
	cp -f $(BUILD_DIR)/sga-font.otf $(HOME)/.local/bin/ 2>/dev/null || true
	cp -f $(BUILD_DIR)/fah.mp3 $(HOME)/.local/bin/ 2>/dev/null || true
	@echo "Installed to $(HOME)/.local/bin/$(BINARY)"
