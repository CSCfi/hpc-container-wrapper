#!/bin/bash -eu
M_SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

export PATH="$(realpath $M_SCRIPT_DIR/../bin):$PATH"

rm -f test.log


if [[ ! ${USE_COLOR+defined} ]];then
   export USE_COLOR="yes"
fi
if [[ ${CW_LOG_LEVEL+defined} ]];then
    unset CW_LOG_LEVEL
fi
unset CW_DEBUG_KEEP_FILES
export PYTHONNOUSERSITE=1
[[ $(type -t module) == function ]] && module purge || true
export CONFIG_YAML="$M_SCRIPT_DIR/../configs/${CONFIG:?run tests with CONFIG=<config>}.yaml"

if [[ -t 1 &&  "$USE_COLOR" = "yes" ]];then
  export   _RED='\033[0;31m'
  export   _GREEN='\033[0;32m'
  export   _YELLOW='\033[1;33m'
  export   _BLUE="\e[1;34m"
  export   _PURPLE='\033[0;35m'
  export   _NC='\033[0m' # No Color

else
  export   _RED=""
  export   _GREEN=""
  export   _YELLOW=""
  export   _BLUE=""
  export   _PURPLE=""
  export   _NC=""
fi

_msg(){
    echo -en "[ - ] $1\r"
}

_ok (){
    echo -e "[ ${_GREEN}OK${_NC} ] $1"

}
_fail(){
    echo -e "[ ${_RED}FAILED${_NC} ]  $1"
}


_failures=0
trap 'exit $(( _failures > 0 ))' EXIT

t_workdir(){
    rm -fr "$1" && mkdir "$1" && cd "$1"
}

t_run(){
    _msg "$2"
    if eval "$1" &>>test.log; then
        _ok "$2"
    else
        _fail "$2"
        _failures=$((_failures + 1))
    fi
}
