#!/bin/bash
set -e


cd  $CW_BUILD_TMPDIR
echo "export env_root=$CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/" >> _extra_envs.sh
echo "export env_root=$CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/" >> _vars.sh
export env_root=$CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/

cd $CW_INSTALLATION_PATH


print_info "Using miniconda version Miniconda3-$CW_CONDA_VERSION-$CW_CONDA_ARCH" 1
print_info "Downloading miniconda " 2
curl https://repo.anaconda.com/miniconda/Miniconda3-$CW_CONDA_VERSION-$CW_CONDA_ARCH.sh --output Miniconda_inst.sh &>/dev/null 
print_info "Installing miniconda " 1 
bash Miniconda_inst.sh -b -p $CW_INSTALLATION_PATH/miniconda  > $CW_BUILD_TMPDIR/_inst_miniconda.log &   
inst_pid=$!
follow_log $inst_pid $CW_BUILD_TMPDIR/_inst_miniconda.log 10
rm Miniconda_inst.sh
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

if [[ ${CW_MAMBA} == "yes" ]] ;then
    print_info "Using mamba to install packages" 1 
    conda install -y mamba -n base -c conda-forge
    mamba $_EC create --name $CW_ENV_NAME $_FF $CW_ENV_FILE &>> $CW_BUILD_TMPDIR/build.log &
else
    conda $_EC create --name $CW_ENV_NAME $_FF $CW_ENV_FILE &>> $CW_BUILD_TMPDIR/build.log &
fi

inst_pid=$!
follow_log $inst_pid $CW_BUILD_TMPDIR/build.log 10  
wait $inst_pid
conda activate $CW_ENV_NAME
if [[ ${CW_REQUIREMENTS_FILE+defined}  ]];then
    pip install -r $( basename "$CW_REQUIREMENTS_FILE" )
fi
cd $CW_WORKDIR
print_info "Running user supplied commands" 1
source $CW_INSTALLATION_PATH/_post_install.sh
if [[ -d $CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/bin/ ]];then
    echo 'echo "' > $CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/bin/list-packages
    conda list >> $CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/bin/list-packages 
    echo '"' >> $CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/bin/list-packages 
    chmod +x $CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/bin/list-packages 
else
    print_warn "Created env is empty"
fi


# Set here as they are dynamic
# Could also set them in construct.py...
echo "CW_WRAPPER_PATHS+=( \"$CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/bin/\" )" >>  $CW_BUILD_TMPDIR/_vars.sh
