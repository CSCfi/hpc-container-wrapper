#!/bin/bash
cd  $CW_BUILD_TMPDIR
echo "export env_root=$CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/" >> _extra_envs.sh
echo "export env_root=$CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/" >> _vars.sh
cd $CW_INSTALLATION_PATH
export env_root=$CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/
eval "$($CW_INSTALLATION_PATH/miniconda/bin/conda shell.bash hook)"
cd $CW_WORKDIR
source $CW_INSTALLATION_PATH/_pre_install.sh
conda activate $CW_ENV_NAME
if [[ ${CW_REQUIREMENTS_FILE+defined}  ]];then
    print_info "Installing requirements file" 1
    pip install -r $( basename "$CW_REQUIREMENTS_FILE" )  > $CW_BUILD_TMPDIR/_pip.log &
    bg_pid=$!
    wait $bg_pid
    follow_log $bg_pid $CW_BUILD_TMPDIR/_pip.log 20
fi
cd $CW_WORKDIR
source $CW_INSTALLATION_PATH/_post_install.sh
echo 'echo "' > $CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/bin/list-packages
conda list >> $CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/bin/list-packages 
echo '"' >> $CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/bin/list-packages 
chmod +x $CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/bin/list-packages 

echo "CW_WRAPPER_PATHS+=( \"$CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/bin/\" )" >>  $CW_BUILD_TMPDIR/_vars.sh
