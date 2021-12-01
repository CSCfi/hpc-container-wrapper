import argparse
import yaml
import os
import sys
def is_valid_file(parser, arg):
    if not os.path.exists(arg):
        parser.error("The file %s does not exist!" % arg)
    else:
        return arg  

sys.argv[0]="cont-conda"
parser = argparse.ArgumentParser()
subparsers = parser.add_subparsers(help='modes',dest='command')
parser_new = subparsers.add_parser('new', help='Create new installation')
parser_new.add_argument("env_file",help="conda env file")
parser.add_argument("-r", "--requirement", type=str,
                    help="requirements file for pip")
parser_new.add_argument("--prefix",type=str,help="Installation location")
parser.add_argument("--post-install",help="Script to run after conda env activation",type=lambda x: is_valid_file(parser, x))
parser.add_argument("--environ",help="Script to run before each program launch ",type=lambda x: is_valid_file(parser, x))

parser_update = subparsers.add_parser('update', help='update an existing installation')
parser_update.add_argument('dir', type=str, help='Installation to update')


if len(sys.argv) < 2:
    parser.print_help()
    sys.exit(0)
args = parser.parse_args()
if args.command == "new":
    conf={}
    conf["env_file"]=args.env_file
    conf["requirements_file"]=""
    conf["installation_file_paths"]=[conf["env_file"]]
    if args.requirement:
        conf["requirements_file"]=args.requirement
        conf["installation_file_paths"].append(conf["requirements_file"])
    if args.prefix:
        conf["installation_prefix"]=args.prefix
    if args.environ:
        conf["extran_envs"]=[{"file":args.environ}]
    if args.post_install:
        conf["post_install"]=[{"file":args.post_install}]
    conf["mode"]="conda"
    conf["update_installation"]="no"
    conf["template_script"]="conda.sh"
else:
    print("Functionality not implemented yet")
    sys.exit(0)

global_conf={}
with open(os.getenv("CW_GLOBAL_YAML"),'r') as g:
    global_conf=yaml.safe_load(g)
    

with open(os.getenv("_usr_yaml"),'a+') as f:
    yaml.dump(conf,f)

