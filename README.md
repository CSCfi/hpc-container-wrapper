


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


Current version of the tools is written using bash  + python. 
At some point it could be worthwile to rewrite the whole thing
in some language which can be statically compiled for maximum robustness
e.g GO/rust/C++ or whatever. 

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

Starting from command invocation
Users will use commands under `bin`

1. `bin` files are symlinks to `frontends/containerize` 
2. `containerize` is the main script which runs all the steps and is responsible for cleanup  
3. Based on the used symlink different a corresponding python script is going to be called from `frontends`
4. This frontend parses the user input and sets a lot of tool specific defaults. 
    - The python interpreter used is hardcoded during the tools installation.
    - A user config is created
5. The user config and the default config are both passed to `construct.py` 
    - The default config has been defined during installation  
    - Some values are overridable other are set.
    - The construct will produce a `_vars.sh` file which will be sources by subsequent steps
    - Current handling of environment variables in config is not standardized. `pre_install`,`post_install` and `extra_envs` will not be expanded in any way. `build_tmpdir_base` will be expanded and checked to be a valid directory during config construction. The rest will be expanded using `os.path.expandvars` note that this will leave unset variables as is.
    - All non-special variables from the yaml will be uppercased, prefixed with `CW_` and dumped to the `_vars.sh` arrays are turned to bash arrays.  
6. `containersize` makes sure that the installation dir exist.
7. **pre.sh** Fetch container either by downloading or copying from disk. When modifying installations, will also copy the squashfs image
8. **create_inst** Run installation script through the container based on some template in `templates`, after which the installation is compressed into a squashfs image. 
    - The installation can be isolated or mount the complete host filesystem. 
    - When modifying an existing installation, the whole installation has to be copied wich might take a while
9. **generate_wrappers** (This is where most tricks live) Generate wrappers for the installation so that they can be used as normal installations. The wrappers:
    - Defines common variables such as image name, container name  
    - Defines runtime bind mounts
    - Unset singularity envs if not actually inside a container (e.g srun called from container -> some SINGULARITY_ are still active) 
    - Extra symlink layer in `_bin` to tricks the likes of dask to generate valid executable paths
    - Copy venv definition when wrapping python venv
    - Activates conda if a conda env is wrapped 
10. **post.sh**
    - Copy build files to final installatio file
    - Save used build files to <install_dir>/share

## Implemented Frontends

- `conda-containerize`
 - Wrap new conda installation or edit existing
 - requires a conda YML file as input
- `pip-containerize`
 - Wrap new venv installation or edit existing
 - Will by default use currently available python
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

Preferably use system python + pip
and run install.sh with the desired config as argument.
Available configs are in `configs` folder

```
bash install.sh <config>
```

This will copy the config to `default_config`,
install pyyaml locally in the repository and
hardcode the used python interpreter. This
is so that the tool can be used to construct environments
which use a completely different python. 

## Special vars

These can be set before starting the tool

`CW_DEBUG_KEEP_FILES`
Don't delete build files when failing. 

`CW_LOG_LEVEL`
How verbosely to report program actions

- 0 only error
- 1 only warnings
- 2 general (default)
- `>2` debug


## Misc features ideas

- Keep container name based on src name

## Notes
`SINGULARITY_BIND` handled after `-B`
ordering within both matter! -> nested bind mounts possible.
Note that while loop devices can be mounted on bind mounts,
any extra bind mounts will be applied after extra loop device (image mounts) 
so to mask dirs on disk with an image mount, the path can not be bind mounted.
(exception is the default $HOME mount, which is applied before loop device mounts)


## Convoluted path modifications in py scripts

The idea is that everything works even if a completely different python
environment is active, we also avoid having any extra envs set while parsing
the conf to allow for very "creative" usages of the tool

## wrap-install

Technically updating masked disk installations
is not an issue, but let's not do that until there is a specific
request. The tool now drops the full path leading to the target
from the bind list, if more binds are needed a yaml input needs to be constructed. 
