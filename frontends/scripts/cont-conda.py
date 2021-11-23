import argparse
import os
parser = argparse.ArgumentParser()
parser.add_argument("env_file",help="conda env file")
parser.add_argument("-r", "--requirement", type=str,
                    help="requirements file for pip")
args = parser.parse_args()
with open(os.getenv("_usr_yaml"),'a+') as f:
    f.write("env_file: "+args.env_file+"\n")
    if args.requirement:
        f.write("requirements_file: " + args.requirement+"\n")
    f.write("mode: conda\n")

