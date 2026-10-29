#!/bin/bash -u
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source $SCRIPT_DIR/setup.sh
# Tests are run in current directory

t_workdir TEST_DIR_CONDA

# Fixtures
echo "pyyaml" > req.txt
echo "pip install requests" > post.sh
echo "conda config --show-sources;conda config --show pkgs_dirs;exit 1" > pre.sh
echo "GARBAGE" > conda_env.txt

echo "
channels:
  - conda-forge
dependencies:
  - numpy
  - pip
" > conda_base.yml

echo "
channels:
  - conda-forge
dependencies:
   - dask
   - dask-jobqueue
" > dask_env.yaml

echo "
channels:
  - conda-forge
dependencies:
  - this_is_not_a_package
" > conda_broken.yaml

echo "
channels:
  - conda-forge
dependencies:
  - numpy
  - uv
  - pip:
    - requests
" > hybrid.yaml

echo '
import dask
import dask_jobqueue

single_worker = {
    "project" : "pn",
    "queue" : "small",
    "nodes" : 1,
    "cores" : 4,
    "memory" : "8G",
    "time" : "00:10:00",
    "temp_folder" : "/scratch/project_2000599/dask_slurm/temp"
}
cluster = dask_jobqueue.SLURMCluster(
        queue = single_worker["queue"],
        project = single_worker["project"],
        cores = single_worker["cores"],
        memory = single_worker["memory"],
        walltime = single_worker["time"],
        interface = "lo",
        local_directory = single_worker["temp_folder"]
    )
print(cluster.job_script())

' > dask_test.py

mkdir CONDA_INSTALL_DIR

# Error reporting and logging
t_run "containerize conda new conda_broken.yaml --prefix CONDA_INSTALL_DIR | tee conda_inst.out | grep 'ResolvePackageNotFound\|PackagesNotFound'" "Conda errors are propagated to the user"
t_run "grep ERROR conda_inst.out" "Failed run contains error"
t_run "grep INFO conda_inst.out"  "Info is present"
t_run "test -z \"\$(grep ' DEBUG ' conda_inst.out )\" "  "Default no debug message"

# User .condarc
unset CW_ENABLE_CONDARC
rc_res=$(containerize conda new --pre-install=pre.sh conda_base.yml --prefix CONDA_INSTALL_DIR 2>&1 | grep -o "$HOME/.conda/pkgs")
t_run "test -z $rc_res" "User .condarc is ignored"
export CW_ENABLE_CONDARC=1
t_run "containerize conda new --pre-install=pre.sh conda_base.yml --prefix CONDA_INSTALL_DIR  | grep -q $HOME/.conda/pkgs" "User .condarc can be enabled"
unset CW_ENABLE_CONDARC

# Basic install, venv and update
t_run "containerize conda new --mamba conda_base.yml -r req.txt --prefix CONDA_INSTALL_DIR &>/dev/null" "Basic installation works"
t_run "CONDA_INSTALL_DIR/bin/python -m venv VE " "Virtual environment creation works"
t_run "VE/bin/python -c 'import sys;sys.exit( sys.prefix == sys.base_prefix )'" "Virtual environment is correct"
t_run "VE/bin/pip install requests" "pip works for a venv"
t_run "VE/bin/python -c 'import requests;print(requests.__file__)' | grep -q VE " "Package is installed correctly to venv"
CONDA_INSTALL_DIR/bin/_debug_exec bash -c "\$(readlink -f \$env_root)/../../bin/conda list --explicit" > explicit_env.txt
t_run "CONDA_INSTALL_DIR/bin/python -c 'import yaml'" "Package added by -r is there"
t_run "containerize conda update CONDA_INSTALL_DIR --post-install post.sh" "Update works"
t_run "CONDA_INSTALL_DIR/bin/python -c 'import requests'" "Package added by update is there"

# Explicit env file (exported above)
rm -fr CONDA_INSTALL_DIR && mkdir CONDA_INSTALL_DIR
t_run "containerize conda new --mamba explicit_env.txt --prefix CONDA_INSTALL_DIR &>/dev/null" "Explicit env file works"

# Hybrid conda/pip with uv
rm -fr CONDA_INSTALL_DIR && mkdir CONDA_INSTALL_DIR
t_run "containerize conda new --mamba --uv --prefix CONDA_INSTALL_DIR hybrid.yaml 2>&1 | grep -o 'Installing uv packages:'" "Hybrid conda/pip environment creation with uv"
t_run "containerize conda update -r req.txt CONDA_INSTALL_DIR  2>&1 | grep -o 'Resolved 1 package in'" "Hybrid conda/pip environment update with uv"

# Wrapper behaviour, using the dask env
rm -fr CONDA_INSTALL_DIR && mkdir CONDA_INSTALL_DIR
t_run "containerize conda new --mamba dask_env.yaml --prefix CONDA_INSTALL_DIR &>/dev/null" "yaml ending is also supported"
OLD_PATH=$PATH
PATH="CONDA_INSTALL_DIR/bin:$PATH"
t_run '[[ "$(which python)" == "$(_debug_exec which python)" ]]' "Which returns same in and out"

str1="$(python -c "print('Hello world --a g -b \\\ ')" )"
str2="Hello world --a g -b \ "
t_run "\[ \"$str1\" = \"$str2\" \]" "Wrapper passed quotes correctly"
t_run "python -c \"import os; os.environ['CONDA_DEFAULT_ENV']\"" "Conda is activated"

g=$(python -c "import dask;print(dask.__file__)" 2>/dev/null )
t_run "[[ -n '$g' ]]" "Package found in container"
t_run "[[ ! -f '$g' ]]" "Package not on host"
t_run "python dask_test.py | grep \"$(realpath -s $PWD/CONDA_INSTALL_DIR/bin/python )\"" "Dask uses correct python path"
PATH=$OLD_PATH
