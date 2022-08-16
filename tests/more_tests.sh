#!/bin/bash -eu
# Test specific to LUMI super computer
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source $SCRIPT_DIR/setup.sh
# Test are run in current directory

rm -fr L_TEST_DIR
mkdir L_TEST_DIR
cd L_TEST_DIR
echo "pyyaml" > req.txt
echo "pip install requests" > post.sh

default_container=$(cat $SCRIPT_DIR/../default_config/config.yaml  | grep container_src | cut -d ":" -f2- | sed "s/'//g" )
singularity pull test_container.sif $default_container 

cat ../../default_config/config.yaml | sed  "s@container_src.*\$@container_src: $PWD/test_container.sif@g" > my_config.yaml | sed 's/container_image.*$/container_image: container.sif/g'
if  grep -q share_container my_config.yaml   ; then
    sed -i 's/share_container.*$/share_container: yes/g' my_config.yaml
else
    sed -i '/container_image.*$/a \ \ \ \ share_container: yes' my_config.yaml
fi
export CW_GLOBAL_YAML=$( readlink -f my_config.yaml)
mkdir PIP_INSTALL_DIR
t_run "pip-containerize new --prefix PIP_INSTALL_DIR req.txt" "Basic pip installation ok"
t_run "PIP_INSTALL_DIR/bin/python -c 'import yaml'" "Required package is present"
t_run "[[ -L PIP_INSTALL_DIR/container.sif  ]]" "Container is symlink"
c1=$(readlink -f test_container.sif )
c2=$(readlink -f PIP_INSTALL_DIR/container.sif )
t_run "[[ $c1 = $c2 ]]" "Symlink points to correct location"
t_run "pip-containerize update PIP_INSTALL_DIR --post post.sh" "Basic update is ok with symlink"
t_run "PIP_INSTALL_DIR/bin/python -c 'import requests'" "Package is present"
t_run "[[ -L PIP_INSTALL_DIR/container.sif  ]]" "Container is still symlink"
c1=$(readlink -f test_container.sif )
c2=$(readlink -f PIP_INSTALL_DIR/container.sif )
t_run "[[ $c1 = $c2 ]]" "Symlink still points to correct location"
t_run "PIP_INSTALL_DIR/bin/python -m venv VE " "Virtual environment creation works"
t_run "VE/bin/python -c 'import sys;sys.exit( sys.prefix == sys.base_prefix )'" "Virtual environment is correct"
t_run "VE/bin/pip install requests" "pip works for a venv"
t_run "VE/bin/python -c 'import requests;print(requests.__file__)' | grep -q VE " "Package is installed correctly to venv"

mkdir fake
mkdir fake/_bin
mkdir fake/bin
touch fake/common.sh
export PATH=$PWD/fake/bin:$PATH
t_run "pip-containerize new --prefix PIP_INSTALL_DIR req.txt 2>&1 | grep Remove" "Fail on active installation"
rm -rf fake

export CW_BUILD_TMPDIR=/NOT_A_DIR
t_run "pip-containerize new --prefix PIP_INSTALL_DIR req.txt 2>&1 | grep -q 'Could not create build directory'" "Can not create build dir"
export CW_BUILD_TMPDIR=A/B/C
t_run "pip-containerize new --prefix PIP_INSTALL_DIR req.txt 2>&1 | grep -q 'path is not absolute' " "Absolute Build dir"
export CW_BUILD_TMPDIR=$PWD/A/B/C
t_run "pip-containerize new --prefix PIP_INSTALL_DIR req.txt" "Creates missing dirs"
unset CW_BUILD_TMPDIR
mkdir subdir 
mkdir PIP_INSTALL_DIR_2
cd subdir
t_run "pip-containerize new --prefix ../PIP_INSTALL_DIR_2 ../req.txt" "Path resolve for input file works"
cd ..
cp req.txt subdir
mkdir subdir/PIP_INSTALL_DIR_3
t_run "pip-containerize new --prefix subdir/PIP_INSTALL_DIR_3 subdir/req.txt" "Path resolve for input file works"

rm -fr PIP_INSTALL_DIR
mkdir PIP_INSTALL_DIR
t_run "wrap-container -w /usr/sbin/sln --prefix PIP_INSTALL_DIR test_container.sif" "wrap-container works with single target"

rm -fr PIP_INSTALL_DIR
mkdir PIP_INSTALL_DIR
t_run "wrap-container -w /usr/sbin --prefix PIP_INSTALL_DIR test_container.sif" "wrap-container works"


forall () { local e fun="$1"; shift ; for e; do $fun $e || return 1 ; done ; }

elementIn () {
  for e in ${real[@]}; do [[ "$e" == "$1" ]] && return 0; done
  return 1
}
export -f forall elementIn

export ref=($(singularity exec test_container.sif sh -c 'ls /usr/sbin' ))
export real=($( ls PIP_INSTALL_DIR/bin/ ))
t_run "forall elementIn \"\${ref[@]}\" " "Wrappers generated"


export ref=($(singularity exec test_container.sif sh -c 'echo $PATH' | tr ':' '\n' ))
export real=($(PIP_INSTALL_DIR/bin/_debug_exec sh -c 'echo $PATH' | tr ':' '\n' ))
t_run "forall elementIn \"\${ref[@]}\" " "Container path retained when wrapping"

export ref=($(singularity exec test_container.sif sh -c 'echo $LD_LIBRARY_PATH' | tr ':' '\n' ))
export real=($(PIP_INSTALL_DIR/bin/_debug_exec sh -c 'echo $LD_LIBRARY_PATH' | tr ':' '\n' ))
t_run "forall elementIn \"\${ref[@]}\" " "Container ld_library_path retained when wrapping"

export PATH="$PATH:/some/extra1:/another/path"
export ref=( $(echo "$PATH" | tr ':' '\n' ))
export real=($(PIP_INSTALL_DIR_2/bin/_debug_exec sh -c 'echo $PATH' | tr ':' '\n' ))
t_run "forall elementIn \"\${ref[@]}\" " "External path retained"

export real=($(PIP_INSTALL_DIR/bin/_debug_exec sh -c 'echo $PATH' | tr ':' '\n' ))
t_string=$( echo "$real" | grep "/some/extra1" )
t_run "test -z $t_string " "External path removed when isolating"


