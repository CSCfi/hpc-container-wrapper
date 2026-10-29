#!/bin/bash -u
# Test specific to LUMI super computer
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source $SCRIPT_DIR/setup.sh
# Test are run in current directory

t_workdir TEST_DIR_LUMI
echo "pyyaml" > req.txt
echo "pip install requests" > post.sh

default_container=$(grep container_src "$CONFIG_YAML" | cut -d ":" -f2- | sed "s/'//g" )
if [[ "$default_container" == "auto" ]];then
    default_container=$(. /etc/os-release; case $ID in
        sles) echo "registry.suse.com/bci/bci-base:$VERSION_ID";; rhel) echo "redhat/ubi${VERSION_ID%%.*}:$VERSION_ID";;
        almalinux) echo "almalinux:$VERSION_ID";; rocky) echo "rockylinux/rockylinux:$VERSION_ID";; *) echo "$ID:$VERSION_ID";; esac)
fi
t_run "singularity pull test_container.sif docker://$default_container" "default or auto determined container exists and can be downloaded"

sed "s@container_src.*\$@container_src: $PWD/test_container.sif@g" "$CONFIG_YAML" > my_config.yaml
if  grep -q share_container my_config.yaml   ; then
    sed -i 's/share_container.*$/share_container: yes/g' my_config.yaml
else
    sed -i '/container_image.*$/a \ \ \ \ share_container: yes' my_config.yaml
fi
export CW_GLOBAL_YAML=$( readlink -f my_config.yaml)
mkdir PIP_INSTALL_DIR
t_run "containerize pip new --system-site-packages --prefix PIP_INSTALL_DIR req.txt" "System site packages flag"
t_run "PIP_INSTALL_DIR/bin/python -c 'import site;import sys;sys.exit(not site.ENABLE_USER_SITE  )'" "Site packages can be enabled"
t_run "containerize pip new --prefix PIP_INSTALL_DIR req.txt" "Basic pip installation ok"
t_run "PIP_INSTALL_DIR/bin/python -c 'import site;import sys;sys.exit(site.ENABLE_USER_SITE  )'" "Site packages disabled by default"
t_run "PIP_INSTALL_DIR/bin/python -c 'import yaml'" "Required package is present"
t_run "containerize pip update PIP_INSTALL_DIR --post post.sh" "Basic update is ok with symlink"
t_run "PIP_INSTALL_DIR/bin/python -c 'import requests'" "Package is present"
t_run "[[ -L PIP_INSTALL_DIR/container.sif  ]]" "Container is still symlink"
c1=$(readlink -f test_container.sif )
c2=$(readlink -f PIP_INSTALL_DIR/container.sif )
t_run "[[ $c1 = $c2 ]]" "Symlink still points to correct location"
t_run "PIP_INSTALL_DIR/bin/python -m venv VE " "Virtual environment creation works"
t_run "VE/bin/python -c 'import sys;sys.exit( sys.prefix == sys.base_prefix )'" "Virtual environment is correct"
t_run "VE/bin/pip install requests" "pip works for a venv"
t_run "VE/bin/python -c 'import requests;print(requests.__file__)' | grep -q VE " "Package is installed correctly to venv"

mkdir subdir 
mkdir PIP_INSTALL_DIR_2
cd subdir
t_run "containerize pip new --prefix ../PIP_INSTALL_DIR_2 ../req.txt" "Path resolve for input file works"
cd ..
cp req.txt subdir
mkdir subdir/PIP_INSTALL_DIR_3
t_run "containerize pip new --prefix subdir/PIP_INSTALL_DIR_3 subdir/req.txt" "Path resolve for input file works"

rm -fr PIP_INSTALL_DIR
mkdir PIP_INSTALL_DIR
t_run "containerize wrap-container -w /usr/sbin/zdump --prefix PIP_INSTALL_DIR test_container.sif" "wrap-container works with single target"

rm -fr WRAP_TEST
mkdir WRAP_TEST
t_run "containerize wrap-container docker://python:3.12.9-slim-bookworm -w /usr/local/bin --prefix WRAP_TEST/WW" "Wrap container for remote container"
t_run "WRAP_TEST/WW/bin/python --version | grep '3.12.9'" "Wrapped container actually contains the correct version of python"
t_run "WRAP_TEST/WW/bin/python -m venv WRAP_TEST/Py" "Creating a virtual environment on wrapped python works"
t_run "WRAP_TEST/Py/bin/python -c 'import sys;sys.exit( sys.prefix == sys.base_prefix )'" "Created venv is functional"
t_run "WRAP_TEST/Py/bin/python -c 'import shutil; print(shutil.which(\"python\"))' | grep 'WRAP_TEST/Py'" "Trick to retain venv path works"
source WRAP_TEST/Py/bin/activate
t_run "python -c 'import sys;sys.exit( sys.prefix == sys.base_prefix )'" "Created venv is functional (activated env)"
t_run "python -c 'import shutil; print(shutil.which(\"python\"))' | grep 'WRAP_TEST/Py'" "Trick to retain venv path works (activated env)"
deactivate

rm -fr PIP_INSTALL_DIR
mkdir PIP_INSTALL_DIR
t_run "containerize wrap-container -w /usr/sbin --prefix PIP_INSTALL_DIR test_container.sif" "wrap-container works"


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
t_run '! printf "%s\n" "${real[@]}" | grep -q /some/extra1' "External path removed when isolating"


