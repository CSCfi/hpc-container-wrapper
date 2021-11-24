- Machine specific settings

parser can select config via env variable

- Enable re-installations
    - Based on if squashfs exist or not!
    - Replace on success
    - Inplace or new
- What kind of files and metadata should we save in the image

commands or scripts

Where do we do the copy when updating?

Yaml list of commands to run

Some sort of install script which set's the default config
+ which python to use and fixes that. 

# config

- Default WRKDIR location
- Default mount points
- Default image 
- Default conda version 
- Default inst paths
- env name
- Default sqfs name
- Blacklisted install locations
- Whitelisted install locations
- config_env
- inst_path vs pwd option
- python user site

All paths in config are relative to current dir

Scripts start at 

force, defaults
prepend

yaml -> resolve path -> caps -> prepend CW
set CACHE_DIR and TMPDIR also to this BUILD TMPDIR

