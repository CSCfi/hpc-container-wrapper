#!/bin/bash
set -e

cd  "$CW_BUILD_TMPDIR"
echo "export env_root=$CW_INSTALLATION_PATH/$CW_ENV_NAME/" >> _extra_envs.sh
echo "export env_root=$CW_INSTALLATION_PATH/$CW_ENV_NAME/" >> _vars.sh
export env_root="$CW_INSTALLATION_PATH/$CW_ENV_NAME/"

cd "$CW_INSTALLATION_PATH"

if [[ ! -f "$CW_INSTALLATION_PATH/uv/bin/uv" ]]; then
    curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="$CW_INSTALLATION_PATH/uv/bin/" UV_PRINT_QUIET=1 sh
fi
export PATH="$CW_INSTALLATION_PATH/uv/bin/:$PATH"

cd "$CW_WORKDIR"
source "$CW_INSTALLATION_PATH/_pre_install.sh"

cd "$CW_INSTALLATION_PATH"

print_info "Installing requirements file" 1
export UV_PYTHON_INSTALL_DIR="$CW_INSTALLATION_PATH/uv/python"

NOCACHE_FLAG=""
if [[ "$CW_PIPCACHE" != "yes" ]]; then
    NOCACHE_FLAG="-n"
fi

if [[ ! -e "$env_root/bin/activate" ]]; then
    uv venv -p "$CW_PYVER" --managed-python $NOCACHE_FLAG --no-config  --link-mode=copy "$env_root"
fi
source "$env_root/bin/activate"

if [[ ${CW_REQUIREMENTS_FILE+defined}  ]];then
    uv pip install --link-mode=copy --compile-bytecode $NOCACHE_FLAG -r "$( basename "$CW_REQUIREMENTS_FILE")" > "$CW_BUILD_TMPDIR/_uv.log" &
    bg_pid=$!
    wait $bg_pid
    follow_log $bg_pid "$CW_BUILD_TMPDIR/_uv.log" 20
fi
cd "$CW_WORKDIR"
print_info "Running user supplied commands" 1
source "$CW_INSTALLATION_PATH/_post_install.sh"

echo "CW_WRAPPER_PATHS+=( \"$CW_INSTALLATION_PATH/$CW_ENV_NAME/bin/\" )" >>  "$CW_BUILD_TMPDIR"/_vars.sh
