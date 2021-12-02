import argparse
import yaml
import os
import sys
import pathlib
curr_dir=pathlib.Path(__file__).parent.resolve()
root_dir=pathlib.Path(curr_dir).parent.parent.resolve()
sys.path+=[str(root_dir)]
from cw_common import *
from script_shared import *

sys.argv[0]="pycont"
parser = argparse.ArgumentParser()
subparsers = parser.add_subparsers(help='subcommands',dest='command')
parser_new=add_new_pars(subparsers)
parser_new.add_argument("requirements_file", type=lambda x: is_valid_file(parser, x),help="requirements file for pip")
parser_upd=add_upd_pars(subparsers)
parser_upd.add_argument("-r","--requirements-file", type=lambda x: is_valid_file(parser, x),help="requirements file for pip")
add_adv_pars(subparsers)
add_base_pars(parser)
add_wrapper_flag(parser)


if len(sys.argv) < 2:
    parser.print_help()
    sys.exit(0)
args = parser.parse_args()
conf={}
pyver="3.10.0-slim-buster"
conf["container_src"]="docker://python:{}".format(pyver)
conf["isolate"]="yes"
if args.requirements_file:
    conf["requirements_file"]=args.requirements_file
    conf["installation_file_paths"]=[conf["requirements_file"]]

if args.command == "new":
    if args.prefix:
        conf["installation_prefix"]=args.prefix
    conf["mode"]="venv"
elif args.command == "update":
    conf["mode"]="venv_modify"
    get_old_conf(args.dir,conf)
else:
    with open(args.yaml,'r') as y:
        conf.update(yaml.safe_load(y))



if args.command in ["update","new"]:
    if args.environ:
        conf["extra_envs"]=[{"file":args.environ}]
    if args.post_install:
        conf["post_install"]=[{"file":args.post_install}]


global_conf={}
with open(os.getenv("CW_GLOBAL_YAML"),'r') as g:
    global_conf=yaml.safe_load(g)
    
parse_wrapper(conf,global_conf,args,False)
if conf["mode"] == "venv":
    conf["update_installation"]="no"
    conf["template_script"]="venv.sh"
else:
    conf["update_installation"]="yes"
    conf["template_script"]="venv_modify.sh"

with open(os.getenv("_usr_yaml"),'a+') as f:
    yaml.dump(conf,f)

