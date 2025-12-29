
export UPLINE=$(tput cuu1)
export ERASELINE=$(tput el)
erase_lines(){
    for i in $(eval echo "{1..$1}");do
        echo -e "$ERASELINE$UPLINE$ERASELINE\c" 
    done

}

use_color="yes"

if [[ -t 1 &&  "$use_color" = "yes" ]];then
  export   _red='\033[0;31m'
  export   _green='\033[0;32m'
  export   _yellow='\033[1;33m'
  export   _blue="\e[1;34m"
  export   _purple='\033[0;35m'
  export   _nc='\033[0m' # no color

else
  export   _red=""
  export   _green=""
  export   _yellow=""
  export   _blue=""
  export   _purple=""
  export   _nc=""
fi

#_RET_ID
getTestIdFromPid(){
    for i in $(seq 0 ${#PID_MAP[@]}); do
        if [[ ${PID_MAP[$i]} == $1 ]];then
             _RET_ID=$i
        fi
    done
}


waitAndCheck(){
    while [ -e /proc/$1 ]; do
        sleep 1
    done
    if ! [[ $(cat $2-status.out 2>/dev/null ) -eq 0  ]];then
        touch $3.skipped 
        return 1
    elif [[ -e $2.skipped ]];then
        touch $3.skipped 
        return 1
    else
        return 0
    fi
}

runTest(){

    if [[ "$FIRST_RUN" -eq 1 ]];then
        STATUS_ARRAY+=("${_blue}PENDING${_nc}")
        TEST_DESCRIPTION+=("$2")
        PID_MAP+=(N)
        TEST_IDX=$((TEST_IDX+1))
    else 
        # Not fully safe if the PIDs wrap around 
        if [[ ${#3} -ge 2 ]];then 
            getTestIdFromPid $3
            #{  while [ -e /proc/$3 ] ; do sleep 1;done ;   touch $TEST_IDX.running ; eval "$1" 2> $TEST_IDX.err 1> $TEST_IDX.log; echo $? > $TEST_IDX-status.out; rm $TEST_IDX.running ;   }  &
            {   waitAndCheck $3 $_RET_ID $TEST_IDX && { touch $TEST_IDX.running ; eval "$1" 2> $TEST_IDX.err 1> $TEST_IDX.log; echo $? > $TEST_IDX-status.out; rm $TEST_IDX.running ;   }  ; }  &
            BACKGROUND_PID=$!
            PID_MAP[$TEST_IDX]=$BACKGROUND_PID
            idxp=$(printf "%03d" $_RET_ID)
            STATUS_ARRAY[$TEST_IDX]="${_purple}BLOCKED by $idxp${_nc}"
            #echo $bpid
        # Schedule directly
        else 
            touch $TEST_IDX.running
            { eval "$1" 2> $TEST_IDX.err 1> $TEST_IDX.log; echo $? > $TEST_IDX-status.out; rm $TEST_IDX.running ;} &
            BACKGROUND_PID=$!
            PID_MAP[$TEST_IDX]=$BACKGROUND_PID
         
        fi
        TEST_IDX=$((TEST_IDX+1))
    fi

    
}

updateStatus(){
    changed=0
    re='^[0-9]+$'
    for i in $(seq 0 $1);do
        CT=${STATUS_ARRAY[$i]}
        if [[ -e $i.running ]];then
            CT=${_yellow}RUNNING${_nc}
        elif [[ -e $i.skipped ]];then
            CT="${_red}SKIPPED${_nc}"
        elif [[ -e $i-status.out ]];then
            ret=$(cat $i-status.out)
            if [[ "$ret" == "0"  ]]; then
                CT=${_green}OK${_nc}
            elif [[ "$ret" =~ $re ]];then
                CT="${_red}FAILED${_nc}"
            else
                CT=UNKNOWN
            fi
            
        fi
        if [[ "$CT" != ${STATUS_ARRAY[$i]} ]];then
            STATUS_ARRAY[$i]=$CT
            changed=1
        fi
    done
    return $changed
}


printStatus(){
    idx=0
    for  i in "${STATUS_ARRAY[@]}"; do
        idxp=$(printf "%03d" $idx)
        echo -e "$idxp [ $i ] ${TEST_DESCRIPTION[$idx]}"
        idx=$((idx+1))
    done
    
}
