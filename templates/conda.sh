#!/bin/bash
set -e



cd $CW_INSTALLATION_PATH

print_info "Using miniconda version Miniconda3-$CW_CONDA_VERSION-$CW_CONDA_ARCH" 1
print_info "Downloading miniconda " 2
curl https://repo.anaconda.com/miniconda/Miniconda3-$CW_CONDA_VERSION-$CW_CONDA_ARCH.sh --output Miniconda_inst.sh &> /dev/null
print_info "Installing miniconda " 1 
bash Miniconda_inst.sh -b -p $CW_INSTALLATION_PATH/miniconda  > $CW_BUILD_TMPDIR/_inst_miniconda.log &   
follow_log $! $CW_BUILD_TMPDIR/_inst_miniconda.log 10
eval "$($CW_INSTALLATION_PATH/miniconda/bin/conda shell.bash hook)"
cd $CW_WORKDIR
source $CW_INSTALLATION_PATH/_pre_install.sh
if [[ ! -z "$(echo "$CW_ENV_FILE" | grep ".*\.yaml\|.*\.yml")" ]];then 
    _EC="env"
    _FF="-f"
else
    _FF="--file"
fi
cd $CW_INSTALLATION_PATH
print_info "Creating env, full log in $CW_BUILD_TMPDIR/build.log" 1
print_info "Command: conda $_EC create --name $CW_ENV_NAME $_FF $CW_ENV_FILE"
conda $_EC create --name $CW_ENV_NAME $_FF $CW_ENV_FILE >> $CW_BUILD_TMPDIR/build.log &
follow_log $! $CW_BUILD_TMPDIR/build.log 10  
conda activate $CW_ENV_NAME
if [[ ! -z $CW_REQUIREMENTS_FILE  ]];then
    pip install -r "$CW_REQUIREMENTS_FILE"
fi
cd $CW_WORKDIR
source $CW_INSTALLATION_PATH/_post_install.sh
echo 'echo "' > $CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/bin/list-packages
conda list >> $CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/bin/list-packages 
echo '"' >> $CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/bin/list-packages 
chmod +x $CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/bin/list-packages 

# Set here as they are dynamic
