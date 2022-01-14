"""Utility function for printing errors and warnings while in python"""
import sys
import os
import random
import string

colors={}
colors["RED"]='\033[0;31m'
colors["GREEN"]='\033[0;32m'
colors["YELLOW"]='\033[1;33m'
colors["BLUE"]="\033[1;34m"
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



def name_generator(size=6, chars=string.ascii_uppercase + string.digits):
   return ''.join(random.choice(chars) for _ in range(size))

