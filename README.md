# Tykky


Tykky is a set of tools which wrap installations inside 
an Apptainer/Singularity container to improve startup times, 
reduce IO load, and lessen the number of files on large parallel filesystems.



## Intro

This is a tool to create installations using existing containers.
The basic idea is to install software through a container,
convert this into a filesystem image and mount this filesystem image
when running the container. 

The main goal is to reduce the number of files on disk,
and reduce the IO load when installations are started. If you 
are not running on a parallel filesystem with a lot of users and load,
the points might not be that relevant. Only tested and developed
on Lustre so benefits might be different on other parallel filesystems

The tool originally started as a way to package conda 
installations using container, as they cause a significant load on the filesystem.
The idea being that using the tool should be very simple
and as similar as possible to an un-containerized installation (drop in replacement for the majority of cases). 
This means that we try to hide the container as much as possible 
from the end-user. 

It's singularity based, but nothing inherently prohibits usage
of some other runtime (granted singularity is quite hardcoded atm ).
All which is needed is the ability to mount filesystem images and control  over bind mounts

### Design choices    

Containers are used for two main things:
- Automatic mounting and demounting of filesystem-image 
- Per process private  (mount) namespace 

From the point of view of the parallel filesystem, the image
just looks like one single file -> much less load on the parallel filesystem.
(I'm not a Lustre expert so I don't know if it's more the OST,OSS or MDT being saved)
The image could be mounted using other tools, but then we would have to keep 
track of unmounting it all kinds of error handling -> things we get for free using a container. The private namespaces means that we don't have to worry about 
conflicts between multiple users, finding folders where to mount or breaking
software which does not want to be moved. 

Existing containers are used as this provides an easier way 
to interface with the host software environment and a user does not have to
have singularity build access on the HPC machine ( user namespaces might be temporarily disabled on a system due to security  reasons ). 

The tool generates a lot of wrappers with some relatively nasty tricks. This
is so that most things which should work without a container works within the container
and the installation looks like a normal installation to the end-user 

The tool is also explicitly meant to allow intertwining with the host
software environment. For this there are two basic modes of operation:

1. Mount everything from the host
 - All host paths will be mounted, used when it makes sense and compatibility can be assumend
 - Internally there are some additional variables so exclude paths 
 - Note! due to this the default container should always be the same as the host system. 
2. Mount specified defaults
 - defaults set in config


The tool is a single statically compiled Go program. Bash is only used
for what runs inside the container during installation (`templates/`)
and for the generated launchers in the finished installation.

### Limitations

What things break / work differently when compared to a normal installation

- ssh commands will drop you out of the container, there is a fix for this, but then
some pre commands have to be run to start any required ssh services 
- you can't start other containers (singularity can not be nested), Ugly hack is
to ssh to `localhost`, but that makes environment management tricky and requires sshd to be running on the current node. 
- Resolving binary paths will result in paths which do not exist outside the container. 
As the image is mounted on a directory which is not present on the host. Bind mounts
are always applied after the image mount which means an image mount can not mask
a directory on disk, without us dropping the whole preceeding path from the mount point list. 
There is a fix for this as a PR for apptainer (as of 1.2.2022) but we do not rely on this
as the future is unclear if singularityCE or apptainer will become dominant.
The workaround is to mount all directories on the same level as each component
of the image mount path -> possibly very expensive -> not done automatically. 
- A bit untested, but running one container per core when you have 128 of them
can lead to the compute node feeling a bit unwell. 


## Basic program structure

Users call the commands under `bin`, which are symlinks to the Go binary
`libexec/containerize`. The binary picks the frontend from the name it was called by.

1. `main.go` parses the command line (argparse compatible) into a user config. 
2. `config.go` merges it with the default config (`default_config/config.yaml` or `CW_GLOBAL_YAML`):
   `defaults` < user values (`prepends` are prepended) < `appends` < `force`.
    - Values are expanded with environment variables (`$VAR`) when used; unset variables become empty.
    - `pre_install`, `post_install` and `extra_envs` are not expanded.
    - `build_tmpdir_base` is checked to be a valid directory and a `cw-XXXXXX` build directory is created in it.
    - `conda_arch: auto` resolves to `Linux-<uname -m>`.
3. `build.go` runs the steps and cleans up on failure:
    - Fetch the container by downloading, copying or linking (`share_container`). When updating, also copy the squashfs image. 
    - Run the installation script from `templates/` through the container (every scalar setting is visible as `CW_<KEY>`), 
      then compress the installation into a squashfs image. 
        - The installation can be isolated or mount the complete host filesystem. 
        - When modifying an existing installation, the whole installation has to be copied which might take a while
    - Copy the result to the installation directory and save the build inputs and config to `<install_dir>/share`.
4. `wrappers.go` (this is where most tricks live) generates the launchers so the installation can be used like a normal one. The wrappers:
    - Define common variables such as image name, container name  
    - Define runtime bind mounts
    - Unset singularity envs if not actually inside a container (e.g srun called from container -> some SINGULARITY are still active) 
    - Add an extra symlink layer in `_bin` to trick the likes of dask into generating valid executable paths
    - Copy the venv definition when wrapping a python venv
    - Activate conda if a conda env is wrapped
    - Set executable argv0 to enable python virtual envs. 


**NOTE** 

Permissions for installation files 
are determined by the current umask and permissions for the 
target installation folder! Files inside the the squashfs are set to
world readable to allow copying when installations are updated by other
that the original creator. Limit access by setting correct permissions on
on the sqfs image itself. This behavior can be disabled by setting `CW_NO_FIX_PERM`

**BASH MAGIC**

```
/usr/bin/singularity --silent exec -B $DIR/../$SQFS_IMAGE:$INSTALLATION_PATH:image-src=/ $DIR/../$CONTAINER_IMAGE  bash -c "eval \"\$(/CSC_CONTAINER/miniforge/bin/conda shell.bash hook )\"  && conda activate env1 &>/dev/null &&  exec -a $_O_SOURCE $DIR/python $( test $# -eq 0 || printf " %q" "$@" )"
```

- `exec -a` is there to enable creating virtual environments as otherwise the venv symlink -> tykky wrapper -> executable in container chain is broken and python does not consider itself to be a venv. 
- `bash -c` is required when conda is involved as we have to initialize the environment for some commands to work properly. Also partially due to exec being a builtin instead of a binary. 
- `$( test $# -eq 0 || printf " %q" "$@" )` without printf special characters will not be escaped correctly and the command will error out. printf will print an empty string '' if no arguments so we need to be quiet in that case.


## Implemented Frontends

- `conda-containerize`
 - Wrap new conda installation or edit existing
 - requires a conda YML file as input
- `pip-containerize`
 - Wrap new venv installation or edit existing
 - Will by default use currently available python
 - Option to use uv to manage python and venv
 - Option to also use slim container image  (will then not mount full host)
- `wrap-container`
 - Generate wrappers for existing container. Mainly
 so that applications in existing containers can be used "almost" as a normal installation.
 - Full host will not be mounted
- `wrap-install`
 - Wrap an installation on disk to a container.
 - Useful for containerizing existing installations which can not be re-installed
 - Option to mount in exact place, so that external and internal paths are identical. This
 will however require dropping the top parent path mount so only works when no dependencies required. E.g
`wrap-install --mask -w bin /appl/soft/prog --prefix Dir` will not mount `/appl` at all.
Understand the implications of this before using this frontend. For manual workaround
and more explanation see [limitations section](#limitations).


All tools support `-h/--help` for displaying info
some have subcommands. 

## Examples

- `conda-containerize new --prefix /path/to_install conda_env.yaml`
    - Where `conda_env.yaml`
    ```
    channels:
      - conda-forge
    dependencies:
      - numpy
    ```

- `conda-containerize update --post-install post.sh /path/to_install`
    - Where `post.sh`
    ```
    conda install scipy  --channel conda-forge
    pip install pyyaml 
    ```
- `pip-containerize new --prefix /path/to_install req.txt`
   - Where `req.txt`
   ```
   numpy 
   ```

- `wrap-container --wrapper-paths /opt/prog/bin --prefix /path/to_install /path/to/container` 
- `wrap-install --wrapper-paths bin --mask --prefix /path/to/install /program/on/disk`


## Installation

Requires Go and make (only for building). Run make with the desired config.
Available configs are in `configs` folder

```
make CONFIG=<config>
```

This will symlink the config to `default_config` and build `libexec/containerize`.
The binary has no runtime dependencies besides apptainer/singularity, mksquashfs and coreutils.

If you are not satisfied with the config you can simply edit 
the config under `default_config` or supply 
a custom config file path using `CW_GLOBAL_YAML`. 

## Special vars

These can be set before starting the tool

`CW_GLOBAL_YAML`
path to config to use

`CW_ENABLE_CONDARC`
enable user condarc during installation

`CW_DEBUG_KEEP_FILES`
Don't delete build files when failing. 

`CW_FORCE_CONDA_ACTIVATE`
Force conda to be activated even if called through a virtual environment. 

`CW_LOG_LEVEL`
How verbosely to report program actions

- 0 only error
- 1 only warnings
- 2 general (default)
- `>2` debug

## Activating and Deactivating wrapped environments
A `tykky` convenience shell function is provided to mimic the conda activate and
deactivate helpers. To use it, you must load those functions into your shell with:

`source etc/profile.d/tykky`

Then you may activate a tykky installation with

`tykky activate <env_dir>`

If you define the environment variable `TYKKY_PATH`, environments may also be
found by name inside that colon-separated list of paths in `TYKKY_PATH`.

You may deactivate the tykky environment in your shell with:

`tykky deactivate`

Alternatively, you may also manually add `<env_dir>/bin` to your `$PATH`.

## License 

Getting errors like `CondaToSNonInteractiveError: Terms of Service have not been accepted for the following channels. Please accept or remove them before proceeding:`

Newer versions of conda have finer management of channels licenses, which might stop the installatoion if using miniconda (currently tykky versions < 0.4), set `CONDA_PLUGINS_AUTO_ACCEPT_TOS=true` to mitigate this ( https://www.anaconda.com/docs/getting-started/tos-plugin#docker-in-ci%2Fcd-environments ). Understand that this means accepting the channel TOS, make sure you have read and understood them and what they imply for your use case and organization. 

## Misc features ideas

- Keep container name based on src name

## Notes (This is most likely no longer the case for both apptainer and singularity but needs validation)
`SINGULARITY_BIND` handled after `-B`
ordering within both matter! -> nested bind mounts possible.
Note that while loop devices can be mounted on bind mounts,
any extra bind mounts will be applied after extra loop device (image mounts) 
so to mask dirs on disk with an image mount, the path can not be bind mounted.
(exception is a default $HOME mount, which is applied before loop device mounts).
Note that this has been fixed in apptainer and you can now apply image mounts over bind mounts. 


## wrap-install

Technically updating masked disk installations
is not an issue, but let's not do that until there is a specific
request. The tool now drops the full path leading to the target
from the bind list, if more binds are needed a yaml input needs to be constructed. 
