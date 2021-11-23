#!/bin/bash
if [[ -t 1 && "$USE_COLOR" = "yes" ]];then
    _RED='\033[0;31m'
    _GREEN='\033[0;32m'
    _YELLOW='\033[1;33m'
    _BLUE="\e[1;34m"
    _NC='\033[0m' # No Color
else
    _RED=""
    _GREEN=""
    _YELLOW=""
    _BLUE=""
    _NC=""
fi


# _print_info <log level threshold>
print_info(){
    if [[ $CW_LOG_LEVEL -gt $2 ]];then
        >&1 echo -e "[ ${_BLUE}INFO${_NC} ] $1 " | sed '2,$s/^/         /g'
    fi
}
print_warn(){
    if [[ $CW_LOG_LEVEL -gt 0  ]];then
        >&1 echo -e "[ ${_YELLOW}WARNING${_NC} ] $1 " | sed '2,$s/^/         /g'
    fi
}
print_err(){
    if [[ $CW_LOG_LEVEL -gt -1  ]];then
        >&1 echo -e "[ ${_RED}ERROR${_NC} ] $1 " | sed '2,$s/^/         /g'
    fi
}

