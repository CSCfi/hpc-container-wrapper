#!/bin/bash
SINGULARITY_BIND=""
set -e
set -u 

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source $SCRIPT_DIR/common_functions.sh
source $CW_BUILD_TMPDIR/_vars.sh


cd $CW_BUILD_TMPDIR
mkdir _deploy/bin
touch _deploy/common.sh
echo "#!/bin/bash" > _deploy/common.sh


if [[ "$CW_MODE" == "wrapcont" ]];then
    _CONTAINER_EXEC="/usr/bin/singularity --silent exec  _deploy/$CW_CONTAINER_IMAGE"
    _RUN_CMD="/usr/bin/singularity --silent exec \$DIR/../\$CONTAINER_IMAGE"
    _SHELL_CMD="/usr/bin/singularity --silent shell \$DIR/../\$CONTAINER_IMAGE"
else
    _CONTAINER_EXEC="/usr/bin/singularity --silent exec -B _deploy/$CW_SQFS_IMAGE:$CW_INSTALLATION_PATH:image-src=/ _deploy/$CW_CONTAINER_IMAGE"
    echo "SQFS_IMAGE=$CW_SQFS_IMAGE" >> _deploy/common.sh
    _RUN_CMD="/usr/bin/singularity --silent exec  \$DIR/../\$CONTAINER_IMAGE"
    _SHELL_CMD="/usr/bin/singularity --silent shell \$DIR/../\$CONTAINER_IMAGE"
fi

# Need to unset the path, otherwise we might be stuck in a nasty loop
# and exhaust the system 
_REAL_PATH_CMD='
export OLD_PATH=$PATH                                      
export PATH="/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/bin"
SOURCE="${BASH_SOURCE[0]}"                                                                                                                                       
_O_SOURCE=$SOURCE                                                                                                                                                
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink                                                                               
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"                                                                                               
  SOURCE="$(readlink "$SOURCE")"                                                                                                                                 
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done                                                                                                                                                             
DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"                                                                                                 

'
_PRE_COMMAND="source \$DIR/../common.sh"
echo "_C_DIR=\"\$( cd \"\$( dirname \"\${BASH_SOURCE[0]}\" )\" >/dev/null 2>&1 && pwd )\"
CONTAINER_IMAGE=$CW_CONTAINER_IMAGE
INSTALLATION_PATH=$CW_INSTALLATION_PATH
">> _deploy/common.sh
if [[ ${CW_WRAPPER_LD_LIBRARY_PATHS+defined} ]]; then
    echo "export SINGULARITYENV_LD_LIBRARY_PATH=\"\$SINGULARITYENV_LD_LIBRARY_PATH:$(echo "${CW_WRAPPER_LD_LIBRARY_PATHS[@]}" | tr ' ' ':' )\"">> _deploy/common.sh
fi

if [[ "$CW_ISOLATE" == "yes" ]]; then
    echo "_DIRS=(${CW_MOUNT_POINTS[@]} \$_C_DIR )" >> _deploy/common.sh
echo "
SINGULARITYENV_DEFAULT_PATH=\"$($_CONTAINER_EXEC sh -c 'echo $PATH')\"
SINGULARITYENV_DEFAULT_LD_LIBRARY_PATH=\"$($_CONTAINER_EXEC sh -c 'echo $LD_LIBRARY_PATH')\"
export SINGULARITYENV_PATH=\"\$SINGULARITYENV_PATH:\$SINGULARITYENV_DEFAULT_PATH\"
export SINGULARITYENV_LD_LIBRARY_PATH=\"\$SINGULARITYENV_LD_LIBRARY_PATH:\$SINGULARITYENV_DEFAULT_LD_LIBRARY_PATH\"
" >> _deploy/common.sh

else
    echo "_DIRS=(\$(/usr/bin/ls -1 / | /usr/bin/awk '!/dev/' | /usr/bin/sed 's/^/\//g' ))" >> _deploy/common.sh
    echo "export SINGULARITYENV_PATH=\"\$OLD_PATH\"
export SINGULARITYENV_LD_LIBRARY_PATH=\"\$SINGULARITYENV_LD_LIBRARY_PATH:\$LD_LIBRARY_PATH\"" >> _deploy/common.sh

if [[ "${CW_EXCLUDED_MOUNT_POINTS+defined}" ]];then
    echo "
        _excludes=( ${CW_EXCLUDED_MOUNT_POINTS[@]}  )
        for mp in \"\${_excludes}\";do
            _DIRS=( \"\${_DIRS[@]/\$mp}\")
        done
    ">> _deploy/common.sh

fi
fi

echo "
if  grep -q 'singularity/mnt/session\|apptainer/mnt/session' /proc/self/mountinfo ;then
    export _CW_IN_CONTAINER=Yes
    if [[ \"$CW_ISOLATE\" == \"yes\" && ! \"\$( stat -c '%i' \$SINGULARITY_CONTAINER)\" == \"\$( stat -c '%i' \$_C_DIR/\$CONTAINER_IMAGE)\" ]]; then
        echo \"[ ERROR ] wrapper called from another container. Is \$SINGULARITY_CONTAINER, should be \$_C_DIR/\$CONTAINER_IMAGE \"
        exit 1 
    fi
    if [[ ! -e $CW_INSTALLATION_PATH ]]; then
        echo \"[ ERROR ] Installation for \$_C_DIR/ is not mounted. Wrapper called from another container?\" 
        exit 1
    fi
    
else
    unset _CW_IN_CONTAINER
    export _CW_IS_ISOLATED=$CW_ISOLATE
fi

if [[ ! \${_CW_IN_CONTAINER+defined} && \${SINGULARITY_NAME+defined} ]] ;then
    unset SINGULARITY_NAME
    unset SINGULARITY_COMMAND
    unset SINGULARITY_NAME
    unset SINGULARITY_ENVIRONMENT
    unset SINGULARITY_BIND
    unset SINGULARITY_CONTAINER

    unset APPTAINER_NAME
    unset APPTAINER_COMMAND
    unset APPTAINER_NAME
    unset APPTAINER_ENVIRONMENT
    unset APPTAINER_BIND
    unset APPTAINER_CONTAINER
fi
" >> _deploy/common.sh
echo "
for d in \"\${_DIRS[@]}\"; do
    if [[ -z \"\$SINGULARITY_BIND\" ]];then
`        `test -d \$d && export SINGULARITY_BIND=\"\$d\"
    else
        test -d \$d && export SINGULARITY_BIND=\"\$SINGULARITY_BIND,\$d\"
    fi
done
if [[ \"\${TMPDIR+defined}\" ]];then
    SINGULARITY_BIND=\"\$SINGULARITY_BIND,\$TMPDIR,\$TMPDIR:/tmp\"
fi
SINGULARITY_BIND=\"\$SINGULARITY_BIND,\$( /usr/bin/readlink -f \$_C_DIR/_bin):\$( /usr/bin/readlink -f \$_C_DIR/bin)\"" >> _deploy/common.sh
# The above readlink is only needed as a workaround for Lumi
# where some folders are symlinked to lustre mount points
if [[ "$CW_MODE" == "wrapcont" ]];then
    echo "export SINGULARITY_BIND" >> _deploy/common.sh
else
    echo "export SINGULARITY_BIND=\$SINGULARITY_BIND,\$DIR/../\$SQFS_IMAGE:\$INSTALLATION_PATH:image-src=/" >> _deploy/common.sh
fi
echo "if [[ \${CW_EXTRA_BIND_MOUNTS+defined} && \"$CW_ISOLATE\" == \"no\" ]]; then
    export SINGULARITY_BIND=\$SINGULARITY_BIND,\$(echo \$CW_EXTRA_BIND_MOUNTS |  sed \"s@\$_C_DIR/\$SQFS_IMAGE:\$INSTALLATION_PATH:image-src=/@@g\")
fi" >> _deploy/common.sh


_SING_LIB_PATHS=()
_GENERATED_WRAPPERS=""


# Let's trick some software
# which hardcode program paths for some generation
# Will not work if symlinks are also resolved.
mkdir _deploy/_bin

print_info "Creating wrappers" 1
# Just in case the container does not contain bash
if [[ -z $($_CONTAINER_EXEC bash --version 2>/dev/null) ]] && [[ "$CW_ISOLATE" == "yes" ]] ;then
    print_info "Using sh inside the container as bash was not found" 1
   _default_cws="sh -c \""
else
   _default_cws="bash -c \""
fi
for wrapper_path in "${CW_WRAPPER_PATHS[@]}";do
    _cws="$_default_cws"
    _cwe="\$( test \$# -eq 0 || printf \" %q\" \"\$@\" )\""
    print_info "Generating wrappers for $wrapper_path" 2
    if $_CONTAINER_EXEC test -f $wrapper_path ; then
        targets=( $(basename $wrapper_path ))
        wrapper_path=$(dirname $wrapper_path)
    else
     if [[ "$CW_WRAP_ALL" == "yes" ]];then
         print_info "Wrapping all files" 3
         targets=($($_CONTAINER_EXEC ls -F $wrapper_path 2>/dev/null | grep -v "/"  | sed 's/.$//g' ))
     else
         print_info "Only wrapping executables" 3
         targets=($($_CONTAINER_EXEC ls -F $wrapper_path 2>/dev/null | grep "\*\|@" | sed 's/.$//g'))
     fi
     if [[ "$CW_ADD_LD" == "yes" ]]; then
         # Nasty hack
         # empty result -> no array defined

         lib_dirs=($($_CONTAINER_EXEC ls $wrapper_path/.. | grep "lib[64]*$" || true ))
         if [[ ${lib_dirs+defined} ]];then
             for d in "${lib_dirs[@]}"; do
                 _SING_LIB_PATHS+=("$(dirname $wrapper_path)/$d")
             done
         fi
     fi
     if [[ ! ${targets+defined} ]];then
         # No method to remove wrapper paths when updating
         # So don't fail here
         print_warn "Path $wrapper_path does not exist in container or is empty \n\tif only wrapping executables, did you forget +x?"
         continue
     fi
     # To activate conda environment
     # printf is used to properly parse the arguments
     # so that quote are maintainted
     # e.g python -c "print('Hello')" works
     # The test is there as printf returns '' if $@ is empty
     # passing '' is not wanted behavior 
     print_info "Checking if conda installation" 3
     unset CONDA_CMD
     if $_CONTAINER_EXEC test -f $wrapper_path/../../../bin/conda ; then 
         export CONDA_CMD=1
         print_info "Inserting conda activation into wrappers" 3
         env_name=$(basename $(realpath -m $wrapper_path/../ ))
         conda_path=$(realpath -m $wrapper_path/../../../bin/conda)
         _cws="bash -c \"eval \\\"\\\$($conda_path shell.bash hook )\\\"  && conda activate $env_name &>/dev/null && "
     else
         print_info "Does not look like a conda installation" 3 
     fi

    fi
    

    for target in "${targets[@]}"; do
        print_info "Creating wrapper for $target" 3
        echo -e "$_GENERATED_WRAPPERS" | grep "^$target$" &>/dev/null &&  print_warn "Multiple binaries with the same name" || true
    _GENERATED_WRAPPERS="$_GENERATED_WRAPPERS\n$target"
        echo "#!/bin/bash" > _deploy/bin/$target
        echo "$_REAL_PATH_CMD" >> _deploy/bin/$target
        echo "$_PRE_COMMAND" >> _deploy/bin/$target
        ln -s $wrapper_path/$target _deploy/_bin/$target
        echo "
if [[ \${_CW_IN_CONTAINER+defined} ]];then
    export PATH=\"\$OLD_PATH\"
    exec -a \$_O_SOURCE \$DIR/../_bin/$target \"\$@\"
else" >> _deploy/bin/$target
        if [[ ${CONDA_CMD+defined} ]];then
        echo "
        if [[ ( -e \$(/usr/bin/dirname \$_O_SOURCE )/../pyvenv.cfg && ! \${CW_FORCE_CONDA_ACTIVATE+defined} ) || \${CW_NO_CONDA_ACTIVATE+defined} ]];then
        export PATH=\"\$OLD_PATH\"
        $_RUN_CMD $_default_cws exec -a \$_O_SOURCE \$DIR/$target $_cwe  
    else
        export PATH=\"\$OLD_PATH\"
        $_RUN_CMD  $_cws exec -a \$_O_SOURCE \$DIR/$target $_cwe  
    fi
fi
        " >>  _deploy/bin/$target
        else 
        echo "
    export PATH=\"\$OLD_PATH\"
    $_RUN_CMD  $_cws exec -a \$_O_SOURCE \$DIR/$target $_cwe  
fi" >> _deploy/bin/$target
        fi
        chmod +x _deploy/bin/$target
        if [[ "$target" == "python"  ]];then
            print_info "Found python, checking if venv" 2
            if [[ ! -z "$($_CONTAINER_EXEC ls $wrapper_path/../pyvenv.cfg 2>/dev/null )" ]]; then
                print_info "Target is a venv" 2
                $_CONTAINER_EXEC cat $wrapper_path/../pyvenv.cfg > _deploy/pyvenv.cfg
                _pyd=$($_CONTAINER_EXEC ls $wrapper_path/../lib)
                mkdir -p _deploy/lib/$_pyd/
                (cd _deploy/lib/$_pyd && ln -s $wrapper_path/../lib/$_pyd/site-packages site-packages )
                (cd _deploy && ln -s lib lib64 )
            fi
        fi
    done
done

target=_debug_shell
echo "#!/bin/bash" > _deploy/bin/$target
echo "$_REAL_PATH_CMD" >> _deploy/bin/$target
echo "$_PRE_COMMAND" >> _deploy/bin/$target
echo "

if [[ -z \"\$SINGULARITY_NAME\" ]];then
    $_SHELL_CMD  \"\$@\" 
fi" >> _deploy/bin/$target
chmod +x _deploy/bin/$target

target=_debug_exec
echo "#!/bin/bash" > _deploy/bin/$target
echo "$_REAL_PATH_CMD" >> _deploy/bin/$target
echo "$_PRE_COMMAND" >> _deploy/bin/$target
echo "
if [[ -z \"\$SINGULARITY_NAME\" ]];then
    $_RUN_CMD \"\$@\" 
fi" >> _deploy/bin/$target
chmod +x _deploy/bin/$target


if [[ "$CW_ADD_LD" == "yes" && ${_SING_LIB_PATHS+defined} ]]; then
    echo "SINGULARITYENV_LD_LIBRARY_PATH=\"$(echo "${_SING_LIB_PATHS[@]}" | /usr/bin/tr ' ' ':' ):\$SINGULARITYENV_LD_LIBRARY_PATH\"" >> _deploy/common.sh
fi
set +H
printf -- '%s\n' "_tmp_arr=(\$(echo \$SINGULARITYENV_PATH | /usr/bin/tr ':' '\n' ))" >> _deploy/common.sh
printf -- '%s\n' "SINGULARITYENV_PATH=\$(echo \"\${_tmp_arr[@]}\" | /usr/bin/tr ' ' ':')" >> _deploy/common.sh
printf -- '%s\n' "_tmp_arr=(\$(echo \$SINGULARITYENV_LD_LIBRARY_PATH | /usr/bin/tr ':' '\n' ))" >> _deploy/common.sh
printf -- '%s\n' "SINGULARITYENV_LD_LIBRARY_PATH=\$(echo \"\${_tmp_arr[@]}\" | /usr/bin/tr ' ' ':')" >> _deploy/common.sh
if [[ -f _extra_envs.sh ]];then
    cat _extra_envs.sh >> _deploy/common.sh 
fi
if [[ -f _extra_user_envs.sh ]];then
    cat _extra_user_envs.sh >> _deploy/common.sh 
fi
chmod o+r _deploy
chmod o+x _deploy
