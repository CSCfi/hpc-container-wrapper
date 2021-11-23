#!/bin/bash
set -e
set -u
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source $SCRIPT_DIR/common_functions.sh

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

echo "$CW_BUILD_TMPDIR"
