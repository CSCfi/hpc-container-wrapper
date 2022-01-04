#!/bin/bash -eu
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source $SCRIPT_DIR/setup.sh
# Test are run in current directory


# Generic
cmds=($(ls ../bin/))

for cmd in "${cmds[@]}"; do
    t_run "$cmd -h | grep 'show this help message' " help_msg_$cmd
done

cmd=conda-containerize
t_run "conda-containerize new 2>&1  | grep 'arguments are required' " missing_arg_$cmd 
t_run "conda-containerize new not_a_file.def 2>&1 | grep 'does not exist' " no_def_file_$cmd 

export PYTHONNOUSERSITE="TRUE"
unset PYTHONPATH
temp_target=cwti_test_temp_dir
[[ -d $temp_target  ]] && rm -fr $temp_target
mkdir $temp_target
t_run " conda-containerize new --prefix $temp_target $SCRIPT_DIR/basic_broken.yaml 2>&1 | grep 'ResolvePackageNotFound' " pkg_not_found
t_run " conda-containerize new --prefix $temp_target $SCRIPT_DIR/basic.yaml " basic_install_1
t_run " $temp_target/bin/python -c 'import numpy'" basic_install_2
in_p=$($temp_target/bin/python3 -c 'import sys;print(sys.executable)')
out_p=$(realpath $temp_target/bin/python3)
t_run "[[ $in_p == $out_p ]]" in_out_same
