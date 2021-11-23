#!/bin/bash
set -u 
unset SINGULARITY_BIND

source common_functions.sh 
source shared_vars.sh
source inst_vars.sh


cd $CW_BUILD_TMPDIR
mkdir _inst_dir

cp ./_sing_inst_script.sh $CW_INSTALLATION_PATH 
cp -a "${CW_INSTALLATION_FILES_PATHS[@]}" $CW_INSTALLATION_PATH

if [[ "$CW_ISOLATE" == "yes" ]]; then
    _DIRS=(${CW_MOUNTPOINTS[@]})
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
SINGULARITY_BIND="$SINGULARITY_BIND,$TMPDIR,$TMPDIR:/tmp"
export SINGULARITY_BIND

if [[ "$CW_UPDATE_INSTALLATION" == "yes" ]];then
    _CONTAINER_EXEC="singularity --silent exec -B $PWD/_inst_dir:$CW_INSTALLATION_PATH,$CW_SQFS_SRC:$CW_SOURCE_MOUNT_POINT:image-src=/ _deploy/$CW_CONTAINER_IMAGE"
    _CONTAINER_EXEC cp -a $CW_SOURCE_MOUNT_POINT $CW_INSTALLATION_PATH
else
    _CONTAINER_EXEC="singularity --silent exec -B $PWD/_inst_dir:$CW_INSTALLATION_PATH _deploy/$CW_CONTAINER_IMAGE "
fi
_CONTAINER_EXEC bash -c "cd $CW_INSTALLATION_PATH && ./_sing_inst_script.sh"

chmod o+rx -R _inst_dir/
if [[ $CW_NUM_CPUS -gt $CW_MAX_NUM_CPUS ]];
    mksquashfs _inst_dir/ $CW_SQFS_IMAGE  -processors $CW_MAX_NUM_CPUS $CW_SQFS_OPTIONS
else
    mksquashfs _inst_dir/ $CW_SQFS_IMAGE  -processors $CW_NUM_CPUS $CW_SQFS_OPTIONS 
fi
