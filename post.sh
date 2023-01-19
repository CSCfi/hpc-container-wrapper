set -e
set -u
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source $SCRIPT_DIR/common_functions.sh
source $CW_BUILD_TMPDIR/_vars.sh

print_info "Installing to $CW_INSTALLATION_PREFIX" 1

if [[ ${CW_UPDATE_INSTALLATION+defined } && "$CW_UPDATE_INSTALLATION" == "yes" ]];then
    # This might fail if the installation resides on a lustre file system
    # And is being used by another client while we try to remove the bin directory
    # Due to the bin being using in a filesystem mount
    # This would produce the error "rm: 'cannot remove Path/to/bin': Device or resource busy"
    rm -fr $CW_INSTALLATION_PREFIX/bin || print_warn "Failed to remove $CW_INSTALLATION_PREFIX/bin due to it being in use\n\tContinuing anyway"
    rm -fr $CW_INSTALLATION_PREFIX/_bin 
    rm -fr $CW_INSTALLATION_PREFIX/share  
fi
    cp -rd $CW_BUILD_TMPDIR/_deploy/* $CW_INSTALLATION_PREFIX/
    mkdir -p $CW_INSTALLATION_PREFIX/share
    if [[ ${CW_INSTALLATION_FILE_PATHS+defined} ]]; then
        for _fil in ${CW_INSTALLATION_FILE_PATHS[@]}; do
            mv $CW_BUILD_TMPDIR/_inst_dir/$( basename $_fil ) $CW_INSTALLATION_PREFIX/share 
        done
    fi
    echo "tag: $(git -C $SCRIPT_DIR describe --tags)" >> $CW_INSTALLATION_PREFIX/share/VERSION.yml
    echo "commit: $(git -C $SCRIPT_DIR rev-parse --short HEAD )" >>  $CW_INSTALLATION_PREFIX/share/VERSION.yml
    echo "build-time: $(date)" >>  $CW_INSTALLATION_PREFIX/share/VERSION.yml 
    
    cp $CW_BUILD_TMPDIR/conf.yaml $CW_INSTALLATION_PREFIX/share

rm -rf $CW_BUILD_TMPDIR
