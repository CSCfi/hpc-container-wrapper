local version = myModuleVersion()
local prefix = "@PREFIX@"

help([[
Tykky - HPC Container Wrapper
]])
whatis("Name: Tykky")
whatis("Version: " .. version)
whatis("Description: HPC Container Wrapper")
whatis("URL: https://github.com/CSCfi/hpc-container-wrapper")

-- Set paths
prepend_path("PATH", pathJoin(prefix, "bin"))

-- Defines the tykky shell functions (needs Lmod >= 8.6)
source_sh("bash", pathJoin(prefix, "etc/profile.d/tykky.sh"))
