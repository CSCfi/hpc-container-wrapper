#!/bin/bash


git checkout v0.3.2
mkdir TT
../bin/conda-containerize new --prefix TT basic.yaml  
git checkout v0.4.2
../bin/conda-containerize update TT --post-install <(echo 'echo "Hello"')
