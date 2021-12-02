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

sys.argv[0]="wrapcont"
parser = argparse.ArgumentParser()
parser.add_argument("container",type=str,help="Container to wrap, can be docker/singularity url")
add_wrapper_flag(parser)
add_prefix_flag(parser)
add_env_flag(parser)
parser.add_argument("-y","--yaml",help="Tool yaml conf file")


if len(sys.argv) < 2:
    parser.print_help()
    sys.exit(0)
args = parser.parse_args()
if not args.wrapper_paths:
    print_err("Tool {} requires -w/--wrapper-paths to be used".format(sys.argv[0]))
    sys.exit(1)
conf={}
conf["container_src"]=args.container
conf["isolate"]="yes"
conf["mode"]="wrapcont"
if args.prefix:
    conf["installation_prefix"]=args.prefix

if args.yaml:
    with open(args.yaml,'r') as y:
        conf.update(yaml.safe_load(y))

if args.environ:
    conf["extra_envs"]=[{"file":args.environ}]


global_conf={}
with open(os.getenv("CW_GLOBAL_YAML"),'r') as g:
    global_conf=yaml.safe_load(g)
    
parse_wrapper(conf,global_conf,args,True)


with open(os.getenv("_usr_yaml"),'a+') as f:
    yaml.dump(conf,f)

