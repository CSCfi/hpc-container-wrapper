## Small more complicated example

Let's compile a small fftw toy code inside a container.

def.yml
```
channels:
  - conda-forge
  - eumetsat
dependencies:
  - fftw3
  - gxx
```

install_prog.sh
```
cp fftw.cpp $CW_INSTALLATION_PATH
cd $CW_INSTALLATION_PATH
export CPATH="$CPATH:$env_root/include"
g++ -lfftw3 -L $env_root/lib fftw.cpp -o fftw_prog
```
[fftw.cpp](https://github.com/SouthAfricaDigitalScience/fftw3-deploy/blob/master/hello-world.cpp)

Here the `CW_INSTALLATION_PATH` point to the root of the installation which will be containerized,
files placed outside this path will not be part of the installation. `env_root`
is a `conda-containerize` specific variable which point to the root of the conda environment.

```
mkdir Inst
conda-containerize new --prefix Inst/ --post install_test.sh -w fftw_prog def.yml 
```

After this we can now run our toy program 
``` 
$ Inst/bin/fftw_prog
0.868345
0.934584
1.01441
1.11207
1.23383
64.513
1.59397
.
.
.
```

The size of this installation is 591MB and 165 files, if we would have
installed it outside the container it would be 1.4GB and 34251 files.
