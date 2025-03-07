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

sys.argv[0]=sys.argv[0].split('/')[-1].split('.')[0]
parser = argparse.ArgumentParser(description="Create or modify a python installation inside a container")
subparsers = parser.add_subparsers(help='subcommands',dest='command')
parser_new=add_new_pars(subparsers)
parser_new.add_argument("requirements_file", type=lambda x: is_valid_file(parser, x),help="requirements file for pip")
parser_upd=add_upd_pars(subparsers)
parser_upd.add_argument("-r","--requirements-file", type=lambda x: is_valid_file(parser, x),help="requirements file for pip")
add_adv_pars(subparsers)
parser_new.add_argument("--slim",action='store_true',help="Use minimal base python container")
parser_new.add_argument("--pyver",help="Docker tag to use for the slim python verison, e.g 3.12.9-bookworm")
parser_new.add_argument("--system-site-packages",action='store_true',help="Enable system and user site packages for the created installation")

ps=[parser_new,parser_upd]
for p in ps:
    add_base_pars(p)




if len(sys.argv) < 2:
    parser.print_help()
    sys.exit(0)
args = parser.parse_args()
conf={}
pyver="3.12.9-slim-bookworm"



if args.requirements_file:
    conf["requirements_file"]=args.requirements_file
    conf["installation_file_paths"]=[conf["requirements_file"]]

if args.command == "new":
    if args.system_site_packages:
        conf["enable_site_packages"]="yes"
    if args.prefix:
        conf["installation_prefix"]=args.prefix
    conf["mode"]="venv"
    if args.slim:
        if args.pyver:
            pyver=args.pyver
        conf["container_src"]="docker://python:{}".format(pyver)
        conf["isolate"]="yes"
    else:
        if args.pyver:
            print_warn("Using --pyver without --slim does not have an effect")

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
    if args.pre_install:
        conf["pre_install"]=[{"file":args.pre_install}]


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

