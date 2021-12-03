import argparse
import os
import sys
import pathlib
curr_dir=pathlib.Path(__file__).parent.resolve()
root_dir=pathlib.Path(curr_dir).parent.resolve()
info=sys.version_info
sys.path.insert(0,str(root_dir))
sys.path.insert(0,str(root_dir)+"/PyDeps/lib/python{}.{}/site-packages".format(info[0],info[1]))
import yaml
from cw_common import *
from script_shared import *

sys.argv[0]="cont-conda"
parser = argparse.ArgumentParser()
subparsers = parser.add_subparsers(help='subcommands',dest='command')
parser_new=add_new_pars(subparsers)
parser_new.add_argument("env_file",help="conda env file")
parser.add_argument("-r", "--requirement", type=lambda x: is_valid_file(parser, x),help="requirements file for pip")
add_upd_pars(subparsers)
add_adv_pars(subparsers)
add_base_pars(parser)
add_wrapper_flag(parser)


if len(sys.argv) < 2:
    parser.print_help()
    sys.exit(0)
args = parser.parse_args()
conf={}
conf["add_ld"]="no"
if args.command == "new":
    conf["env_file"]=args.env_file
    if args.prefix:
        conf["installation_prefix"]=args.prefix
    conf["mode"]="conda"
elif args.command == "update":
    conf["mode"]="conda_modify"
    get_old_conf(args.dir,conf)
else:
    with open(args.yaml,'r') as y:
        conf.update(yaml.safe_load(y))



if args.command in ["update","new"]:
    if args.environ:
        conf["extra_envs"]=[{"file":args.environ}]
    if args.post_install:
        conf["post_install"]=[{"file":args.post_install}]
    if args.requirement:
        conf["requirements_file"]=args.requirement


global_conf={}
with open(os.getenv("CW_GLOBAL_YAML"),'r') as g:
    global_conf=yaml.safe_load(g)
    
parse_wrapper(conf,global_conf,args,False)
if conf["mode"] == "conda":
    conf["update_installation"]="no"
    conf["template_script"]="conda.sh"
    conf["installation_file_paths"]=[conf["env_file"]]
elif conf["mode"]=="conda_modify":
    conf["update_installation"]="yes"
    conf["template_script"]="conda_modify.sh"
else:
    print_err("No or incorrent mode set, [conda,conda_modify]")
    sys.exit(1)
if "requirements_file" in conf:
    conf["installation_file_paths"].append(conf["requirements_file"])

with open(os.getenv("_usr_yaml"),'a+') as f:
    yaml.dump(conf,f)

