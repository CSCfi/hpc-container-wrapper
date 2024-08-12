# Tykky shell functions to activate/deactivate environments

__tykky_get_env_path() {
    # Get and validate installation path of a tykky environment.
    # If a name is passed as an argument, try to find it in colon-separated
    # list TYKKY_PATH

    __candidate=""
    case "$1" in
        */*)
            __candidate="${1%/}"
            ;;
        *)
            oldIFS=$IFS
            IFS=:
            for __tykky_path in ${TYKKY_PATH:-""}; do
                IFS=$oldIFS
                if [ -d "$__tykky_path/$1" ]; then
                    __candidate="${__tykky_path%/}/${1%/}"
                    break
                fi
            done
            
            ;;
    esac

    # Validation of genunine tykky installation
    if [ -f "$__candidate/common.sh" ] && [ -d "$__candidate/bin" ]; then
        echo "$__candidate"
        unset __candidate __tykky_path 
    else
        unset __candidate __tykky_path 
        echo "ERROR: $1 is not a valid tykky environment" >&2
        false
    fi

}

__tykky_activate() {
    # Activate a Tykky environment. Change PS1 if interactive by default,
    # unless TYKKY_CHANGE_PS1 is set to 0

    if [ -z "${2:-}" ]; then
        echo "ERROR: You must specify a valid tykky environment to activate" >&2
        false
        return
    fi
    __candidate=$(__tykky_get_env_path $2)
    if [ "$?" -ne 0 ]; then
        false
        return
    fi
    if [ -n "$__candidate" ]; then
        __tykky_deactivate
        export TYKKY_PREFIX="$__candidate"
        export PATH=$TYKKY_PREFIX/bin:$PATH
        if [ -n "${PS1:-}" ] && [ "${TYKKY_CHANGE_PS1:-}" != "0" ]; then
            PS1="($(basename $(echo $TYKKY_PREFIX))) $PS1"
        fi
    fi
    unset __candidate
}


__tykky_deactivate() {
    # Dectivate a Tykky environment. Change PS1 if interactive by default,

    if [ -n "${TYKKY_PREFIX:-}" ]; then
        export PATH=$(echo $PATH | sed -e "s|$TYKKY_PREFIX/bin:||g")
        if [ -n "${PS1:-}" ]; then 
            PS1="$(echo "$PS1" | sed -e "s|^($(basename $TYKKY_PREFIX)) ||")"
        fi
        unset TYKKY_PREFIX
    fi
}


tykky() {
    # Top level shell function to activate and deactivate Tykky environments

    case "${1:-}" in
        activate)
            __tykky_activate "$@"
            ;;
        deactivate)
            __tykky_deactivate "$@"
            ;;
        *)
            echo "Usage: tykky activate <env_name_or_dir>"
            echo "       tykky deactivate"
            ;;
    esac
}
