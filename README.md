
SINGULARITY_BIND is after -B
ordering within both matter!


## Frontends

- Fresh conda
- conda update
- Fresh pip
- pip update
- Create wrappers for containers
- Wrap on disk
-   

- Need to be robust to people changing the python environment!
    - Tool install scripts needs to 



CW_DEBUG_KEEP_FILES

`CW_LOG_LEVEL`
0 only error
1 only warnings
2 general
3 debug

## TODO
- option to only allow relative paths.


## Convoluted path modifications in py scripts
The idea is that everything works even if a completely different python
environment is active, we also avoid having any extra envs set while parsing
the conf to allow for very "creative" usages of the tool

## instcont

Technically updating masked disk installations
is not an issue, but let's not do that until there is a specific
request. 
