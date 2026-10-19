# Build the tool and select the default config: make CONFIG=<config>
CONFIGS := $(basename $(notdir $(wildcard configs/*.yaml)))
LDFLAGS := -X main.version=$(shell git describe --tags 2>/dev/null) -X main.commit=$(shell git rev-parse --short HEAD 2>/dev/null)

.PHONY: all
all:
	@test -n "$(CONFIG)" || { echo "Supply a default config with CONFIG=<config>, options: $(CONFIGS)"; exit 1; }
	@test -f configs/$(CONFIG).yaml || { echo "Specified config does not exists, options: $(CONFIGS)"; exit 1; }
	mkdir -p default_config
	ln -sf ../configs/$(CONFIG).yaml default_config/config.yaml
	CGO_ENABLED=0 go build -ldflags "$(LDFLAGS)" -o libexec/containerize ./src
	mkdir -p bin
	for p in conda-containerize pip-containerize wrap-container wrap-install; do ln -sf ../libexec/containerize bin/$$p; done
