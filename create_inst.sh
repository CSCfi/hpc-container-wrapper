#!/bin/bash
set -e
set -u
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source $SCRIPT_DIR/common_functions.sh
source $CW_BUILD_TMPDIR/_vars.sh
SINGULARITY_BIND=""

mkdir $CW_BUILD_TMPDIR/_inst_dir
cp -a "${CW_INSTALLATION_FILE_PATHS[@]}" $CW_BUILD_TMPDIR/_inst_dir
cd $CW_BUILD_TMPDIR
chmod +x ./_sing_inst_script.sh
cp ./_sing_inst_script.sh _pre_install.sh _post_install.sh _inst_dir 

if [[ "$CW_ISOLATE" == "yes" ]]; then
    _DIRS=(${CW_MOUNT_POINTS[@]})
else
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
export SINGULARITY_BIND

if [[ "$CW_UPDATE_INSTALLATION" == "yes" ]];then
    _CONTAINER_EXEC="singularity --silent exec -B $PWD/_inst_dir:$CW_INSTALLATION_PATH,$CW_SQFS_SRC:$CW_SOURCE_MOUNT_POINT:image-src=/ _deploy/$CW_CONTAINER_IMAGE"
    _CONTAINER_EXEC cp -a $CW_SOURCE_MOUNT_POINT $CW_INSTALLATION_PATH
elif [[ "$CW_MODE" == "wrap" ]];then
    _CONTAINER_EXEC="singularity --silent exec -B $PWD/_inst_dir:$CW_INSTALLATION_PATH,$CW_WRAP_SRC:$CW_SOURCE_MOUNT_POINT:image-src=/ _deploy/$CW_CONTAINER_IMAGE"
    
else
    _CONTAINER_EXEC="singularity --silent exec -B $PWD/_inst_dir:$CW_INSTALLATION_PATH _deploy/$CW_CONTAINER_IMAGE "
fi
print_info "Running installation script" 1
$_CONTAINER_EXEC bash -c "cd $CW_INSTALLATION_PATH && ./_sing_inst_script.sh"

chmod o+rx -R _inst_dir/
print_info "Creating sqfs image" 1 
if [[ $CW_NUM_CPUS -gt $CW_MAX_NUM_CPUS ]]; then
    mksquashfs _inst_dir/ _deploy/$CW_SQFS_IMAGE  -processors $CW_MAX_NUM_CPUS $CW_SQFS_OPTIONS
else
    mksquashfs _inst_dir/ _deploy/$CW_SQFS_IMAGE  -processors $CW_NUM_CPUS $CW_SQFS_OPTIONS 
fi
