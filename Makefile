# Makefile

CRYSTAL ?= crystal
BUILD_DIR ?= build
FONT ?= assets/unifont.ttf
ASCII_FONT ?= assets/SGr-IosevkaTermSlab-Regular.ttc
BENCH_ARGS ?=
CORE_ARGS ?=
GL_ARGS ?=

CORE_BIN := $(BUILD_DIR)/bench-core
GL_BIN := $(BUILD_DIR)/bench-gl
CORE_SOURCES := src/slug.cr $(wildcard src/slug/*.cr)
GL_SOURCES := $(CORE_SOURCES) examples/egl.cr examples/frame.cr $(wildcard shaders/*.glsl)

.PHONY: all build bench bench-core bench-gl bench-ascii bench-gles

all: bench

build: $(CORE_BIN) $(GL_BIN)

bench: build
	$(CORE_BIN) --font "$(FONT)" $(BENCH_ARGS) $(CORE_ARGS)
	$(GL_BIN) --font "$(FONT)" $(BENCH_ARGS) $(GL_ARGS)

bench-core: $(CORE_BIN)
	$(CORE_BIN) --font "$(FONT)" $(BENCH_ARGS) $(CORE_ARGS)

bench-gl: $(GL_BIN)
	$(GL_BIN) --font "$(FONT)" $(BENCH_ARGS) $(GL_ARGS)

bench-ascii: build
	$(CORE_BIN) --ascii --font "$(ASCII_FONT)" $(BENCH_ARGS) $(CORE_ARGS)
	$(GL_BIN) --ascii --font "$(ASCII_FONT)" $(BENCH_ARGS) $(GL_ARGS)

bench-gles: $(GL_BIN)
	$(GL_BIN) --es --font "$(FONT)" $(BENCH_ARGS) $(GL_ARGS)

$(CORE_BIN): bench/core.cr bench/support.cr $(CORE_SOURCES) | $(BUILD_DIR)/
	$(CRYSTAL) build $< --release -o $@

$(GL_BIN): bench/gl.cr bench/support.cr $(GL_SOURCES) | $(BUILD_DIR)/
	$(CRYSTAL) build $< --release -o $@

$(BUILD_DIR)/:
	mkdir -p $@
