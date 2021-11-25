set -e
set -u
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source $SCRIPT_DIR/common_functions.sh
source $CW_BUILD_TMPDIR/_vars.sh

print_info "Installing to $CW_INSTALLATION_PREFIX" 1
cp -a $CW_BUILD_TMPDIR/_deploy/* $CW_INSTALLATION_PREFIX/
rm -rf $CW_BUILD_TMPDIR
