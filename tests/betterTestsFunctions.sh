
export UPLINE=$(tput cuu1)
export ERASELINE=$(tput el)



export SAVE_POS=$'\033[s'   # ESC [ s
export RESTORE_POS=$'\033[u' # ESC [ u
export CLEAR_EOS=$'\033[J'   # ESC [ J


move_to() {           # move to row, col
  printf '%s' "$(tput cup "$1" "$2")"
}
clear_eol() {         # clear to end of line
  printf '%s' "$(tput el)"
}
clear_from_top() {    # go to top-left and clear to end of screen
  move_to 0 0
  printf '%s' "$(tput ed)"
}

draw_line() {         # write text and clear rest of line
  #printf '%s' "$1"
  #
  echo -ne "$1"
  clear_eol
}

# Track previous frame
declare -a LAST=()

# Redraw only changed lines; assumes anchor at (0,0)
redraw_lines() {
  local -a CUR=("$@")
  local rows=${#CUR[@]}

  # On first draw or forced full redraw, clear downwards from top
  if [[ ${#LAST[@]} -eq 0 ]]; then
    clear_from_top
  fi

  # Update only the lines that changed
  for ((r=0; r<rows; r++)); do
    if [[ "${CUR[r]-}" != "${LAST[r]-}" ]]; then
      move_to "$r" 0
      draw_line "${CUR[r]}"
    fi
  done

  # If previously we had more lines, clear the leftovers
  if (( ${#LAST[@]} > rows )); then
    for ((r=rows; r<${#LAST[@]}; r++)); do
      move_to "$r" 0
      clear_eol
    done
  fi

  LAST=("${CUR[@]}")
}

# Optional: handle terminal resize gracefully
need_full_redraw=1
trap 'need_full_redraw=1; LAST=()' WINCH

# Optional: hide cursor for smoother look; ensure it is restored on exit
printf '\033[?25l'
#trap 'printf "\033[?25h"' EXIT




erase_lines(){
    for i in $(eval echo "{1..$(($1 +1))}");do
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
        echo $2 > $3.skipped 
        return 1
    elif [[ -e $2.skipped ]];then
        cat $2.skipped > $3.skipped 
        return 1
    else
        return 0
    fi
}





setupFifo(){
    SEMFILE=/tmp/mysem.$$
    mkfifo "$SEMFILE"
    exec {SEM}<> "$SEMFILE"
    M=$1
    # Create a FIFO and preload M tokens
    echo "[ CREATED FIFO $SEMFILE, max test = $M]"
    # Background: continuously re-provide tokens from a subshell holding M of them
    # The trick: cat reads tokens from writers (release) and tee feeds new readers (acquire)
    {
    
      for i in $(seq 1 "$M"); do echo -e "token-in-$i" ; done
    } >& $SEM # &   # writer that keeps the FIFO supplied
}

# acquire: read one token from the FIFO (blocks if none available)
acquire() { 
    touch $1.pending
    read -r tok <& $SEM  
    rm $1.pending
}

# release: write a token back into the FIFO
release() { 
    echo -e "token-$1" >& $SEM 

}

cleanup() {
 
  exec 3>/dev/tty
  echo -e "\e[?25h" >&3
  exec {SEM}<>-
  rm -f "$SEMFILE"
  kill -TERM -- -$$
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
            {   waitAndCheck $3 $_RET_ID $TEST_IDX && {   touch $TEST_IDX.running ; eval "$1" 2> $TEST_IDX.err 1> $TEST_IDX.log; echo $? > $TEST_IDX-status.out; rm $TEST_IDX.running ;   }  ; }  &
            BACKGROUND_PID=$!
            PID_MAP[$TEST_IDX]=$BACKGROUND_PID
            idxp=$(printf "%03d" $_RET_ID)
            STATUS_ARRAY[$TEST_IDX]="${_purple}BLOCKED by $idxp${_nc}"
            #echo $bpid
        # Schedule directly
        else 
            { acquire $TEST_IDX; touch $TEST_IDX.running ; eval "$1" 2> $TEST_IDX.err 1> $TEST_IDX.log; echo $? > $TEST_IDX-status.out; rm $TEST_IDX.running ; release $TEST_IDX  ;} &
            BACKGROUND_PID=$!
            PID_MAP[$TEST_IDX]=$BACKGROUND_PID
         
        fi
        TEST_IDX=$((TEST_IDX+1))
    fi

    
}

##
##

updateStatus(){
    changed=0
    re='^[0-9]+$'
    for i in $(seq 0 $1);do
        CT=${STATUS_ARRAY[$i]}
       if [[ -e $i.pending ]];then
          CT="${_blue}WAITING FOR SLOT${_nc}"
        elif [[ -e $i.running ]];then
            CT=${_yellow}RUNNING${_nc}
        elif [[ -e $i.skipped ]];then
            CT="${_red}SKIPPED DUE TO $(<$i.skipped) ${_nc}"
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
        if ! [[ "$CT" == "${STATUS_ARRAY[$i]}" ]];then
            STATUS_ARRAY[$i]=$CT
            changed=1
        fi
    done
    changed=1
    return $changed
}


printStatus(){
    idx=0
    lines=()
    events=()
    time=$(date '+%H:%M:%S')
    lines+="Time: $time"
    for  i in "${STATUS_ARRAY[@]}"; do
        idxp=$(printf "%03d" $idx)
        lines+=("$idxp [ $i ] ${TEST_DESCRIPTION[$idx]}")
    if ! [ -t 1 ]; then
        if ! [[ "${STATUS_ARRAY[$idx]}" == "${OLD_STATUS_ARRAY[$idx]}" ]] ; then
            events+=("TASK $idx changed from ${OLD_STATUS_ARRAY[$idx]} to ${STATUS_ARRAY[$idx]}")
            OLD_STATUS_ARRAY[$idx]=${STATUS_ARRAY[$idx]}
        fi
    fi
        idx=$((idx+1)) 
    done
    if [ -t 1 ]; then
     if (( need_full_redraw )); then
         clear_from_top               
          need_full_redraw=0           
         LAST=()                      
     fi                                                            
     redraw_lines "${lines[@]}"     
    else
        echo "Status at $time"
        for e in "${events[@]}"; do
            echo "$e"
        done
    fi                          
}
