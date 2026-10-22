package main

import (
	"os"
	"os/exec"
	"strings"
	"testing"
)

// stub singularity: runs the command on the host, ignoring image and binds
const stubSing = `#!/bin/bash
[[ "$1" == "--help" ]] && { echo build; echo exec; echo shell; exit 0; }
shift; shift
[[ "$1" == "-B" ]] && shift 2
shift
exec "$@"
`

// fakeConda builds a conda-like tree on the host, standing in for the image.
func fakeConda(t *testing.T, dir string) *build {
	inst := dir + "/INST"
	env := inst + "/miniforge/envs/env1"
	for _, d := range []string{inst + "/miniforge/bin", env + "/bin", env + "/lib", env + "/lib64", dir + "/B/_deploy"} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	os.WriteFile(inst+"/miniforge/bin/conda", nil, 0o644)
	os.WriteFile(env+"/bin/data.txt", nil, 0o644)
	for _, p := range []string{"python", "pip", "ls"} {
		os.WriteFile(env+"/bin/"+p, []byte("#!/bin/sh\n"), 0o755)
	}
	os.WriteFile(dir+"/sing", []byte(stubSing), 0o755)
	os.WriteFile(dir+"/envs.sh", []byte("export FOO=\"bar\"\n"), 0o644)
	c := conf{"mode": "conda", "sqfs_image": "img.sqfs", "container_image": "container.sif",
		"installation_path": inst, "isolate": false, "wrap_all": false, "add_ld": true, "env_name": "env1",
		"excluded_mount_points": "/appl", "extra_envs": []any{map[string]any{"file": dir + "/envs.sh"},
			map[string]any{"name": "Q", "value": `say "hi" \o/`, "type": "set"}}}
	return &build{c: c, dir: dir + "/B", deploy: dir + "/B/_deploy", sing: dir + "/sing", env: os.Environ()}
}

func TestWrappersConda(t *testing.T) {
	dir := t.TempDir() + "/a b" // the generated shell must quote paths
	b := fakeConda(t, dir)
	logLevel = 0
	if err := b.wrappers(); err != nil {
		t.Fatal(err)
	}
	read := func(p string) string { s, _ := os.ReadFile(b.deploy + "/" + p); return string(s) }
	for _, p := range []string{"python", "pip", "ls", "_debug_exec", "_debug_shell"} {
		if !exists(b.deploy + "/bin/" + p) {
			t.Errorf("missing wrapper %s", p)
		}
	}
	if exists(b.deploy + "/bin/data.txt") {
		t.Error("non-executable file wrapped")
	}
	for _, p := range []string{"bin/python", "bin/_debug_exec"} {
		if out, err := exec.Command("bash", "-n", b.deploy+"/"+p).CombinedOutput(); err != nil {
			t.Errorf("%s: %s", p, out)
		}
	}
	os.WriteFile(b.deploy+"/"+b.c.get("container_image"), nil, 0o644)
	run := exec.Command(b.deploy+"/bin/_debug_exec", "sh", "-c", `echo "$Q"`)
	run.Env = append(os.Environ(), "SINGULARITY_NAME=")
	if out, err := run.Output(); err != nil || string(out) != "say \"hi\" \\o/\n" {
		t.Errorf("_debug_exec: %v %q", err, out)
	}
	run = exec.Command(b.deploy+"/bin/_debug_exec", "sh", "-c", `echo "$SINGULARITYENV_PATH|$SINGULARITY_BIND"`)
	run.Env = append(os.Environ(), "SINGULARITY_NAME=", "PATH=:/a::/b:",
		"CW_EXTRA_BIND_MOUNTS=/x:"+dir+"/INST:image-src=/,/y")
	out, _ := run.Output()
	if p, bind, _ := strings.Cut(strings.TrimSpace(string(out)), "|"); p != "/a:/b" ||
		!strings.HasSuffix(bind, ",,/y") || !strings.Contains(bind, ","+b.deploy+"/_bin:"+b.deploy+"/bin,") {
		t.Errorf("_debug_exec env: %q", out)
	}
	if l, _ := os.Readlink(b.deploy + "/_bin/python"); l != dir+"/INST/miniforge/envs/env1/bin//python" {
		t.Errorf("_bin link %s", l)
	}
	py := read("bin/python")
	if !strings.Contains(py, `eval \"\$('`+dir+`/INST/miniforge/bin/conda' shell.bash hook)\" && conda activate 'env1'`) {
		t.Errorf("no conda activation in wrapper:\n%s", py)
	}
	if exists(b.deploy + "/common.sh") {
		t.Error("common.sh written, the wrappers should hold its setup")
	}
	common := read("bin/_debug_exec")
	for _, want := range []string{
		"SQFS_IMAGE='img.sqfs'\n",
		"export env_root='" + dir + "/INST/miniforge/envs/env1/'\n",
		"SINGULARITYENV_LD_LIBRARY_PATH='" + dir + "/INST/miniforge/envs/env1/lib:" + dir + "/INST/miniforge/envs/env1/lib64'\":",
		"_excludes=('/appl')",
		"export FOO=\"bar\"\n",
	} {
		if !strings.Contains(common, want) {
			t.Errorf("_debug_exec lacks %q", want)
		}
	}
}
