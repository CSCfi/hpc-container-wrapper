import os
import sys
import yaml
def is_valid_file(par,arg):
    if not os.path.exists(arg):
        print_err("The file %s does not exist!" % arg)
        sys.exit(1)
    else:
        return arg  

def add_prefix_flag(p):
    p.add_argument("--prefix",type=str,help="Installation location")

def add_post_flag(p):
    p.add_argument("--post-install",help="Script to run after conda env activation",type=lambda x: is_valid_file(par,x))
def add_env_flag(p):
    p.add_argument("--environ",help="Script to run before each program launch ",type=lambda x: is_valid_file(par,x))

def add_wrapper_flag(par):
    par.add_argument("-w","--wrapper-paths",help='Comma separated list of paths')

def add_adv_pars(subpar): 
    parser_advanced = subpar.add_parser('advanced', help='')
    parser_advanced.add_argument('yaml',type=str,help='yaml file with tool config')
    return parser_advanced
def add_upd_pars(subpar):
    parser_update = subpar.add_parser('update', help='update an existing installation')
    parser_update.add_argument('dir', type=str, help='Installation to update')
    return parser_update
def add_new_pars(subpar):
    parser_new = subpar.add_parser('new', help='Create new installation')
    add_prefix_flag(parser_new)
    return parser_new
def add_base_pars(par):
    add_post_flag(par)
    add_env_flag(par)

# non absolute paths are relative to the installation dir
def parse_wrapper(conf,g_conf,a,req_abs):
    if a.wrapper_paths:
        ip=""
        if "installation_path "in conf:
            ip = conf["installation_path"]
        elif "installation_path" in g_conf["force"]:
            ip = g_conf["force"]["installation_path"]
        elif "installation_path" in g_conf["defaults"]:
            ip = g_conf["defaults"]["installation_path"]
        elif not req_abs:
            print_err("Failed to parse wrapper paths, missing installation path")
            sys.exit(1)
        conf["wrapper_paths"]=[]
        for p in a.wrapper_paths.split(','):
            if p[0] == "/":
                conf["wrapper_paths"].append(p)
            elif req_abs:
                print_err("Only absolute paths are accepted for --wrapper-paths/-w")
                sys.exit(1)
            else:
                conf["wrapper_paths"].append(ip+"/"+p)

def get_old_conf(d,conf):
    old_conf={}
    try:
        with open(d+"/share/conf.yaml",'r') as c:
            old_conf=yaml.safe_load(c)
    except FileNotFoundError:
        print_err("Directory {} does not exist or is not a valid installation".format(d))
        sys.exit(1)
        
    conf["container_src"]=d+"/"+old_conf["container_image"]
    conf["sqfs_src"]=d+"/"+old_conf["sqfs_image"]
    conf["installation_path"]=old_conf["installation_path"]
    conf["installation_prefix"]=d
    conf["sqfs_image"]=old_conf["sqfs_image"]
    conf["container_image"]=old_conf["container_image"]
