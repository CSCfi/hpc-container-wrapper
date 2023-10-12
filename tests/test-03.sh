#!/bin/bash -eu
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source $SCRIPT_DIR/setup.sh
# Test are run in current directory

rm -fr T_TEST_DIR
mkdir T_TEST_DIR
cd T_TEST_DIR
mkdir Gdal
mkdir S
echo 'channels:
  - conda-forge
  - bioconda
dependencies:
  - python>=3.10
  - snakemake
' > env2.yml
echo '
channels:
  - conda-forge
dependencies:
  - python>=3.10
  - gdal
' > env.yml
echo 'rule all:
	input: "out.txt"
rule ghelp:
    output: "out.txt"
    shell:
        """
        gdaladdo --help-general | grep -q "Generic GDAL utility command options" > out.txt
        """
' > Snakefile

cat ../../default_config/config.yaml | sed  "s@singularity_executable_path.*@singularity_executable_path: 'ThisIsNotACommand'@g" > my_config.yaml 
export CW_GLOBAL_YAML=$( readlink -f my_config.yaml)
t_run "conda-containerize new --mamba env2.yml --prefix S | grep 'ThisIsNotACommand does not exists'" "Exit if configured singularity command does not exist" 
cat ../../default_config/config.yaml | sed  "s@singularity_executable_path.*@singularity_executable_path: 'my_sing_command'@g" > my_config.yaml 
echo "#!/bin/bash" > my_sing_command
echo "exit 0" >> my_sing_command
chmod +x my_sing_command
export PATH=$PATH:$PWD
t_run "conda-containerize new --mamba env2.yml --prefix S | grep 'does not seem to be a valid apptainer/singularity executable'" "Exit if configured singularity command seems broken" 
# Run the rest of the test with singularity found from path.
cat ../../default_config/config.yaml | sed  "s@singularity_executable_path.*@singularity_executable_path: 'singularity'@g" > my_config.yaml 


t_run "conda-containerize new --mamba env2.yml --prefix S" "mamba works" 
t_run "conda-containerize new --mamba env.yml --prefix Gdal" "gdal installed"
export OPATH=$PATH
export PATH=$PWD/Gdal/bin:$PATH
export PATH=$PWD/S/bin:$PATH
export CW_EXTRA_BIND_MOUNTS=$PWD/Gdal/img.sqfs:$(Gdal/bin/_debug_exec bash -c "echo \$install_root"):image-src=/
t_run "gdaladdo --help-general | grep -q 'Generic GDAL utility command options'" "Filter out own bind mount"
t_run "snakemake -j1" "Composition works"
t_run "Gdal/bin/_debug_exec Gdal/_bin/gdaladdo --help-general | grep -q 'Generic GDAL utility command options'" "_bin directory works"
rm out.txt
export CW_EXTRA_BIND_MOUNTS=$CW_EXTRA_BIND_MOUNTS:$PWD/S/img.sqfs:$(S/bin/_debug_exec bash -c "echo \$install_root"):image-src=/
t_run 'Gdal/bin/_debug_exec snakemake --help |  grep "usage: snakemake" -q' "Composition works other way around"
t_run 'Gdal/bin/python -c "import sys;import os;sys.exit(\"CONDA_PREFIX\" not in os.environ)"' "Conda is active"
export CW_NO_CONDA_ACTIVATE=1
t_run 'Gdal/bin/python -c "import sys;import os;sys.exit(\"CONDA_PREFIX\" in os.environ)"' "Conda is not active"
unset CW_NO_CONDA_ACTIVATE
Gdal/bin/python -m venv Py
t_run 'Py/bin/python -c "import sys;import os;sys.exit(\"CONDA_PREFIX\" in os.environ)"' "Conda is not active in venv"
export CW_FORCE_CONDA_ACTIVATE=1
t_run 'Py/bin/python -c "import sys;import os;sys.exit(\"CONDA_PREFIX\" not in os.environ)"' "Conda can be activated in venv"
unset CW_FORCE_CONDA_ACTIVATE
unset CW_EXTRA_BIND_MOUNTS
mkdir -p M MyProg/bin N
echo 'echo HELLO' > MyProg/bin/PP
chmod +x MyProg/bin/PP
export PATH=$OPATH
t_run "wrap-install MyProg/ -w bin --mask --prefix M" "Wrap install --mask"
t_run "M/bin/PP | grep -q HELLO" "wrap-install with --mask works"
t_run "M/bin/_debug_exec touch MyProg/A 2>&1 | grep -q 'Read-only file system'" "--mask covers disk" 
t_run "wrap-install MyProg/ -w bin --prefix N" "Wrap install nomask"
t_run "N/bin/PP | grep -q HELLO" "wrap-install without --mask works"
t_run "N/bin/_debug_exec touch MyProg/A" "disk installation is not masked"
export CW_EXTRA_BIND_MOUNTS=$PWD/MyProg/img.sqfs:$PWD/MyProg:image-src=/,$PWD/S/img.sqfs:$(S/bin/_debug_exec bash -c "echo \$install_root"):image-src=/,$PWD/Gdal/img.sqfs:$(Gdal/bin/_debug_exec bash -c "echo \$install_root"):image-src=/
rm -rf MyProg
mv M MyProg
t_run "S/bin/_debug_exec MyProg/bin/PP | grep -q HELLO" "Composition works into wrapped"
t_run 'MyProg/bin/_debug_exec S/bin/snakemake --help |  grep "usage: snakemake" -q' "Composition works from wrapped"
export PATH=$PWD/Gdal/bin:$PATH
t_run "MyProg/bin/_debug_exec gdaladdo --help-general | grep -q 'Generic GDAL utility command options'" "Multi composition works"
t_run 'MyProg/bin/_debug_exec S/bin/snakemake -j 1' "Nested composition works"
t_run 'MyProg/bin/_debug_exec bash -c "echo \$SINGULARITY_BIND" | grep -q "/$(echo $PWD | cut -d "/" -f2),"' "Top mount point is not excluded"
mkdir 2.1.0
t_run 'wrap-container -w /whitebox_tools docker://crazyzlj/whitebox-tools:2.1.0 --prefix 2.1.0' "Wrap container from external source" 
t_run "2.1.0/bin/whitebox_tools --help" "Using sh if bash not available for wrap container"
t_run 'Gdal/bin/_debug_exec 2.1.0/bin/whitebox_tools --help  | grep  "wrapper called from another container" -q' "Wrapped container gives error when cross called"
res=$(2.1.0/bin/_debug_exec sh -c "echo \$SINGULARITY_BIND" | grep -q -- "image-src")
t_run "test -z $res" "No extra bind mounts into wrapped container"
t_run "grep -q $(git describe --tags) 2.1.0/share/VERSION.yml" "Version information saved"


