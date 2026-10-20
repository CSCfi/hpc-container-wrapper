# Build the tool and select the default config: make CONFIG=<config> [PREFIX=<dir>]
PREFIX ?= ./build
CONFIGS := $(basename $(notdir $(wildcard configs/*.yaml)))
LDFLAGS := -X main.config=$(CONFIG) -X main.version=$(shell git describe --tags 2>/dev/null) -X main.commit=$(shell git rev-parse --short HEAD 2>/dev/null)

.PHONY: all
all:
	@test -n "$(CONFIG)" || { echo "Supply a default config with CONFIG=<config>, options: $(CONFIGS)"; exit 1; }
	@test -f configs/$(CONFIG).yaml || { echo "Specified config does not exists, options: $(CONFIGS)"; exit 1; }
	CGO_ENABLED=0 go build -ldflags "$(LDFLAGS)" -o $(PREFIX)/libexec/containerize ./src
	mkdir -p $(PREFIX)/bin
	for p in conda-containerize pip-containerize wrap-container wrap-install; do ln -sf ../libexec/containerize $(PREFIX)/bin/$$p; done
	cp -r etc $(PREFIX)/
	mkdir -p $(PREFIX)/configs && cp configs/$(CONFIG).yaml $(PREFIX)/configs/
