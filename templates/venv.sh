#!/bin/bash
set -e


cd  $CW_BUILD_TMPDIR
echo "export env_root=$CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/" >> _extra_envs.sh
echo "export env_root=$CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/" >> _vars.sh

cd $CW_INSTALLATION_PATH


print_info "Using miniconda version Miniconda3-$CW_CONDA_VERSION-$CW_CONDA_ARCH" 1
print_info "Downloading miniconda " 2
curl https://repo.anaconda.com/miniconda/Miniconda3-$CW_CONDA_VERSION-$CW_CONDA_ARCH.sh --output Miniconda_inst.sh &>/dev/null 
print_info "Installing miniconda " 1 
bash Miniconda_inst.sh -b -p $CW_INSTALLATION_PATH/miniconda  > $CW_BUILD_TMPDIR/_inst_miniconda.log &   
follow_log $! $CW_BUILD_TMPDIR/_inst_miniconda.log 10
eval "$($CW_INSTALLATION_PATH/miniconda/bin/conda shell.bash hook)"
cd $CW_WORKDIR
source $CW_INSTALLATION_PATH/_pre_install.sh
cd $CW_INSTALLATION_PATH
if [[ ${CW_REQUIREMENTS_FILE+defined}  ]];then
    pip install -r "$CW_REQUIREMENTS_FILE"
fi
cd $CW_WORKDIR
print_info "Running user supplied commands" 1

echo "CW_WRAPPER_PATHS+=( \"$CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/bin/\" )
CW_WRAPPER_LD_LIBRARY_PATHS+=( \"$CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/lib/\" )
" >>  $CW_BUILD_TMPDIR/_vars.sh
