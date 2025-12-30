


echo "pyyaml" > req.txt
echo "pyyyaml" > req_typo.txt
echo "pip install requests" > post.sh

echo "
channels:
  - conda-forge
dependencies:
  - numpy
" > conda_base.yml

echo "
channels:
  - conda-forge
dependencies:
  - this_is_not_a_package
" > conda_broken.yaml


echo "
channels:
  - conda-forge
dependencies:
   - dask
   - dask-jobqueue
" > dask_env.yaml

echo '
import dask
import dask_jobqueue

single_worker = {
    "project" : "pn",
    "queue" : "small",
    "nodes" : 1,
    "cores" : 4,
    "memory" : "8G",
    "time" : "00:10:00",
    "temp_folder" : "/scratch/project_2000599/dask_slurm/temp"
}
cluster = dask_jobqueue.SLURMCluster(
        queue = single_worker["queue"],
        project = single_worker["project"],
        cores = single_worker["cores"],
        memory = single_worker["memory"],
        walltime = single_worker["time"],
        interface = "lo",
        local_directory = single_worker["temp_folder"]
    )
print(cluster.job_script())

' > dask_test.py

runTest "conda-containerize new conda_base.yml --prefix NOT_A_DIR" "Missing install dir is created"
rm -rf A_DIR_NO_WRITE && mkdir A_DIR_NO_WRITE
chmod ugo-w A_DIR_NO_WRITE
runTest "conda-containerize new conda_base.yml --prefix A_DIR_NO_WRITE | grep ERROR" "Installation dir has to be writable"
rm -rf A_DIR_NO_EXE && mkdir A_DIR_NO_EXE
chmod ugo-x A_DIR_NO_EXE
runTest "conda-containerize new conda_base.yml --prefix A_DIR_NO_EXE | grep ERROR" "Installation dir has to be executable"
#
rm -rf CONDA_INSTALL_DIR mkdir CONDA_INSTALL_DIR
rm -rf CONDA_INSTALL_DIR2 mkdir CONDA_INSTALL_DIR2
rm -rf CONDA_INSTALL_DIR3 mkdir CONDA_INSTALL_DIR3
rm -rf CONDA_INSTALL_DIR4 mkdir CONDA_INSTALL_DIR4
rm -rf CONDA_INSTALL_DIR5 mkdir CONDA_INSTALL_DIR5
rm -rf CONDA_INSTALL_DIR6 mkdir CONDA_INSTALL_DIR6
#
runTest "conda-containerize new conda_broken.yaml --prefix CONDA_INSTALL_DIR | tee conda_inst.out | grep 'ResolvePackageNotFound\|PackagesNotFoundError'" "Conda errors are propagated to the user"
brokenTest=$BACKGROUND_PID

runTest "grep ERROR conda_inst.out" "Failed run contains error" $brokenTest 
runTest "grep INFO conda_inst.out"  "Info is present" $brokenTest
runTest "test -z \"\$(grep ' DEBUG ' conda_inst.out )\" "  "Default no debug message" $brokenTest
runTest '\[ ! -e $(cat conda_inst.out | grep -o "[^ ]*/cw-[A-Z,0-9]\{6\} ") \]' "Build dir is deleted on error" $brokenTest
export CW_DEBUG_KEEP_FILES=1
runTest 'conda-containerize new conda_broken.yaml --prefix CONDA_INSTALL_DIR2 &> conda_inst2.out ; \[ -e $(cat conda_inst2.out | grep -o "[^ ]*/cw-[A-Z,0-9]\{6\} ") \] ' "Build dir is saved if CW_DEBUG_KEEP_FILES set"
unset CW_DEBUG_KEEP_FILES


runTest "conda-containerize new --mamba conda_base.yml -r req.txt --prefix CONDA_INSTALL_DIR3 &>/dev/null" "Basic installation works"
workingTest=$BACKGROUND_PID
runTest "CONDA_INSTALL_DIR3/bin/python -m venv VE " "Virtual environment creation works" $workingTest
venvTest=$BACKGROUND_PID
runTest "VE/bin/python -c 'import sys;sys.exit( sys.prefix == sys.base_prefix )'" "Virtual environment is correct" $venvTest
runTest "VE/bin/pip install requests" "pip works for a venv" $venvTest
pipInstallTest=$BACKGROUND_PID
runTest "VE/bin/python -c 'import requests;print(requests.__file__)' | grep -q VE " "Package is installed correctly to venv" $pipInstallTest
runTest "CONDA_INSTALL_DIR3/bin/python -c 'import yaml'" "Package added by -r is there" $pipInstallTest
runTest "conda-containerize update CONDA_INSTALL_DIR3 --post-install post.sh" "Update works" $pipInstallTest
condaUpdateTest=$BACKGROUND_PID
runTest "CONDA_INSTALL_DIR3/bin/python -c 'import requests'" "Package added by update is there" $condaUpdateTest


export CW_ENABLE_CONDARC=1
echo "conda config --show-sources;conda config --show pkgs_dirs;exit 1" > pre.sh
runTest "conda-containerize new --pre-install=pre.sh conda_base.yml --prefix CONDA_INSTALL_DIR4  | grep -q $HOME/.conda/pkgs" "User .condarc can be enabled"
unset CW_ENABLE_CONDARC

runTest "conda-containerize new --mamba dask_env.yaml --prefix CONDA_INSTALL_DIR6 &>/dev/null" "yaml ending is also supported"
daskInstall=$BACKGROUND_PID

OLD_PATH=$PATH
PATH="CONDA_INSTALL_DIR6/bin:$PATH"
runTest "python dask_test.py | grep \"\$(realpath -s \$PWD/CONDA_INSTALL_DIR/bin/python )\" " "Dask uses correct python path" $daskInstall
PATH=$OLD_PATH
