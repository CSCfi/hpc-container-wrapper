**Tool is very much WIP**

- More error handling
- Failing fast on illogical option combinations
- Better descriptions 
- Better syntax
- Argument ordering bad?
- Cleaning up the code
- Custom python version for plain pip container
- Keep wrapcont container names?

## Frontends

- `conda-containerize`
 - Wrap new conda installation or edit existing
- `pip-containerize`
 - Wrap new venv installation or edit existing
 - Defaults to slim python container
- `wrap-container`
 - Generate wrappers for existing container
- `wrap-install`
 - Wrap an installation on disk to a container. 

All tools support `-h/--help` for displaying info
some have subcommands. 

## Examples

- `conda-containerize new --prefix /path/to_install conda_env.yaml`
- `conda-containerize --post-install <(conda install scipy --channel conda-forge) update /path/to_install`
- `pip-containerize new --prefix /path/to_install requirements.txt`
- `wrap-container --wrapper-paths /opt/prog/bin --prefix /path/to_install /path/to/container` 
- `wrap-install --wrapper-paths bin --mask --prefix /path/to/install /program/on/disk`


## Installation

preferrably use system python + pip
and run install.sh with the config as argument

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
