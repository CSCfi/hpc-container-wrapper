# Tykky shell functions to activate/deactivate environments (bash and zsh)

tykky() {
    case "${1:-}" in
        activate) __tykky_activate "$@" ;;
        deactivate) __tykky_deactivate ;;
        *)
            echo "Usage: tykky activate <env_name_or_dir>"
            echo "       tykky deactivate"
            ;;
    esac
}

# Activate a Tykky environment. Change PS1 if interactive, unless TYKKY_CHANGE_PS1=0
__tykky_activate() {
    local prefix
    if [ -z "${2:-}" ]; then
        echo "ERROR: You must specify a valid tykky environment to activate" >&2
        return 1
    fi
    prefix=$(__tykky_get_env_path "$2") || return 1
    __tykky_deactivate
    export TYKKY_PREFIX="$(realpath "$prefix")"
    export PATH="$TYKKY_PREFIX/bin:$PATH"
    if [ -n "${PS1:-}" ] && [ "${TYKKY_CHANGE_PS1:-}" != "0" ]; then
        PS1="(${TYKKY_PREFIX##*/}) $PS1"
    fi
}

# Undo exactly what __tykky_activate added
__tykky_deactivate() {
    local p
    [ -n "${TYKKY_PREFIX:-}" ] || return 0
    p=":$PATH:"
    p="${p/":$TYKKY_PREFIX/bin:"/:}"
    p="${p#:}"
    PATH="${p%:}"
    PS1="${PS1#"(${TYKKY_PREFIX##*/}) "}"
    unset TYKKY_PREFIX
}

# Print the path of a tykky environment given as a directory, or as a name
# found in the colon-separated TYKKY_PATH or the current directory
__tykky_get_env_path() {
    local candidate="" dir rest
    case "$1" in
        */*) candidate="${1%/}" ;;
        *)
            # Split by hand: zsh does not word split on IFS
            rest="${TYKKY_PATH:-$HOME/.tykky}:"
            while [ -n "$rest" ]; do
                dir="${rest%%:*}"
                rest="${rest#*:}"
                [ -n "$dir" ] && [ -d "$dir/$1" ] || continue
                if [ -z "$candidate" ]; then
                    candidate="${dir%/}/$1"
                else
                    printf 'WARNING: Additional candidate tykky environments found in TYKKY_PATH for %s, only the first one will be considered\n\tfirst candidate: %s\n\tnew candidate: %s\n' \
                        "$1" "$candidate" "$dir/$1" >&2
                fi
            done
            # The current directory wins, like relative paths containing a / do
            if [ -d "$1" ]; then
                if [ -n "$candidate" ] && [ "$(realpath "$candidate")" != "$(realpath "$1")" ]; then
                    printf 'WARNING: Multiple candidate tykky environments for %s, activating the one in the current directory\n\tfrom TYKKY_PATH: %s\n\tfrom current directory: %s\n' \
                        "$1" "$(realpath "$candidate")" "$(realpath "$1")" >&2
                fi
                candidate="$PWD/$1"
            fi
            ;;
    esac

    if [ -f "$candidate/common.sh" ] && [ -d "$candidate/bin" ]; then
        printf '%s\n' "$candidate"
    else
        printf 'ERROR: %s is not a valid tykky environment\n' "$1" >&2
        if [ ! -d "$1" ]; then
            printf '\t%s does not exist or parent folder is not in TYKKY_PATH\n\tCurrent value: TYKKY_PATH=%s\n' "$1" "${TYKKY_PATH:-}" >&2
        fi
        return 1
    fi
}

if [ -n "${BASH_VERSION:-}" ]; then
    __tykky_dir="${BASH_SOURCE[0]}"
    # Make the functions available in subshells too
    export -f tykky __tykky_activate __tykky_deactivate __tykky_get_env_path
elif [ -n "${ZSH_VERSION:-}" ]; then
    __tykky_dir="${(%):-%N}"
fi
__tykky_dir="$(realpath "$(dirname "$__tykky_dir")/../..")"

case ":$PATH:" in
    *":$__tykky_dir/bin:"*) ;;
    *) export PATH="$__tykky_dir/bin:$PATH" ;;
esac

if [ -n "${BASH_VERSION:-}" ] && [ -n "${PS1:-}" ] && [ -f "$__tykky_dir/etc/bash_completion.d/tykky_completion" ]; then
    . "$__tykky_dir/etc/bash_completion.d/tykky_completion"
fi
unset __tykky_dir
