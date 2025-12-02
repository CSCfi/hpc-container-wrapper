#!/bin/bash
set -e

cd  "$CW_BUILD_TMPDIR"
echo "export env_root=$CW_INSTALLATION_PATH/$CW_ENV_NAME/" >> _extra_envs.sh
echo "export env_root=$CW_INSTALLATION_PATH/$CW_ENV_NAME/" >> _vars.sh
export env_root="$CW_INSTALLATION_PATH/$CW_ENV_NAME/"

cd "$CW_INSTALLATION_PATH"
source "$CW_INSTALLATION_PATH/_pre_install.sh"

_NC=""
if [[ "$CW_PIPCACHE" != "yes" ]]; then
    _NC="-n"
fi

if [[ "$CW_USE_UV" == "yes" ]]; then
    if [[ ! -f "$CW_INSTALLATION_PATH/uv/bin/uv" ]]; then
        print_info "Installing uv package manager" 1
        curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="$CW_INSTALLATION_PATH/uv/bin/" UV_PRINT_QUIET=1 sh
    fi
    export PATH="$CW_INSTALLATION_PATH/uv/bin/:$PATH"
    export UV_PYTHON_INSTALL_DIR="$CW_INSTALLATION_PATH/uv/python"
fi

if [[ ! -e "$env_root/bin/activate" ]]; then
    if [[ ${CW_ENABLE_SITE_PACKAGES+defined} ]];then
        print_info "Enabling system and user site packages" 1
        _SP="--system-site-packages"
    else
        print_info "Not enabling system and user site packages" 1
        _SP=""
    fi
    print_info "Creating virtual environment" 1
    if [[ "$CW_USE_UV" == "yes" ]]; then
        uv venv -p "$CW_PYVER" $_SP --managed-python $_NC --no-config  --link-mode=copy "$env_root"
    else
        python3 -m venv $_SP "$CW_ENV_NAME"
    fi
fi

source "$env_root/bin/activate"

if [[ ${CW_REQUIREMENTS_FILE+defined}  ]];then
    print_info "Installing requirements file" 1
    if [[ "$CW_USE_UV" == "yes" ]]; then
        uv pip install --link-mode=copy --compile-bytecode $_NC -r "$( basename "$CW_REQUIREMENTS_FILE")" > "$CW_BUILD_TMPDIR/_pip.log" &
    else
        pip install --disable-pip-version-check $_NC -r "$( basename "$CW_REQUIREMENTS_FILE")" > "$CW_BUILD_TMPDIR/_pip.log" &
    fi
    bg_pid=$!
    wait $bg_pid
    follow_log $bg_pid "$CW_BUILD_TMPDIR/_pip.log" 20
fi
cd "$CW_WORKDIR"
print_info "Running user supplied commands" 1
source "$CW_INSTALLATION_PATH/_post_install.sh"

echo "CW_WRAPPER_PATHS+=( \"$CW_INSTALLATION_PATH/$CW_ENV_NAME/bin/\" )" >>  "$CW_BUILD_TMPDIR"/_vars.sh
