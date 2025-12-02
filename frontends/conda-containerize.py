import argparse
import os
import pathlib
import sys

curr_dir = pathlib.Path(__file__).parent.resolve()
root_dir = pathlib.Path(curr_dir).parent.resolve()
info = sys.version_info
sys.path.insert(0, str(root_dir))
sys.path.insert(
    0, str(root_dir) + "/PyDeps/lib/python{}.{}/site-packages".format(info[0], info[1])
)
import yaml  # noqa: E402
from cw_common import print_err, print_warn  # noqa: E402
from script_shared import (  # noqa E402
    add_adv_pars,
    add_base_pars,
    add_new_pars,
    add_upd_pars,
    get_old_conf,
    is_valid_file,
    parse_wrapper,
)

sys.argv[0] = sys.argv[0].split("/")[-1].split(".")[0]
parser = argparse.ArgumentParser(
    description="Create or modify a Conda installation inside a container"
)
subparsers = parser.add_subparsers(help="subcommands", dest="command")
parser_new = add_new_pars(subparsers)
parser_new.add_argument("env_file", help="conda env file")
parser_new.add_argument(
    "--mamba", help="use mamba for installation", action="store_true"
)
parser_new.add_argument(
    "--uv", help="use uv for pip dependencies (only with mamba)", action="store_true"
)
parser_new.add_argument(
    "--nocache", help="Do not use pip/uv cache", action="store_true"
)
parser_upd = add_upd_pars(subparsers)
add_adv_pars(subparsers)
parser_upd.add_argument(
    "--nocache", help="Do not use pip/uv cache", action="store_true"
)

ps = [parser_new, parser_upd]
for p in ps:
    add_base_pars(p)
    p.add_argument(
        "-r",
        "--requirement",
        type=lambda x: is_valid_file(x),
        help="requirements file for pip",
    )

if len(sys.argv) < 2:
    parser.print_help()
    sys.exit(0)
args = parser.parse_args()
conf = {}
conf["add_ld"] = "no"
conf["use_uv"] = "no"
conf["mode"] = "conda"
conf["template_script"] = "conda.sh"
if args.command == "new":
    conf["env_file"] = args.env_file
    conf["update_installation"] = "no"
    conf["installation_file_paths"] = [conf["env_file"]]
    if args.prefix:
        conf["installation_prefix"] = args.prefix
    conf["mode"] = "conda"
    if args.mamba:
        conf["mamba"] = "yes"
    else:
        conf["mamba"] = "no"
    if args.uv and args.mamba:
        conf["use_uv"] = "yes"
    elif args.uv and not args.mamba:
        print_warn("Using --uv without --mamba does not have an effect")
elif args.command == "update":
    conf["update_installation"] = "yes"
    get_old_conf(args.dir, conf)
else:
    with open(args.yaml, "r") as y:
        conf.update(yaml.safe_load(y))

if args.command == "new" and not os.path.isfile(args.env_file):
    print_err("Env file {} does not exist".format(args.env_file))
    sys.exit(1)

if args.command in ["update", "new"]:
    if args.environ:
        conf["extra_envs"] = [{"file": args.environ}]
    if args.post_install:
        conf["post_install"] = [{"file": args.post_install}]
    if args.requirement:
        conf["requirements_file"] = args.requirement
    if args.pre_install:
        conf["pre_install"] = [{"file": args.pre_install}]


global_conf = {}
with open(os.getenv("CW_GLOBAL_YAML", ""), "r") as g:
    global_conf = yaml.safe_load(g)

parse_wrapper(conf, args, False)

if "requirements_file" in conf:
    if "installation_file_paths" in conf:
        conf["installation_file_paths"].append(conf["requirements_file"])
    else:
        conf["installation_file_paths"] = conf["requirements_file"]

if "pipcache" not in conf:
    conf["pipcache"] = True

if args.nocache is not None:
    conf["pipcache"] = not args.nocache

with open(os.getenv("_usr_yaml", ""), "a+") as f:
    yaml.dump(conf, f)
