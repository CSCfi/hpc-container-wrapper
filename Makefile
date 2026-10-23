# Build the tool and select the default config: make CONFIG=<config> [PREFIX=<dir>] [MODULEFILES_DIR=<dir>]
PREFIX ?= ./build
MODULEFILES_DIR ?= $(PREFIX)
VERSION := $(or $(shell git describe --tags 2>/dev/null),dev)
# Legacy command name:containerize subcommand
LEGACY := conda-containerize:conda pip-containerize:pip wrap-container:wrap-container wrap-install:wrap-install
CONFIGS := $(basename $(notdir $(wildcard configs/*.yaml)))
LDFLAGS := -X main.config=$(CONFIG) -X main.version=$(VERSION) -X main.commit=$(shell git rev-parse --short HEAD 2>/dev/null)

.PHONY: all
all:
	@test -n "$(CONFIG)" || { echo "Supply a default config with CONFIG=<config>, options: $(CONFIGS)"; exit 1; }
	@test -f configs/$(CONFIG).yaml || { echo "Specified config does not exists, options: $(CONFIGS)"; exit 1; }
	CGO_ENABLED=0 go build -ldflags "$(LDFLAGS)" -o $(PREFIX)/bin/containerize ./src
	for l in $(LEGACY); do \
		printf '#!/bin/sh\nexec "$${0%%/*}/containerize" %s "$$@"\n' "$${l#*:}" > $(PREFIX)/bin/$${l%%:*}; \
		chmod +x $(PREFIX)/bin/$${l%%:*}; \
	done
	cp -r etc $(PREFIX)/
	mkdir -p $(PREFIX)/configs && cp configs/$(CONFIG).yaml $(PREFIX)/configs/
	mkdir -p $(MODULEFILES_DIR)/tykky
	sed 's|@PREFIX@|$(abspath $(PREFIX))|' modulefiles/tykky.lua > $(MODULEFILES_DIR)/tykky/$(VERSION).lua
