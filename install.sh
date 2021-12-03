#!/bin/bash
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd $SCRIPT_DIR

if [[ ! ${1+defined} ]];then
    echo "Supply a default config, options: $(ls configs | tr '\n' ' ' | sed 's/.yaml//g')"
    exit 1
fi
if [[ ! -f "configs/$1.yaml" ]];then
    echo "Specified config does not exists, options: $(ls configs | tr '\n' ' ' | sed 's/.yaml//g')"
fi

if [[  $( which python3 &> /dev/null ) ]];then
    echo "Could not find python3"
    exit 1 
fi
if [[  $(which pip3 &> /dev/null ) ]];then
    echo "Could not find pip3"
    exit 1 
fi
mkdir default_config
ln -s ../configs/$1.yaml default_config/config.yaml
echo "Using python3: $(which python3)"
unset PYTHONUSERBASE
export PYTHONUSERBASE=PyDeps
echo "export PY_EXE=$(which python3)" > frontends/inst_vars.sh
echo "Installing pyyaml"
pip3 install --user pyyaml

