#!/bin/bash
cd $CW_WORKDIR
cd $CW_INSTALLATION_PATH
eval "$($CW_INSTALLATION_PATH/miniconda/bin/conda shell.bash hook)"
source _pre_install.sh
conda activate $CW_ENV_NAME
if [[ ! -z $CW_REQUIREMENTS_FILE  ]];then
    pip install -r "$CW_REQUIREMENTS_FILE"
fi
cd $CW_WORKDIR
source _post_install.sh
echo 'echo "' > $CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/bin/list-packages
conda list >> $CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/bin/list-packages 
echo '"' >> $CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/bin/list-packages 
chmod +x $CW_INSTALLATION_PATH/miniconda/envs/$CW_ENV_NAME/bin/list-packages 
