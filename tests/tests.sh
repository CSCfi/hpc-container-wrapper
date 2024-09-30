#!/bin/bash -eu
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source $SCRIPT_DIR/setup.sh
# Test are run in current directory

rm -fr TEST_DIR
mkdir TEST_DIR
cd TEST_DIR

cmds=(conda-containerize pip-containerize wrap-container wrap-install)

for cmd in "${cmds[@]}"; do
    t_run "$cmd -h | grep 'show this help message'" "$cmd has help flag"
    t_run "$cmd" "$cmd help returns 0"
done
cmds=("conda-containerize new " "pip-containerize new" wrap-install)
for cmd in "${cmds[@]}"; do
   t_run "$cmd --help | grep -- '--post-install'" "$cmd has post-install flag"
   t_run "$cmd --help | grep -- '--pre-install'" "$cmd has pre-install flag"
   t_run "$cmd --help | grep -- '--environ'" "$cmd has environ flag"
   t_run "$cmd --help | grep -- '--wrapper-paths'" "$cmd has wrapper-paths flag"
   t_run "$cmd 2>&1 | grep -- 'arguments are required\|^usage:'" "$cmd error/help on no arg"
done
cmd=(wrap-container)
for cmd in "${cmds[@]}"; do
   t_run "$cmd --help | grep -- '--environ'" "$cmd has environ flag"
   t_run "$cmd --help | grep -- '--wrapper-paths'" "$cmd has wrapper-paths flag"
   t_run "$cmd 2>&1 | grep -- 'arguments are required\|^usage:'" "$cmd error/help on no arg"
done


echo "pyyaml" > req.txt
echo "pyyyaml" > req_typo.txt
echo "pip install requests" > post.sh

echo "
channels:
  - conda-forge
dependencies:
  - numpy
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
echo "GARBAGE" > conda_env.txt

t_run "conda-containerize new conda_base.yml --prefix NOT_A_DIR" "Missing install dir is created"
mkdir A_DIR_NO_WRITE
chmod ugo-w A_DIR_NO_WRITE
t_run "conda-containerize new conda_base.yml --prefix A_DIR_NO_WRITE | grep ERROR" "Installation dir has to be writable"
mkdir A_DIR_NO_EXE
chmod ugo-x A_DIR_NO_EXE
t_run "conda-containerize new conda_base.yml --prefix A_DIR_NO_EXE | grep ERROR" "Installation dir has to be executable"

mkdir CONDA_INSTALL_DIR

t_run "conda-containerize new conda_broken.yaml --prefix CONDA_INSTALL_DIR | tee conda_inst.out | grep 'ResolvePackageNotFound'" "Conda errors are propagated to the user"
t_run "grep ERROR conda_inst.out" "Failed run contains error" 
t_run "grep INFO conda_inst.out"  "Info is present"
t_run "test -z \"\$(grep ' DEBUG ' conda_inst.out )\" "  "Default no debug message"
tmp_dir=$(cat conda_inst.out | grep -o "[^ ]*/cw-[A-Z,0-9]\{6\} ")
t_run "\[ ! -e $tmp_dir \]" "Build dir is deleted on error"
export CW_DEBUG_KEEP_FILES=1
conda-containerize new conda_broken.yaml --prefix CONDA_INSTALL_DIR > conda_inst.out
tmp_dir=$(cat conda_inst.out | grep -o "[^ ]*/cw-[A-Z,0-9]\{6\} ")
t_run "\[ -e $tmp_dir \]" "Build dir is saved if CW_DEBUG_KEEP_FILES set"
test -d $tmp_dir && rm -rf $tmp_dir
unset CW_DEBUG_KEEP_FILES

unset CW_ENABLE_CONDARC
echo "conda config --show-sources;conda config --show pkgs_dirs;exit 1" > pre.sh
rc_res=$(conda-containerize new --pre-install=pre.sh conda_base.yml --prefix CONDA_INSTALL_DIR  | grep -o $HOME/.conda/pkgs)
t_run "test -z $rc_res" "User .condarc is ignored"
export CW_ENABLE_CONDARC=1
t_run "conda-containerize new --pre-install=pre.sh conda_base.yml --prefix CONDA_INSTALL_DIR  | grep -q $HOME/.conda/pkgs" "User .condarc can be enabled"
unset CW_ENABLE_CONDARC
t_run "conda-containerize new --mamba conda_base.yml -r req.txt --prefix CONDA_INSTALL_DIR &>/dev/null" "Basic installation works"
t_run "CONDA_INSTALL_DIR/bin/python -m venv VE " "Virtual environment creation works"
t_run "VE/bin/python -c 'import sys;sys.exit( sys.prefix == sys.base_prefix )'" "Virtual environment is correct"
t_run "VE/bin/pip install requests" "pip works for a venv"
t_run "VE/bin/python -c 'import requests;print(requests.__file__)' | grep -q VE " "Package is installed correctly to venv"
CONDA_INSTALL_DIR/bin/_debug_exec bash -c "\$(readlink -f \$env_root)/../../bin/conda list --explicit" > explicit_env.txt 
t_run "CONDA_INSTALL_DIR/bin/python -c 'import yaml'" "Package added by -r is there"
t_run "conda-containerize update CONDA_INSTALL_DIR --post-install post.sh" "Update works"
t_run "CONDA_INSTALL_DIR/bin/python -c 'import requests'" "Package added by update is there"
rm -fr CONDA_INSTALL_DIR && mkdir CONDA_INSTALL_DIR
t_run "conda-containerize new --mamba explicit_env.txt --prefix CONDA_INSTALL_DIR &>/dev/null" "Explicit env file works"

rm -fr CONDA_INSTALL_DIR && mkdir CONDA_INSTALL_DIR
t_run "conda-containerize new --mamba dask_env.yaml --prefix CONDA_INSTALL_DIR &>/dev/null" "yaml ending is also supported"
OLD_PATH=$PATH
PATH="CONDA_INSTALL_DIR/bin:$PATH"
t_run " \[  $(which python)==$(_debug_exec which python)  \] " "Which returns same in and out"
str1="$(python -c "print('Hello world --a g -b \ ')" )"
str2="Hello world --a g -b \ "
t_run "\[ \"$str1\" = \"$str2\" \]" "Wrapper passed quotes correctly"
t_run "python -c \"import os; os.environ['CONDA_DEFAULT_ENV']\"" "Conda is activated"
g=$(python -c "import dask;print(dask.__file__)" 2>/dev/null )
t_run "\[ -n $g \]" "Package found in container"
t_run "\[ ! -f \"$g\" \]" "Package not on host"
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
t_run "python dask_test.py | grep \"$(realpath -s $PWD/CONDA_INSTALL_DIR/bin/python )\"" "Dask uses correct python path"
PATH=$OLD_PATH


OLD_PATH=$PATH
mkdir PIP_INSTALL_DIR

cat ../../default_config/config.yaml | sed  's/container_image.*$/container_image: My_very_cool_name.sif/g' > my_config.yaml
t_run "pip-containerize new --prefix PIP_INSTALL_DIR req_typo.txt  2>&1 | grep 'No matching distribution'" "pip error shown to user"
export CW_GLOBAL_YAML=my_config.yaml
t_run "pip-containerize new --prefix PIP_INSTALL_DIR req.txt " "pip install works"
t_run "pip-containerize update PIP_INSTALL_DIR --post-install post.sh" "Update works"
PATH="PIP_INSTALL_DIR/bin:$PATH"
t_run "python -c 'import requests'" "Package added in update available"
t_run "\[ -e PIP_INSTALL_DIR/My_very_cool_name.sif \]" "Using custom conf"
t_run "python -c 'import sys;sys.exit(sys.prefix == sys.base_prefix)'" "Installation is venv"
in_p=$(python3 -c 'import sys;print(sys.executable)') 
out_p="$PWD/PIP_INSTALL_DIR/bin/python3"                                  
t_run "[[ $in_p == $out_p ]]" "Executable name is same on in and out"                         
