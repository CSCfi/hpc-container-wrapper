"""Utility function for printing errors and warnings while in python"""
import sys

colors={}
colors["RED"]='\033[0;31m'
colors["GREEN"]='\033[0;32m'
colors["YELLOW"]='\033[1;33m'
colors["BLUE"]="\033[1;34m"
colors["NC"]='\033[0m' # No Color

def print_err(txt):
    """Pretty error message, color is disabled if not in a TTY"""
    if not sys.stdout.isatty():
        print("[ ERROR ] "+txt)
    else:
        print("["+colors["RED"]+" ERROR "+colors["NC"]+"] "+txt)
def print_err_stderr(msg):
    if not sys.stderr.isatty():
        print("[ ERROR ] "+msg, file=sys.stderr)
    else:
        print("["+colors["RED"]+" ERROR "+colors["NC"]+"] "+msg,file=sys.stderr)
