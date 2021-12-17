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

- `cont-conda`
 - Wrap new conda installation or edit existing
- `pycont`
 - Wrap new venv installation or edit existing
 - Defaults to slim python container
- `wrapcont`
 - Generate wrappers for existing container
- `instcont`
 - Wrap an installation on disk on to a container. 

All tools support `-h/--help` for displaying info
some have subcommands. 

## Examples

- `cont-conda new --prefix /path/to_install conda_env.yaml`
- `cont-conda --post-install <(conda install scipy --channel conda-forge) update /path/to_install`
- `pycont new --prefix /path/to_install requirements.txt`
- `wrapcont --wrapper-paths /opt/prog/bin --prefix /path/to_install /path/to/container` 
- `instcont --wrapper-paths bin --mask --prefix /path/to/install /program/on/disk`


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

## instcont

Technically updating masked disk installations
is not an issue, but let's not do that until there is a specific
request. The tool now drops the full path leading to the target
from the bind list, if more binds are needed a yaml input needs to be constructed. 
