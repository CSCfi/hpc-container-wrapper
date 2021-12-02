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

