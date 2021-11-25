#!/bin/bash

if [[ ! ${USE_COLOR+defined} ]];then
   export USE_COLOR="yes"
fi
if [[ ! ${CW_LOG_LEVEL+defined} ]];then
    CW_LOG_LEVEL="2"
fi

if [[ -t 1 &&  "$USE_COLOR" = "yes" ]];then
  export   _RED='\033[0;31m'
  export   _GREEN='\033[0;32m'
  export   _YELLOW='\033[1;33m'
  export   _BLUE="\e[1;34m"
  export   _NC='\033[0m' # No Color
else
  export   _RED=""
  export   _GREEN=""
  export   _YELLOW=""
  export   _BLUE=""
  export   _NC=""
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
# Errors are always printed
print_err(){
        >&1 echo -e "[ ${_RED}ERROR${_NC} ] $1 " | sed '2,$s/^/         /g'
}

## Fancy info

export UPLINE=$(tput cuu1)
export ERASELINE=$(tput el)
erase_lines(){
    for i in $(eval echo "{1..$1}");do
        echo -e "$ERASELINE$UPLINE$ERASELINE\c" 
    done

}
export -f erase_lines
counter=1
follow_log(){
    set -e
    p_pid=$1
    log_file=$2
    output_length=$3

    trap "kill $p_pid 2> /dev/null" EXIT
    trap "kill $p_pid 2> /dev/null" INT
    trap "kill $p_pid 2> /dev/null" ERR
    echo "========================="
    while kill -0 $p_pid 2> /dev/null; do
        res="$(tail -n $output_length $log_file)"
        res_lines="$(echo -e "$res" | wc -l )"
        echo -e "$res"
        echo "========================="
        counter=$(($counter +1))
        sleep 1
        if [[   "$output_length" -gt "$res_lines" ]];then
            erase_lines $res_lines
        else
            erase_lines $output_length
        fi
        erase_lines 1
    done
    trap - EXIT
    trap - INT
    trap - ERR
    res="$(tail -n $output_length $log_file)"
    echo -e "$res"
    echo "========================="
}



export -f follow_log
export -f print_info
export -f print_warn
export -f print_err
