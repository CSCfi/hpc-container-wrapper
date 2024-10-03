# Tykky shell functions to activate/deactivate environments

__tykky_dir=""
if [ -n "${BASH_SOURCE:-}" ]; then
    __tykky_dir="$(dirname "${BASH_SOURCE[0]}")"
elif [ -n "${ZSH_VERSION:-}" ]; then
    __tykky_dir="$(dirname "${(%):-%N}")"
elif [ -n "${KSH_VERSION:-}" ]; then
    __tykky_dir="$(dirname "${.sh.file}")"
else
    # Generic POSIX shell case or dash
    __tykky_dir="$(dirname "$0")"
fi

__tykky_dir="$(realpath $(dirname $(dirname "$__tykky_dir")))"

# Add the tykky tools to PATH if not present
if [ "${PATH#*$__tykky_dir/bin:}" = "$PATH" ]; then
    export PATH="$__tykky_dir/bin:$PATH"
fi

# Make available tykky functions for this shell and subshells
for __function in $__tykky_dir/share/sh_functions/*; do
    source $__function
    if [ -z "$KSH_VERSION" ]; then
        export -f $(basename $__function)
    fi
done
unset __function

# KSH does not support exporting functions
if [ "${FPATH#*$__tykky_dir/share/sh_functions:}" = "$FPATH" ]; then
    export FPATH="$__tykky_dir/share/sh_functions:$FPATH" 
fi

# Enable BASH autocompletion
if [ -n "${BASH_VERSIONi:-}" ] && [ -n "${PS1:-}" ]; then
    __tykky_bash_completion_file="$_tykky_dir/etc/bash_completion.d/tykky_completion"
    [ -f "$__tykky_bash_completion_file" ] && . "$__tykky_bash_completion_file"
    unset __tykky_bash_completion_file
fi
unset __tykky_dir
