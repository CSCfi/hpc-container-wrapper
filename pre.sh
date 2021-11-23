# Create tmpdir 
# Fetch/Copy any containers
# Copy any squashf
# Set correct paths to them
# Both are always copied for robustness 
# post takes care of placing the things in the 
# correct place
source common_functions.sh
set -e

if [[ ! -d $CW_BUILD_TMPDIR_BASE ]]; then
    print_err "Temporary dir $CW_BUILD_TMPDIR_BASE does not exist"    
else
    export $CW_BUILD_TMPDIR="$CW_BUILD_TMPDIR_BASE/cw-$(echo $RANDOM | md5sum | head -c 7)"
    print_info "Creating temporary dir $CW_BUILD_TMPDIR" 2
    if [[ -d $CW_BUILD_TMPDIR ]];then
        print_err "Temporary dir $CW_BUILD_TMPDIR already exists"    
    else
        mkdir -p $CW_BUILD_TMPDIR 
        mkdir -p $CW_BUILD_TMPDIR/_deploy
    fi
fi

if [[ ! -f $CW_CONTAINER_SRC ]]; 
    print_info "Fetching container $CW_CONTAINER_SRC"  2
    singularity --silent pull $CW_BUILD_TMPDIR/_deploy/$CW_CONTAINER_IMAGE $CW_CONTAINER_SRC || \
    print_err "Failed fetching container"
else
    print_info "Copying container $CW_CONTAINER_SRC" 2
fi
if [[ ! "$CW_NO_SQFS" ]];then 
    if [[ ! -f $CW_SQFS_SRC ]];
        print_err "SQFS image $CW_SQFS_SRC does not exist"
    else
        print_info "Copying image $CW_SQFS_SRC"
    fi
fi
