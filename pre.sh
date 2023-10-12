# Create tmpdir 
# Fetch/Copy any containers
# Copy any squashf
# Set correct paths to them
# Both are always copied for robustness 
# post takes care of placing the things in the 
# correct place
set -e
set -u
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source $SCRIPT_DIR/common_functions.sh
source $CW_BUILD_TMPDIR/_vars.sh
mkdir -p  $CW_BUILD_TMPDIR/_deploy/

if [[ ! -e $CW_CONTAINER_SRC ]]; then 
    print_info "Fetching container $CW_CONTAINER_SRC"  1
    $CW_SINGULARITY_EXECUTABLE_PATH --silent pull $CW_BUILD_TMPDIR/_deploy/$CW_CONTAINER_IMAGE $CW_CONTAINER_SRC || \
    { print_err "Failed fetching container"; exit 1 ;}
    if [[ ! -e $CW_BUILD_TMPDIR/_deploy/$CW_CONTAINER_IMAGE ]];then
	{ print_err "$CW_SINGULARITY_EXECUTABLE_PATH pull returned success, but no container was fetched"; exit 1 ;}
    fi
else
    if [[ ${CW_SHARE_CONTAINER+defined} && ${CW_SHARE_CONTAINER} == "yes" ]];then
        print_info "Using container $CW_CONTAINER_SRC" 1
        ln -s $(realpath -s "$CW_CONTAINER_SRC") "$CW_BUILD_TMPDIR/_deploy/$CW_CONTAINER_IMAGE" 
    else
        print_info "Copying container $CW_CONTAINER_SRC" 1
        cp "$CW_CONTAINER_SRC" "$CW_BUILD_TMPDIR/_deploy/$CW_CONTAINER_IMAGE"
    fi
fi
if [[  "${CW_SQFS_SRC+defined}" ]];then 
    if [[ ! -f $CW_SQFS_SRC ]]; then
        print_err "SQFS image $CW_SQFS_SRC does not exist"
        exit 1
    else
        print_info "Copying image $CW_SQFS_SRC" 1
        cp "$CW_SQFS_SRC" "$CW_BUILD_TMPDIR/_deploy/$CW_SQFS_IMAGE"
    fi
fi
