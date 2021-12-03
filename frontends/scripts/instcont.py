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

sys.argv[0]="instcont"
parser = argparse.ArgumentParser(description="Wrap an existing installation into a container")
parser.add_argument("dir",type=str,help="Installation to wrap")
add_wrapper_flag(parser)
add_prefix_flag(parser)
add_env_flag(parser)
add_post_flag(parser)
parser.add_argument("-y","--yaml",help="Tool yaml conf file")
parser.add_argument("--mask",action='store_true',help="Mask installation on disk")


if len(sys.argv) < 2:
    parser.print_help()
    sys.exit(0)
args = parser.parse_args()
if not args.wrapper_paths:
    print_err("Tool {} requires -w/--wrapper-paths to be used".format(sys.argv[0]))
    sys.exit(1)
conf={}
#wrapp=[ str(pathlib.Path(w).resolve()) for w in args.wrapper_paths.split(',')]
#args.wrapper_paths=",".join(wrapp)
conf["isolate"]="no"
conf["mode"]="wrapdisk"
conf["wrap_src"]=str(pathlib.Path(args.dir).resolve())
conf["update_installation"]="no"
conf["template_script"]="wrap.sh"
if args.mask:
    conf["installation_path"]=str(pathlib.Path(args.dir).resolve())
    conf["excluded_mount_points"]="/"+conf["installation_path"].split('/')[1]

if args.prefix:
    conf["installation_prefix"]=args.prefix

if args.yaml:
    with open(args.yaml,'r') as y:
        conf.update(yaml.safe_load(y))

if args.environ:
    conf["extra_envs"]=[{"file":args.environ}]
if args.post_install:
    conf["post_install"]=[{"file":args.post_install}]


global_conf={}
with open(os.getenv("CW_GLOBAL_YAML"),'r') as g:
    global_conf=yaml.safe_load(g)
    
parse_wrapper(conf,global_conf,args,False)


with open(os.getenv("_usr_yaml"),'a+') as f:
    yaml.dump(conf,f)

