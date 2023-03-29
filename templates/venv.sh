#!/bin/bash
set -e


cd  $CW_BUILD_TMPDIR
echo "export env_root=$CW_INSTALLATION_PATH/$CW_ENV_NAME/" >> _extra_envs.sh
echo "export env_root=$CW_INSTALLATION_PATH/$CW_ENV_NAME/" >> _vars.sh
export env_root=$CW_INSTALLATION_PATH/$CW_ENV_NAME/

cd $CW_INSTALLATION_PATH


cd $CW_WORKDIR
source $CW_INSTALLATION_PATH/_pre_install.sh
cd $CW_INSTALLATION_PATH

if [[ ${CW_ENABLE_SITE_PACKAGES+defined} ]];then
    print_info "Enabling system and user site packages" 1
    _SP="--system-site-packages"
else
    print_info "Not enabling system and user site packages" 1
    _SP=""
fi
print_info "Installing requirements file" 1
python3 -m venv $_SP $CW_ENV_NAME
source $CW_INSTALLATION_PATH/$CW_ENV_NAME/bin/activate

if [[ ${CW_REQUIREMENTS_FILE+defined}  ]];then
    pip install --disable-pip-version-check -r "$( basename $CW_REQUIREMENTS_FILE)" > $CW_BUILD_TMPDIR/_pip.log &
    bg_pid=$!
    wait $bg_pid
    follow_log $bg_pid $CW_BUILD_TMPDIR/_pip.log 10
fi
cd $CW_WORKDIR
print_info "Running user supplied commands" 1
source $CW_INSTALLATION_PATH/_post_install.sh

echo "CW_WRAPPER_PATHS+=( \"$CW_INSTALLATION_PATH/$CW_ENV_NAME/bin/\" )" >>  $CW_BUILD_TMPDIR/_vars.sh
