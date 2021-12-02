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
with open(sys.argv[2]) as user_conf_file:
    user_conf=yaml.safe_load(user_conf_file)

for s in ["prepends","appends", "force"]:
    if s not in shared_conf or shared_conf[s] == None:
       shared_conf[s] = {} 

full_conf=shared_conf["defaults"]
full_conf.update(shared_conf["prepends"])
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
full_conf.update(shared_conf["force"])

if os.getenv("CW_LOG_LEVEL"):
    full_conf["log_level"]=os.getenv("CW_LOG_LEVEL")

build_dir=os.path.expandvars(full_conf["build_tmpdir_base"]+"/cw-"+name_generator())
subprocess.run(["mkdir","-p",build_dir])
full_conf["build_tmpdir"]=build_dir
print(build_dir)



# The follwing keys require special handling can not be dumped as is
specials=["pre_install","post_install","extra_envs"]
with open(build_dir+"/_sing_inst_script.sh",'a+') as f:
    f.write("#!/bin/bash\n")
    f.write("set -e\n")
    f.write("source $CW_INSTALLATION_PATH/common_functions.sh\n")
    if "template_script" in full_conf:
        f.write("source $CW_INSTALLATION_PATH/"+ full_conf["template_script"] +"\n")

with open(build_dir+"/_pre_install.sh",'a+') as f:
    f.write("#!/bin/bash\n")
    if "pre_install" in full_conf:
        for e in full_conf["pre_install"]:
            if "file" in e:
                with open(e["file"],'r') as src_f:
                    f.write(src_f.read())
            else:
                f.write(e+"\n")
with open(build_dir+"/_extra_user_envs.sh",'a+') as f:
    if "extra_envs" in full_conf:
        for e in full_conf["extra_envs"]:
            # A file, fairly small -> fits in memory
            if isinstance(e,dict) and "file" in e:
                with open(e["file"],'r') as src_f:
                    f.write(src_f.read())
            # Individual env var
            # No explicit support for arrays
            # but using set both fixed value and appending possible
            else:
                if e["type"] == "set":
                    f.write('export {}="{}"\n'.format(e["name"],e["value"]))
                elif e["type"] == "append":
                    f.write('export {}="${}:{}"\n'.format(e["name"],e["name"],e["value"]))
                else:
                    f.write('export {}="{}:${}"\n'.format(e["name"],e["value"],e["name"]))
            

        f.write("")
with open(build_dir+"/_post_install.sh",'a+') as f:
    f.write("#!/bin/bash\n")
    if "post_install" in full_conf:
        for e in full_conf["post_install"]:
            if "file" in e:
                with open(e["file"],'r') as src_f:
                    f.write(src_f.read())
            else:
                f.write(e+"\n")
    
# Other lists are dumped directly into bash arrays
c={True:"yes",False:"no"}
with open(build_dir+"/_vars.sh",'a+') as f:
    for k,v in full_conf.items():
        if k not in specials:
            if not isinstance(v,list):
                if isinstance(v,bool):
                    f.write("export CW_{}=\"{}\"\n".format(k.upper(),c[v]))
                else:
                    f.write("export CW_{}=\"{}\"\n".format(k.upper(),os.path.expandvars(str(v))))
            else: 
                # no point in exporting arrays
                f.write("CW_{}=({})\n".format(k.upper()," ".join(['"'+os.path.expandvars(str(elem))+'"' for elem in v ] )))

    f.write("export SINGULARITY_TMPDIR={}\n".format(build_dir))
    f.write("export SINGULARITY_CACHEDIR={}\n".format(os.path.expandvars(full_conf["build_tmpdir_base"])))

with open(build_dir+"/conf.yaml",'a+') as f:
    yaml.dump(full_conf,f)

