import os
import sys
import subprocess
import yaml

import string
import random
def name_generator(size=6, chars=string.ascii_uppercase + string.digits):
   return ''.join(random.choice(chars) for _ in range(size))





tool_root_dir=os.path.dirname(os.path.realpath(__file__))
shared_conf=None
user_conf=None
full_conf={}




with open(sys.argv[1]) as shared_conf_file:
    shared_conf=yaml.safe_load(shared_conf_file)
for s in ["prepends","appends", "force"]:
    if s not in shared_conf or shared_conf[s] == None:
       shared_conf[s] = {} 
full_conf=shared_conf["defaults"]
for k,v in shared_conf["prepends"].items():
    full_conf[k]=v
with open(sys.argv[2]) as user_conf_file:
    user_conf=yaml.safe_load(user_conf_file)
for k,v in user_conf.items():
    if k in shared_conf["prepends"]:
       full_conf[k] = full_conf[k] + v
    else:
       full_conf[k] =  v
for k,v in shared_conf["appends"].items():
    if k in full_conf:
        full_conf[k]= full_conf[k] + v
    else:
        full_conf[k] = v
for k,v in shared_conf["force"].items():
    full_conf[k] = v


# Handle the different modes
if(full_conf["mode"] == "conda"):
    template_script="conda.sh"
    full_conf["installation_file_paths"]=[full_conf["env_file"]]
    if "requirements_file" in full_conf:
        full_conf["installation_file_paths"].append(full_conf["requirements_file"])
    else:
        full_conf["requirements_file"]=""

build_dir=os.path.expandvars(full_conf["build_tmpdir_base"]+"/cw-"+name_generator())
subprocess.run(["mkdir",build_dir])
full_conf["build_tmpdir"]=build_dir




# The follwing keys require special handling can not be dumped as is
#FIXME implement this !
specials=["pre_install","post_install","extra_env"]
with open(build_dir+"/_sing_inst_script.sh",'a+') as f:
    f.write("#!/bin/bash\n")
    f.write("source "+tool_root_dir+"/templates/"+ template_script +"\n")
with open(build_dir+"/_pre_install.sh",'a+') as f:
    f.write("")
with open(build_dir+"/_post_install.sh",'a+') as f:
    f.write("")
    
# Other lists are dumped directly into bash arrays
c={True:"yes",False:"no"}
with open(build_dir+"/_vars.sh",'a+') as f:
    for k,v in full_conf.items():
        if not isinstance(v,list):
            if isinstance(v,bool):
                f.write("CW_{}=\"{}\"\n".format(k.upper(),c[v]))
            else:
                f.write("CW_{}=\"{}\"\n".format(k.upper(),v))
        
        elif k not in specials:
                f.write("CW_{}=({})\n".format(k.upper()," ".join(['"'+elem+'"' for elem in v ] )))

