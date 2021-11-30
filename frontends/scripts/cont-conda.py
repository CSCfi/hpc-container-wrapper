import argparse
import yaml
import os
parser = argparse.ArgumentParser()
parser.add_argument("env_file",help="conda env file")
parser.add_argument("-r", "--requirement", type=str,
                    help="requirements file for pip")
parser.add_argument("--prefix",type=str,help="Installation location")
args = parser.parse_args()
conf={}
with open(os.getenv("_usr_yaml"),'a+') as f:
    conf["env_file"]=args.env_file
    conf["requirements_file"]=""
    conf["installation_file_paths"]=[conf["env_file"]]
    if args.requirement:
        conf["requirements_file"]=args.requirement
        conf["installation_file_paths"].append(conf["requirements_file"])
    if args.prefix:
        conf["installation_prefix"]=args.prefix
    conf["mode"]="conda"
    conf["update_installation"]="no"
    conf["template_script"]="conda.sh"
    yaml.dump(conf,f)
