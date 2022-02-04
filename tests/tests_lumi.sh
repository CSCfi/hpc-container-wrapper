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
singularity pull test_container.sif docker://opensuse/leap:15.1 

cat ../../default_config/config.yaml | sed  "s@container_src.*\$@container_src: $PWD/test_container.sif@g" > my_config.yaml | sed 's/container_image.*$/container_image: container.sif/g'
if  grep -q share_container my_config.yaml   ; then
    sed -i 's/share_container.*$/share_container: yes/g' my_config.yaml
else
    sed -i '/container_image.*$/a \ \ \ \ share_container: yes' my_config.yaml
fi
export CW_GLOBAL_YAML=my_config.yaml
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
