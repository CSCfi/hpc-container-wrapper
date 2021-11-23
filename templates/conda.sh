#!/bin/bash
cd $CW_INSTALLATION_PATH
curl https://repo.anaconda.com/miniconda/Miniconda3-$CW_CONDA_VERSION-$CW_CONDA_ARCH.sh --output Miniconda_inst.sh
bash Miniconda_inst.sh -b -p $CW_INSTALLATION_PATH/miniconda
eval "$($CW_INSTALLATION_PATH/miniconda/bin/conda shell.bash hook)"
cd $CW_WORKDIR
source _pre_install.sh
if [[ -z "$(echo "$CW_ENV_FILE" | grep "*\.yaml\|*\.yml")" ]];then 
    _EC="env"
    _FF="-f"
else
    _FF="--file"
fi
conda $_EC create --name $CW_ENV_NAME $_FF $CW_ENV_FILE
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
