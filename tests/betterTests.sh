SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source $SCRIPT_DIR/betterTestsFunctions.sh
export PATH="$(realpath $SCRIPT_DIR/../bin):$PATH"
# Test are run in current directory

#cd "${TMPDIR:-/tmp}"
rm -fr TEST_DIR
mkdir TEST_DIR
cd TEST_DIR


#### Part 1, Generate input files for testing
echo "[ PRESETUP ] Generating input files"


echo "pyyaml" > req.txt
echo "pyyyaml" > req_typo.txt
echo "pip install requests" > post.sh
echo "uv pip install requests" > post_uv.sh

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
   - dask
   - dask-jobqueue
" > dask_env.yaml

echo "
channels:
  - conda-forge
dependencies:
  - this_is_not_a_package
" > conda_broken.yaml
echo "GARBAGE" > conda_env.txt

echo "
channels:
  - conda-forge
dependencies:
  - numpy
  - uv
  - pip:
    - requests
" > hybrid.yaml

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

#### Part 2, run some tests 
echo "[ RUNNING TESTS]"


STATUS_ARRAY=()
TEST_DESCRIPTION=()
TEST_FILE=()
PID_MAP=()
FIRST_RUN=1
TEST_IDX=0


## Example
# addTest "FlagTest1" ""

testFiles=( ../test02.sh )


#source ../testMoc.sh
for f in "${testFiles[@]}";do
    source $f
done
NUM_TESTS=$TEST_IDX
TEST_IDX=0
#printStatus
export FIRST_RUN=0
for f in "${testFiles[@]}";do
    source $f
done
#erase_lines $NUM_TESTS
printStatus

while jobs -p >/dev/null; do
    sleep 2
    jobs | grep -q "Running" || break 
    updateStatus $NUM_TESTS || { erase_lines $NUM_TESTS; printStatus  ;}
done
updateStatus $NUM_TESTS || { erase_lines $NUM_TESTS; printStatus  ;}
