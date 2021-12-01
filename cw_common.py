import os
import sys
class colors:
  _RED='\033[0;31m'
  _GREEN='\033[0;32m'
  _YELLOW='\033[1;33m'
  _BLUE="\e[1;34m"
  _NC='\033[0m' # No Color
def print_err(txt):
    print("["+colors._RED+" ERROR "+colors._NC+"] "+txt)

def is_valid_file(parser, arg):
    if not os.path.exists(arg):
        print_err("The file %s does not exist!" % arg)
        sys.exit(1)
    else:
        return arg  
