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
from cw_common import print_warn  # noqa: E402
from script_shared import (  # noqa: E402
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
    description="Create or modify a python installation inside a container"
)
subparsers = parser.add_subparsers(help="subcommands", dest="command")
parser_new = add_new_pars(subparsers)
parser_new.add_argument(
    "requirements_file",
    type=lambda x: is_valid_file(x),
    help="requirements file for pip",
)
parser_upd = add_upd_pars(subparsers)
parser_upd.add_argument(
    "-r",
    "--requirements-file",
    type=lambda x: is_valid_file(x),
    help="requirements file for pip",
)
parser_upd.add_argument(
    "--nocache", help="Do not use pip/uv cache", action="store_true"
)
add_adv_pars(subparsers)
python_mode = parser_new.add_mutually_exclusive_group()
python_mode.add_argument("--uv", action="store_true", help="Use uv")
python_mode.add_argument(
    "--slim", action="store_true", help="Use minimal base python container"
)
parser_new.add_argument("--pyver", help="Python version to use for slim or uv modes")
parser_new.add_argument(
    "--system-site-packages",
    action="store_true",
    help="Enable system and user site packages for the created installation",
)
parser_new.add_argument(
    "--nocache", help="Do not use pip/uv cache", action="store_true"
)

ps = [parser_new, parser_upd]
for p in ps:
    add_base_pars(p)

if len(sys.argv) < 2:
    parser.print_help()
    sys.exit(0)
args = parser.parse_args()
conf = {}

if args.requirements_file:
    conf["requirements_file"] = args.requirements_file
    conf["installation_file_paths"] = [conf["requirements_file"]]

if args.command == "new":
    conf["mode"] = "venv"
    conf["use_uv"] = "no"
    conf["update_installation"] = "no"
    if args.system_site_packages:
        conf["enable_site_packages"] = "yes"
    if args.prefix:
        conf["installation_prefix"] = args.prefix
    if args.slim:
        conf["pyver"] = "slim"
        if args.pyver:
            if "-slim" in args.pyver or args.pyver == "slim":
                conf["pyver"] = args.pyver
            else:
                conf["pyver"] = args.pyver + "-slim"

        conf["container_src"] = "docker://python:{}".format(conf["pyver"])
        conf["isolate"] = "yes"
    elif args.uv:
        conf["use_uv"] = "yes"
        conf["pyver"] = args.pyver if args.pyver else "3"
    else:
        if args.pyver:
            print_warn("Using --pyver without --slim or --uv does not have an effect")

elif args.command == "update":
    conf["update_installation"] = "yes"
    get_old_conf(args.dir, conf)
else:
    with open(args.yaml, "r") as y:
        conf.update(yaml.safe_load(y))


if args.command in ["update", "new"]:
    if args.environ:
        conf["extra_envs"] = [{"file": args.environ}]
    if args.post_install:
        conf["post_install"] = [{"file": args.post_install}]
    if args.pre_install:
        conf["pre_install"] = [{"file": args.pre_install}]


global_conf = {}
with open(os.getenv("CW_GLOBAL_YAML", ""), "r") as g:
    global_conf = yaml.safe_load(g)

parse_wrapper(conf, args, False)

conf["template_script"] = "venv.sh"

if "pipcache" not in conf:
    conf["pipcache"] = True

if args.nocache is not None:
    conf["pipcache"] = not args.nocache

with open(os.getenv("_usr_yaml", ""), "a+") as f:
    yaml.dump(conf, f)
