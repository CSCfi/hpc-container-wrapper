#!/bin/bash
# Tests specific to the LUMI supercomputer
# shellcheck source-path=SCRIPTDIR
# Single-quoted $ and the ref/real arrays are used by sh -c or t_run's eval
# shellcheck disable=SC2016,SC2034
set -u
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# shellcheck source=setup.sh
source "$SCRIPT_DIR/setup.sh"
# Tests are run in current directory

t_workdir TEST_DIR_LUMI

# Fixtures
echo "pyyaml" > req.txt
echo "pip install requests" > post.sh

# Base container, resolved by containerize from container_src: auto
mkdir BASE
t_run "containerize pip new --prefix BASE req.txt" "Base container can be fetched"
cp BASE/container.sif test_container.sif

# Config using the base container as a shared container
sed "s@container_src.*\$@container_src: $PWD/test_container.sif@g" "$CONFIG_YAML" > my_config.yaml
if grep -q share_container my_config.yaml; then
    sed -i 's/share_container.*$/share_container: yes/g' my_config.yaml
else
    sed -i '/container_image.*$/a \ \ \ \ share_container: yes' my_config.yaml
fi
CW_GLOBAL_YAML=$(readlink -f my_config.yaml)
export CW_GLOBAL_YAML

# Site packages and shared container symlink
mkdir PIP_INSTALL_DIR
t_run "containerize pip new --system-site-packages --prefix PIP_INSTALL_DIR req.txt" "System site packages flag"
t_run "env -u PYTHONNOUSERSITE PIP_INSTALL_DIR/bin/python -c 'import site;import sys;sys.exit(not site.ENABLE_USER_SITE  )'" "Site packages can be enabled"
t_run "containerize pip new --prefix PIP_INSTALL_DIR req.txt" "Basic pip installation ok"
t_run "env -u PYTHONNOUSERSITE PIP_INSTALL_DIR/bin/python -c 'import site;import sys;sys.exit(site.ENABLE_USER_SITE  )'" "Site packages disabled by default"
t_run "containerize pip update PIP_INSTALL_DIR --post post.sh" "Basic update is ok with symlink"
t_run "[[ -L PIP_INSTALL_DIR/container.sif  ]]" "Container is still symlink"
c1=$(readlink -f test_container.sif )
c2=$(readlink -f PIP_INSTALL_DIR/container.sif )
t_run "[[ $c1 = $c2 ]]" "Symlink still points to correct location"

# Relative paths
mkdir subdir PIP_INSTALL_DIR_2
t_run "(cd subdir && containerize pip new --prefix ../PIP_INSTALL_DIR_2 ../req.txt)" "Path resolve for input file works"
cp req.txt subdir
mkdir subdir/PIP_INSTALL_DIR_3
t_run "containerize pip new --prefix subdir/PIP_INSTALL_DIR_3 subdir/req.txt" "Path resolve for input file works"

# wrap-container with a single target
rm -fr PIP_INSTALL_DIR && mkdir PIP_INSTALL_DIR
t_run "containerize wrap-container -w /usr/sbin/zdump --prefix PIP_INSTALL_DIR test_container.sif" "wrap-container works with single target"

# wrap-container from a remote image, and a venv on top of it
rm -fr WRAP_TEST && mkdir WRAP_TEST
t_run "containerize wrap-container docker://python:3.12.9-slim-bookworm -w /usr/local/bin --prefix WRAP_TEST/WW" "Wrap container for remote container"
t_run "WRAP_TEST/WW/bin/python --version | grep '3.12.9'" "Wrapped container actually contains the correct version of python"
t_run "WRAP_TEST/WW/bin/python -m venv WRAP_TEST/Py" "Creating a virtual environment on wrapped python works"
t_run "WRAP_TEST/Py/bin/python -c 'import sys;sys.exit( sys.prefix == sys.base_prefix )'" "Created venv is functional"
t_run "WRAP_TEST/Py/bin/python -c 'import shutil; print(shutil.which(\"python\"))' | grep 'WRAP_TEST/Py'" "Trick to retain venv path works"
# shellcheck source=/dev/null
source WRAP_TEST/Py/bin/activate
t_run "python -c 'import sys;sys.exit( sys.prefix == sys.base_prefix )'" "Created venv is functional (activated env)"
t_run "python -c 'import shutil; print(shutil.which(\"python\"))' | grep 'WRAP_TEST/Py'" "Trick to retain venv path works (activated env)"
deactivate

# wrap-container with a directory target
rm -fr PIP_INSTALL_DIR && mkdir PIP_INSTALL_DIR
t_run "containerize wrap-container -w /usr/sbin --prefix PIP_INSTALL_DIR test_container.sif" "wrap-container works"

# Helpers: is every element of ref also in real?
forall () { local e fun="$1"; shift ; for e; do $fun "$e" || return 1 ; done ; }

elementIn () {
    for e in "${real[@]}"; do [[ "$e" == "$1" ]] && return 0; done
    return 1
}

# Wrapped environment matches the container
mapfile -t ref < <(singularity exec test_container.sif sh -c 'ls /usr/sbin')
mapfile -t real < <(ls PIP_INSTALL_DIR/bin/)
t_run "forall elementIn \"\${ref[@]}\" " "Wrappers generated"

mapfile -t ref < <(singularity exec test_container.sif sh -c 'echo $PATH' | tr ':' '\n' | grep .)
mapfile -t real < <(PIP_INSTALL_DIR/bin/_debug_exec sh -c 'echo $PATH' | tr ':' '\n' | grep .)
t_run "forall elementIn \"\${ref[@]}\" " "Container path retained when wrapping"

mapfile -t ref < <(singularity exec test_container.sif sh -c 'echo $LD_LIBRARY_PATH' | tr ':' '\n' | grep .)
mapfile -t real < <(PIP_INSTALL_DIR/bin/_debug_exec sh -c 'echo $LD_LIBRARY_PATH' | tr ':' '\n' | grep .)
t_run "forall elementIn \"\${ref[@]}\" " "Container ld_library_path retained when wrapping"

# Host PATH: kept for pip installs, dropped for isolated wrap-container
export PATH="$PATH:/some/extra1:/another/path"
mapfile -t ref < <(echo "$PATH" | tr ':' '\n' | grep .)
mapfile -t real < <(PIP_INSTALL_DIR_2/bin/_debug_exec sh -c 'echo $PATH' | tr ':' '\n' | grep .)
t_run "forall elementIn \"\${ref[@]}\" " "External path retained"

mapfile -t real < <(PIP_INSTALL_DIR/bin/_debug_exec sh -c 'echo $PATH' | tr ':' '\n' | grep .)
t_run '! printf "%s\n" "${real[@]}" | grep -q /some/extra1' "External path removed when isolating"
