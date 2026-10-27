# Tykky

Tykky wraps software installations inside an Apptainer/Singularity container
to improve startup times, reduce IO load, and cut the number of files on large
parallel filesystems.

You install software through a container, Tykky packs the result into a
single squashfs image, and generated launchers mount that image whenever a
program runs. To the end user it looks like a normal installation: it is a
drop-in replacement in most cases, and the container stays hidden.

Tykky started as a way to package conda environments, which put a heavy load
on parallel filesystems. If your filesystem is not a busy shared parallel
filesystem, the gains may be small. It has only been developed and tested on
Lustre.

## Installation

Building requires Go and make. Pick a default config from `configs/`
(`local`, `lumi`, `roihu-cpu`, `roihu-gpu`):

```
make CONFIG=<config> [PREFIX=<dir>] [MODULEFILES_DIR=<dir>]
```

This builds `$PREFIX/bin/containerize` with `configs/<config>.yaml` as its
default config and copies `etc` and the config to `$PREFIX`. `PREFIX` defaults to `./build`.
It also writes the Lmod modulefile `$MODULEFILES_DIR/tykky/<version>.lua`
(`MODULEFILES_DIR` defaults to `PREFIX`), load it with
`module use $MODULEFILES_DIR && module load tykky`.

At runtime the binary only needs apptainer/singularity, mksquashfs and
coreutils.

To change settings, edit `$PREFIX/configs/<config>.yaml` (it is read at
runtime, so no rebuild is needed) or point `CW_GLOBAL_YAML` at your own config
file.

## Commands

The commands are subcommands of `containerize`, e.g.
`containerize pip new ...`. All support `-h/--help`. Some have subcommands (`new`, `update`).
The legacy commands `conda-containerize`, `pip-containerize`, `wrap-container`
and `wrap-install` still work and call the matching subcommand.

- `conda`: create a new conda installation or update an existing one.
  Takes a conda environment YAML file as input.
- `pip`: create a new venv installation or update an existing one.
  Uses the currently available python by default. Can use uv to manage python
  and the venv, and can use a slim container image (the full host is then not
  mounted).
- `wrap-container`: generate launchers for an existing container, so its
  applications can be used almost like a normal installation. The host
  filesystem is not mounted.
- `wrap-install`: wrap an existing installation on disk into a container.
  Useful for installations that cannot be reinstalled. `--mask` mounts the
  image at the original path so paths inside and outside match, but this drops
  the top-level parent directory from the mounts, so it only works for software
  without external dependencies. For example
  `containerize wrap-install --mask -w bin /appl/soft/prog --prefix Dir` does not mount
  `/appl` at all. Read the [limitations](#limitations) before using it.

## Examples

Create a conda installation:

```
containerize conda new --prefix /path/to_install conda_env.yaml
```

where `conda_env.yaml` is

```yaml
channels:
  - conda-forge
dependencies:
  - numpy
```

Add packages to it later:

```
containerize conda update --post-install post.sh /path/to_install
```

where `post.sh` is

```
conda install scipy --channel conda-forge
pip install pyyaml
```

Create a venv installation from a requirements file:

```
containerize pip new --prefix /path/to_install req.txt
```

Wrap an existing container or installation:

```
containerize wrap-container --wrapper-paths /opt/prog/bin --prefix /path/to_install /path/to/container
containerize wrap-install --wrapper-paths bin --mask --prefix /path/to/install /program/on/disk
```

## Using an installation

Add `<install_dir>/bin` to your `PATH`, or use the `tykky` shell function,
which mimics `conda activate` and `conda deactivate`:

```
source $PREFIX/etc/profile.d/tykky.sh
tykky activate <install_dir>
tykky deactivate
```

If `TYKKY_PATH` is set to a colon-separated list of directories,
`tykky activate` also finds installations in them by name.

**Permissions:** installation files get their permissions from your umask and
the target directory. Files inside the squashfs image are made world readable
so that other users can update the installation; restrict access by setting
permissions on the `.sqfs` image itself. Set `CW_NO_FIX_PERM` to disable this.

## Environment variables

Set these before running a command.

| Variable | Effect |
|---|---|
| `CW_GLOBAL_YAML` | Path to the config file to use. |
| `CW_ENABLE_CONDARC` | Use the user's condarc during installation. |
| `CW_DEBUG_KEEP_FILES` | Keep build files when the build fails. |
| `CW_FORCE_CONDA_ACTIVATE` | Activate conda even when called through a virtual environment. |
| `CW_NO_CONDA_ACTIVATE` | Never activate conda in the launchers. |
| `CW_BUILD_TMPDIR` | Overrides `build_tmpdir_base` from the config. |
| `CW_NO_FIX_PERM` | Don't make files inside the squashfs image world readable. |
| `CW_EXTRA_BIND_MOUNTS` | Extra bind mounts for the launchers (not used for isolated installations). |
| `CW_LOG_LEVEL` | Verbosity: `0` errors, `1` warnings, `2` general (default), `>2` debug. |

## Troubleshooting

### Conda Terms of Service

An error like `CondaToSNonInteractiveError: Terms of Service have not been
accepted for the following channels` comes from newer conda versions, which
manage channel licenses. It can stop installations that use miniconda (Tykky
versions before 0.4). Set `CONDA_PLUGINS_AUTO_ACCEPT_TOS=true` to work around
it ([Anaconda docs](https://www.anaconda.com/docs/getting-started/tos-plugin#docker-in-ci%2Fcd-environments)).
This accepts the channel terms on your behalf, so read them and make sure they
fit your use case and organization.

## Limitations

What breaks or behaves differently compared to a normal installation:

- `ssh` drops you out of the container. There is a fix, but it needs pre
  commands that start the required ssh services.
- You can't start other containers, because singularity cannot be nested. An
  ugly workaround is to ssh to `localhost`, but that makes environment
  management tricky and needs sshd running on the node.
- Resolved binary paths point to paths that do not exist outside the
  container, because the image is mounted on a directory that is not on the
  host. Bind mounts are applied after the image mount, so an image cannot mask
  a directory on disk unless the whole preceding path is dropped from the
  mounts. An apptainer PR fixes this (as of February 2022), but Tykky does not
  rely on it. The manual workaround is to mount every directory at the same
  level as each component of the image mount path, which can be very
  expensive, so it is not done automatically.
- Running one container per core on a 128-core node is largely untested and
  can strain the compute node.

## How it works

### Design

Containers do two jobs:

- Mount and unmount the filesystem image automatically.
- Give each process a private mount namespace.

To the parallel filesystem the image is a single file, which means far less
load. The image could be mounted with other tools, but then Tykky would have
to handle unmounting and error cases itself; the container provides that for
free. Private namespaces mean there are no conflicts between users, no need to
find mount points, and no breakage of software that refuses to be moved.

Tykky uses existing containers rather than building them, because that makes
it easier to interface with the host software environment, and users don't
need singularity build access on the HPC system (user namespaces may be
disabled for security reasons).

Tykky is meant to mix with the host software environment. There are two
modes:

1. Mount everything from the host. Used when compatibility can be assumed.
   Some paths can be excluded through internal variables. Because of this the
   default container should always match the host OS.
2. Mount only the defaults set in the config.

Tykky is a single statically compiled Go program and is currently tied to
singularity, although any runtime that can mount filesystem images and control
bind mounts would work. Bash is only used for the script it runs inside the
container during installation (conda/venv activation and the user's pre/post
install commands share one shell) and for the generated launchers.

### Program structure

`bin/containerize` is a single Go binary that picks the frontend from its
first argument.

1. `src/main.go` parses the command line (argparse compatible) into a user config.
2. `src/config.go` merges it with the default config (`configs/<config>.yaml`
   chosen at build time, or `CW_GLOBAL_YAML`), in increasing priority:
   `defaults` < user values (`prepends` are prepended) < `appends` < `force`.
    - Values are expanded with environment variables (`$VAR`) when used; unset variables become empty.
    - `pre_install`, `post_install` and `extra_envs` are not expanded.
    - `build_tmpdir_base` must be a valid directory; a `cw-XXXXXX` build directory is created in it.
    - `conda_arch: auto` resolves to `Linux-<uname -m>`.
3. `src/build.go` runs the build steps and cleans up on failure:
    - Fetch the container by downloading, copying or linking it (`share_container`). When updating, also copy the squashfs image.
    - Run the installation script generated by `src/install.go` in the container. Every scalar setting is visible as `CW_<KEY>`.
      Miniforge and uv are downloaded on the host. Output of the heavy steps goes to `build.log` in the build directory.
      The installation can be isolated or mount the whole host filesystem.
      Updating an installation copies all of it, which can take a while.
    - Compress the installation into a squashfs image.
    - Copy the result to the installation directory and save the build inputs and config to `<install_dir>/share`.
4. `src/wrappers.go` generates the launchers, and is where most of the tricks live. Each wrapper in `bin` is a stub that runs
   `bin/_containerize_exec <command> <args>`, which holds the shared logic. `_containerize_exec`:
    - Define common variables such as the image and container names.
    - Define runtime bind mounts.
    - Unset singularity variables when not actually inside a container (e.g. `srun` called from a container leaves some `SINGULARITY*` variables set).
    - Add an extra symlink layer in `_bin` so tools like dask generate valid executable paths.
    - Copy the venv definition when wrapping a python venv.
    - Activate conda when wrapping a conda environment.
    - Set the executable's `argv0` so python virtual environments work.

### Launcher example

```
/usr/bin/singularity --silent exec -B $DIR/../$SQFS_IMAGE:$INSTALLATION_PATH:image-src=/ $DIR/../$CONTAINER_IMAGE  bash -c "eval \"\$(/CSC_CONTAINER/miniforge/bin/conda shell.bash hook )\"  && conda activate env1 &>/dev/null &&  exec -a $_O_SOURCE $DIR/$_cmd $( test $# -eq 0 || printf " %q" "$@" )"
```

- `exec -a` makes virtual environments work. Without it the chain
  venv symlink → Tykky launcher → executable in container breaks, and python
  does not see itself as a venv.
- `bash -c` is needed with conda, because the environment must be initialized
  for some commands to work, and because `exec` is a shell builtin rather than
  a binary.
- `printf " %q"` escapes special characters in the arguments; without it the
  command fails. With no arguments `printf` would print an empty `''`, so the
  `test $# -eq 0` guard skips it.
