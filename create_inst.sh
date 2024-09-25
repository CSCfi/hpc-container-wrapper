#!/bin/bash
set -e
set -u
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source $SCRIPT_DIR/common_functions.sh
source $CW_BUILD_TMPDIR/_vars.sh
SINGULARITY_BIND=""



mkdir $CW_BUILD_TMPDIR/_inst_dir
if [[ ${CW_INSTALLATION_FILE_PATHS+defined} ]];then
    cp -a "${CW_INSTALLATION_FILE_PATHS[@]}" $CW_BUILD_TMPDIR/_inst_dir
fi
if [[ ${CW_TEMPLATE_SCRIPT+defined} ]];then
    cp $SCRIPT_DIR/templates/$CW_TEMPLATE_SCRIPT $CW_BUILD_TMPDIR/_inst_dir
fi
cp $SCRIPT_DIR/common_functions.sh $CW_BUILD_TMPDIR/_inst_dir

cd $CW_BUILD_TMPDIR
chmod +x ./_sing_inst_script.sh

if [[ "$CW_ISOLATE" == "yes" ]]; then
    _DIRS=(${CW_MOUNT_POINTS[@]})
else
    export SINGULARITYENV_PATH="$PATH"
    if [[ ${LD_LIBRARY_PATH+defined} ]];then
        export SINGULARITYENV_LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
    fi
    _DIRS=($(ls -1 / | awk '!/dev/' | sed 's/^/\//g' ))
fi
for d in "${_DIRS[@]}"; do
    if [[ -z "$SINGULARITY_BIND" ]];then
        test -d $d && export SINGULARITY_BIND="$d"
    else
        test -d $d && export SINGULARITY_BIND="$SINGULARITY_BIND,$d"
    fi
done
SINGULARITY_BIND="$SINGULARITY_BIND,/tmp"
# By default we want to disable the user condarc as that
# might interfere with the installation
if [[ ! ${CW_ENABLE_CONDARC+defined} ]]; then
    export CONDA_PKGS_DIRS=$CW_INSTALLATION_PATH/miniforge/pkgs
fi
export SINGULARITY_BIND
echo "export install_root=$CW_INSTALLATION_PATH" >> _extra_envs.sh
echo "export install_root=$CW_INSTALLATION_PATH" >> _vars.sh
export install_root=$CW_INSTALLATION_PATH




if [[ "$CW_UPDATE_INSTALLATION" == "yes" ]];then
    _CONTAINER_EXEC="$CW_SINGULARITY_EXECUTABLE_PATH --silent exec -B _deploy/$CW_SQFS_IMAGE:$CW_SOURCE_MOUNT_POINT:image-src=/ _deploy/$CW_CONTAINER_IMAGE"
    export SINGULARITY_BIND="$SINGULARITY_BIND,$PWD/_inst_dir:$CW_INSTALLATION_PATH,$_inst_path/_bin:$_inst_path/bin"
    print_info "Copying installation to writable area, might take a while" 1
    print_info "$(readlink -f $CW_INSTALLATION_PREFIX)" 1
    $_CONTAINER_EXEC cp -a $CW_SOURCE_MOUNT_POINT/. $CW_INSTALLATION_PATH || { print_err "Failed to copy some files, most likely incorrect file permissions inside the squashfs image" && false ; }
elif [[ "$CW_MODE" == "wrapdisk" ]];then
    export SINGULARITY_BIND="$SINGULARITY_BIND,$PWD/_inst_dir:$CW_INSTALLATION_PATH,$CW_WRAP_SRC:$CW_SOURCE_MOUNT_POINT"
    _CONTAINER_EXEC="$CW_SINGULARITY_EXECUTABLE_PATH --silent exec _deploy/$CW_CONTAINER_IMAGE"
    
else
    export SINGULARITY_BIND="$SINGULARITY_BIND,$PWD/_inst_dir:$CW_INSTALLATION_PATH"
    _CONTAINER_EXEC="$CW_SINGULARITY_EXECUTABLE_PATH --silent exec _deploy/$CW_CONTAINER_IMAGE"
fi
cp ./_sing_inst_script.sh _pre_install.sh _post_install.sh _inst_dir 
print_info "Running installation script" 1
$_CONTAINER_EXEC ./_sing_inst_script.sh
rm -f $PWD/_inst_dir/condarc_override

chmod o+r -R _inst_dir/
print_info "Creating sqfs image" 1 
if [[ $CW_NUM_CPUS -gt $CW_MAX_NUM_CPUS ]]; then
    _cpus=$CW_MAX_NUM_CPUS
else
    _cpus=$CW_NUM_CPUS
fi
# There should be a separate folder so that removal is easier
(cd _inst_dir && rm -f _vars.sh common_functions.sh  _sing_inst_script.sh _pre_install.sh _post_install.sh $CW_TEMPLATE_SCRIPT  _extra_user_envs.sh _extra_envs.sh )


# Save old configurations in separate folder so they are not overridden
counter=0
while true;do
if [[ -e _inst_dir/previous_input/$counter ]]; then
    counter=$((counter+1))
else
    mkdir -p _inst_dir/previous_input/$counter
    break
fi
done
for fp in "${CW_INSTALLATION_FILE_PATHS[@]}";do
    n=$(basename $fp)
    mv _inst_dir/$n _inst_dir/previous_input/$counter
done
####### 



if [[ ! ${CW_NO_FIX_PERM+defined}  ]];then
    print_info "Fixing permissions within squashfs image" 2
    chmod -R ugo+rwX _inst_dir 
fi

mksquashfs _inst_dir/ _deploy/$CW_SQFS_IMAGE -processors $_cpus $CW_SQFS_OPTIONS 
 
# Check if we need to fix group permissions
stat -c "%a" $CW_BUILD_TMPDIR | grep ".[67]." -q && chmod g+w _deploy/$CW_SQFS_IMAGE

