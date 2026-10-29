#!/bin/bash
set -u
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# shellcheck source=setup.sh
source "$SCRIPT_DIR/setup.sh"
# Tests are run in current directory

t_workdir TEST_DIR_PIP

# Fixtures
echo "pyyaml" > req.txt
echo "pyyyaml" > req_typo.txt
echo "pip install requests" > post.sh
sed 's/container_image.*$/container_image: My_very_cool_name.sif/g' "$CONFIG_YAML" > my_config.yaml
mkdir PIP_INSTALL_DIR

# pip
t_run "containerize pip new --prefix PIP_INSTALL_DIR req_typo.txt  2>&1 | grep 'No matching distribution'" "pip error shown to user"

export CW_GLOBAL_YAML=my_config.yaml
t_run "containerize pip new --prefix PIP_INSTALL_DIR req.txt " "pip install works"
t_run "containerize pip update PIP_INSTALL_DIR --post-install post.sh" "Update works"

PATH="PIP_INSTALL_DIR/bin:$PATH"
t_run "python -c 'import requests'" "Package added in update available"
t_run "\[ -e PIP_INSTALL_DIR/My_very_cool_name.sif \]" "Using custom conf"
t_run "python -c 'import sys;sys.exit(sys.prefix == sys.base_prefix)'" "Installation is venv"

in_p=$(python3 -c 'import sys;print(sys.executable)')
out_p="$PWD/PIP_INSTALL_DIR/bin/python3"
t_run "[[ $in_p == $out_p ]]" "Executable name is same on in and out"
