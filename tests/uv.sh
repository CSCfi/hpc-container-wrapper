#!/bin/bash -u
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# shellcheck source=setup.sh
source "$SCRIPT_DIR/setup.sh"
# Tests are run in current directory

t_workdir TEST_DIR_UV

# Fixtures
echo "pyyaml" > req.txt
echo "pyyyaml" > req_typo.txt
echo "uv pip install requests" > post.sh
sed 's/container_image.*$/container_image: My_very_cool_name.sif/g' "$CONFIG_YAML" > my_config.yaml
export CW_GLOBAL_YAML=my_config.yaml

# Tests
t_run "containerize pip new --uv --prefix UV_INSTALL_DIR req_typo.txt  2>&1 | grep -o 'not found in the package registry'" "uv error shown to user"

t_run "containerize pip new --uv --prefix UV_INSTALL_DIR req.txt " "pip install with uv works"
t_run "containerize pip update UV_INSTALL_DIR --post-install post.sh" "Update with uv works"

t_run "UV_INSTALL_DIR/bin/python -c 'import requests'" "Package added in uv update available"
t_run "UV_INSTALL_DIR/bin/python -c 'import sys;sys.exit(sys.prefix == sys.base_prefix)'" "UV Installation is venv"
