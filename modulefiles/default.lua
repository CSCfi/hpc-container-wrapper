local version = "0.4.3"
local base = "/appl/soft/manual/general/common/tykky"
help([[
Tykky - HPC Container Wrapper
]])
whatis("Name: Tykky")
whatis("Version: " .. version)
whatis("Description: HPC Container Wrapper")
-- Set paths
prepend_path("PATH", pathJoin(base, version, "bin"))
prepend_path("FPATH", pathJoin(base, version, "share/sh_functions"))
-- Set shell functions:
local function read_file(filename)
    local file = io.open(filename, "r")
    if not file then return nil end
    local content = file:read("*all")
    file:close()
    return content
end
set_shell_function("__tykky_activate", read_file(pathJoin(base, version, "share/sh_functions/__tykky_activate")), "")
set_shell_function("__tykky_deactivate", read_file(pathJoin(base, version, "share/sh_functions/__tykky_deactivate")), "")
set_shell_function("__tykky_get_env_path", read_file(pathJoin(base, version, "share/sh_functions/__tykky_get_env_path")), "")
set_shell_function("tykky", read_file(pathJoin(base, version, "share/sh_functions/tykky")), "")
