import argparse
import yaml
import os
import sys
import pathlib
curr_dir=pathlib.Path(__file__).parent.resolve()
root_dir=pathlib.Path(curr_dir).parent.parent.resolve()
sys.path+=[str(root_dir)]
from cw_common import *

sys.argv[0]="pycont"
parser = argparse.ArgumentParser()
subparsers = parser.add_subparsers(help='subcommands',dest='command')
parser_new = subparsers.add_parser('new', help='Create new installation')
parser_new.add_argument("requirements_file", type=lambda x: is_valid_file(parser, x),help="requirements file for pip")
parser_new.add_argument("--prefix",type=str,help="Installation location")
parser.add_argument("--post-install",help="Script to run after conda env activation",type=lambda x: is_valid_file(parser, x))
parser.add_argument("--environ",help="Script to run before each program launch ",type=lambda x: is_valid_file(parser, x))
parser_update = subparsers.add_parser('update', help='update an existing installation')
parser_update.add_argument('dir', type=str, help='Installation to update')
parser_advanced = subparsers.add_parser('advanced', help='')
parser_advanced.add_argument('yaml',type=str,help='yaml file with tool config')


if len(sys.argv) < 2:
    parser.print_help()
    sys.exit(0)
args = parser.parse_args()
conf={}
if args.command == "new":
    conf["requirements_file"]=args.env_file
    if args.prefix:
        conf["installation_prefix"]=args.prefix
    conf["mode"]="venv"
elif args.command == "update":
    conf["mode"]="venv_modify"
    old_conf={}
    try:
        with open(args.dir+"/share/conf.yaml",'r') as c:
            old_conf=yaml.safe_load(c)
    except FileNotFoundError:
        print_err("Directory {} does not exist or is not a valid installation".format(args.dir))
        sys.exit(1)
        
    conf["container_src"]=args.dir+"/"+old_conf["container_image"]
    conf["sqfs_src"]=args.dir+"/"+old_conf["sqfs_image"]
    conf["installation_path"]=old_conf["installation_path"]
    conf["installation_prefix"]=args.dir
    conf["sqfs_image"]=old_conf["sqfs_image"]
    conf["container_image"]=old_conf["container_image"]
else:
    with open(args.yaml,'r') as y:
        conf=yaml.safe_load(y)



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
    
if conf["mode"] == "venv":
    conf["update_installation"]="no"
    conf["template_script"]="venv.sh"
else:
    conf["update_installation"]="yes"
    conf["template_script"]="venv_modify.sh"
conf["installation_file_paths"]=[conf["requirements_file"]]

with open(os.getenv("_usr_yaml"),'a+') as f:
    yaml.dump(conf,f)

