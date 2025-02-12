"""Utility function for printing errors and warnings while in python"""
import sys
import os
import random
import string
import pathlib
import sys
import shutil

colors={}
colors["RED"]='\033[0;31m'
colors["GREEN"]='\033[0;32m'
colors["YELLOW"]='\033[1;33m'
colors["BLUE"]="\033[1;34m"
colors["PURPLE"]='\033[0;35m'
colors["NC"]='\033[0m' # No Color

def print_err(txt,err=False):
    """Pretty error message, color is disabled if not in a TTY"""
    if(err):
        if not sys.stderr.isatty():
            print("[ ERROR ] "+txt, file=sys.stderr)
        else:
            print("["+colors["RED"]+" ERROR "+colors["NC"]+"] "+txt,file=sys.stderr)

    else:
        if not sys.stdout.isatty():
            print("[ ERROR ] "+txt)
        else:
            print("["+colors["RED"]+" ERROR "+colors["NC"]+"] "+txt)

def print_info(txt,log_level,msg_level,err=False):
    """Pretty info message, color is disabled if not in a TTY"""
    if int(log_level) <= msg_level:
        return
    if msg_level >= 2:
        msg="DEBUG"
        color=colors["PURPLE"]
    else:
        msg="INFO"
        color=colors["BLUE"]
    if(err):
        if not sys.stderr.isatty():
            print(f"[ {msg} ] "+txt,file=sys.stderr)
        else:
            print("["+color+f" {msg} "+colors["NC"]+"] "+txt,file=sys.stderr)
    else:
        if not sys.stdout.isatty():
            print(f"[ {msg} ] "+txt,file=sys.stderr)
        else:
            print("["+color+f" {msg} "+colors["NC"]+"] "+txt,file=sys.stdout)

def print_warn(txt,err=False):
    if(err):
        if not sys.stderr.isatty():
            print("[ WARNING ] "+txt, file=sys.stderr)
        else:
            print("["+colors["YELLOW"]+" WARNING "+colors["NC"]+"] "+txt,file=sys.stderr)

    else:
        if not sys.stdout.isatty():
            print("[ WARNING ] "+txt)
        else:
            print("["+colors["YELLOW"]+" WARNING "+colors["NC"]+"] "+txt)
    

def expand_vars(path,rec=0):
    if(rec > 10):
        print_err("Max 10 shell variables allowed per value, check configuration ",True)
        sys.exit(1)
    g=path
    try: 
        g=string.Template(g).substitute(os.environ)
    except KeyError as E:
        var=E.args[0]
        return expand_vars(g.replace(f"${var}",''),rec+1)
    return g

def has_apptainer():
    return shutil.which("apptainer") != None

def name_generator(size=6, chars=string.ascii_uppercase + string.digits):
   return ''.join(random.choice(chars) for _ in range(size))

def installation_in_PATH():
    return [P for P in os.environ["PATH"].split(':') if is_installation(P) ]

def is_installation(base_path):
    markers=["bin","_bin","common.sh"]
    return all( pathlib.Path(base_path+'/../'+m).exists() for m in markers )

# UBI images are namespaced with the major version as part of the name
# and not just the tag.
special={}
special["rhel"]= lambda namespace,version: namespace+version.split('.')[0]

# Get the docker image matching the host OS
def get_docker_image(release_file):
    os_release_file = release_file
    docker_images = {
        "sles": "opensuse/leap",
        "rhel": "redhat/ubi",
        "almalinux": "almalinux",
        "rocky": "rockylinux",
        "ubuntu": "ubuntu"
    }

    try:
        with open(os_release_file, 'r') as file:
            lines = file.readlines()
            os_info = {}
            for line in lines:
                # Lazy way to handle empty lines
                try:
                    key, value = line.strip().split('=', 1)
                except:
                    continue
                os_info[key] = value.strip('"')

            os_id = os_info.get("ID", "").lower()
            version_id = os_info.get("VERSION_ID", "").lower()

            if os_id in docker_images:
                docker_image = docker_images[os_id]
                if os_id in special:
                    docker_image = special[os_id](docker_image,version_id)
                return (True,f"{docker_image}:{version_id}")
            else:
                # Guess what the name could be
                # Will most likely fail for most small distros
                return (True,f"{os_id}:{version_id}")

    except FileNotFoundError:
        return (False,"OS release file not found")
    except Exception as e:
        return (False,f"An error occurred: {e}")
