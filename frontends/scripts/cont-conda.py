import argparse
import os
parser = argparse.ArgumentParser()
parser.add_argument("env_file",help="conda env file")
parser.add_argument("-r", "--requirement", type=str,
                    help="requirements file for pip")
parser.add_argument("--prefix",type=str,help="Installation location")
args = parser.parse_args()
with open(os.getenv("_usr_yaml"),'a+') as f:
    f.write("env_file: "+args.env_file+"\n")
    if args.requirement:
        f.write("requirements_file: " + args.requirement+"\n")
    if args.prefix:
        f.write("installation_prefix: " + args.prefix + "\n")
    f.write("mode: conda\n")
    f.write("update_installation: no")

