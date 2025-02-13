import sys
sys.path.append("../")
sys.path.append("../../")
import cw_common
print(cw_common.get_docker_image('/etc/os-release')[1])
