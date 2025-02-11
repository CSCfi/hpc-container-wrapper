#!/bin/bash

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source $SCRIPT_DIR/setup.sh

rm -rf TYKKY_V_TEST
mkdir -p TYKKY_V_TEST

cd TYKKY_V_TEST
echo "csvkit" > requirements.txt
echo "pip install lxml" > extra.txt

t_run "pip-containerize new --slim --prefix tykky_test requirements.txt" "Creating slim container works"
t_run "singularity exec tykky_test/container.sif cat /etc/os-release  | grep 'Debian'" "Slim container is actually using debian"
t_run "pip-containerize update --post-install extra.txt tykky_test" "Updating a slim container works"
t_run "pip-containerize new --slim --pyver 3.13.2-slim-bullseye --prefix tykky_test2 requirements.txt | grep 'Python 3.13.2'" "--pyver flag does not break"
t_run "tykky_test2/bin/python --version | grep 'Python 3.13.2" "Correct python version used"
