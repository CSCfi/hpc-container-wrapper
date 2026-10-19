#!/bin/bash
# Build the tool and select the default config: bash install.sh <config>
set -e
cd "$(dirname "${BASH_SOURCE[0]}")"
configs="$(ls configs | sed 's/.yaml//g' | tr '\n' ' ')"
if [[ -z "${1:-}" ]]; then
    echo "Supply a default config, options: $configs"
    exit 1
fi
if [[ ! -f "configs/$1.yaml" ]]; then
    echo "Specified config does not exists, options: $configs"
    exit 1
fi
mkdir -p default_config
ln -sf ../configs/$1.yaml default_config/config.yaml
CGO_ENABLED=0 go build -ldflags "-X main.version=$(git describe --tags 2>/dev/null) -X main.commit=$(git rev-parse --short HEAD 2>/dev/null)" -o libexec/containerize .
echo "Built libexec/containerize using config $1"
