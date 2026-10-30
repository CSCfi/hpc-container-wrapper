package main

import (
	"errors"
	"os"
	"reflect"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

func TestParse(t *testing.T) {
	c := &cmd{prog: "x new", pos: [][2]string{{"env_file", ""}},
		opts: append([]opt{prefixOpt, {long: "--mamba", flag: true}}, baseOpts...)}
	want := args{"env_file": "env.yml", "prefix": "P", "mamba": "true", "wrapper_paths": "bin", "post_install": "post.sh"}
	// post.sh must exist for the file check
	t.Chdir(t.TempDir())
	os.WriteFile("post.sh", nil, 0o644)
	got, err := c.parse([]string{"env.yml", "--pref", "P", "--mamba", "-w", "bin", "--post-install=post.sh"})
	if err != nil || !reflect.DeepEqual(got, want) {
		t.Errorf("got %v, %v want %v", got, err, want)
	}
	var ue usageError
	for _, argv := range [][]string{{"--nope"}, {"env.yml", "--prefix"}, {}, {"a", "b"}} {
		if _, err := c.parse(argv); !errors.As(err, &ue) {
			t.Errorf("%q: got %v, want usage error", argv, err)
		}
	}
	if _, err := c.parse([]string{"env.yml", "--post-install", "missing.sh"}); err == nil || errors.As(err, &ue) {
		t.Errorf("missing file: got %v", err)
	}
}

func TestFrontend(t *testing.T) {
	t.Chdir(t.TempDir())
	os.WriteFile("env.yml", nil, 0o644)
	os.WriteFile("req.txt", nil, 0o644)
	global := map[string]any{"defaults": map[string]any{"installation_path": "/I"}}
	for _, tc := range []struct {
		prog string
		argv []string
		want map[string]any // subset of the result
	}{
		{"conda", []string{"new", "--mamba", "--uv", "-r", "req.txt", "env.yml"},
			map[string]any{"mode": modeConda, "mamba": "yes", "use_uv": "yes", "update_installation": "no",
				"installation_file_paths": []any{"env.yml", "req.txt"}, "pipcache": "yes"}},
		{"pip", []string{"new", "--slim", "--pyver", "3.12", "--nocache", "req.txt"},
			map[string]any{"mode": modeVenv, "container_src": "docker://python:3.12-slim", "isolate": "yes", "pipcache": "no"}},
		{"wrap-container", []string{"-w", "/opt/bin", "img.sif"},
			map[string]any{"mode": modeWrapCont, "wrapper_paths": []any{"/opt/bin"}}},
	} {
		got, err := frontend(tc.prog, tc.argv, global)
		if err != nil {
			t.Errorf("%s: %v", tc.prog, err)
			continue
		}
		for k, v := range tc.want {
			if !reflect.DeepEqual(got[k], v) {
				t.Errorf("%s: %s = %v want %v", tc.prog, k, got[k], v)
			}
		}
	}
	var ue usageError
	for _, tc := range []struct {
		prog  string
		argv  []string
		usage bool
	}{
		{"nope", []string{"x"}, false},
		{"pip", []string{"new", "--slim", "--uv", "req.txt"}, true},
		{"conda", []string{"--prefix", "P"}, true},
		{"conda", []string{"new", "missing.yml"}, false},
		{"conda", []string{"update", "nodir"}, false},
		{"wrap-container", []string{"img.sif"}, false},
		{"wrap-container", []string{"-w", "rel/bin", "img.sif"}, false},
	} {
		_, err := frontend(tc.prog, tc.argv, global)
		if err == nil || errors.As(err, &ue) != tc.usage {
			t.Errorf("%s %q: got %v", tc.prog, tc.argv, err)
		}
	}
}

func TestMerge(t *testing.T) {
	shared := map[string]any{
		"defaults": map[string]any{"a": "d", "b": "d", "l": []any{"x"}, "s": "-noappend", "m": "x"},
		"prepends": map[string]any{"l": []any{"p"}},
		"appends":  map[string]any{"l": []any{"z"}, "n": "new", "s": "-mem 10000M", "m": []any{"y"}},
		"force":    map[string]any{"b": "f"},
	}
	got := merge(shared, map[string]any{"a": "u", "b": "u", "l": []any{"u"}})
	want := conf{"a": "u", "b": "f", "l": []any{"p", "u", "z"}, "n": "new", "s": "-noappend -mem 10000M", "m": []any{"x", "y"}}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %v want %v", got, want)
	}
}

func TestCheck(t *testing.T) {
	ok := conf{"isolate": true, "add_ld": "no", "num_cpus": 8, "log_level": "", "workdir": "$PWD", "typo_key": 1}
	if err := ok.check(); err != nil {
		t.Errorf("unexpected error %v", err)
	}
	for _, bad := range []conf{{"isolate": "true"}, {"use_uv": "on"}, {"num_cpus": "eight"}} {
		if bad.check() == nil {
			t.Errorf("%v: expected error", bad)
		}
	}
}

func TestDockerImage(t *testing.T) {
	for rel, want := range map[string]string{
		"ID=\"rhel\"\nVERSION_ID=\"8.10\"\n\n":   "redhat/ubi8:8.10",
		"ID=ubuntu\nVERSION_ID=\"24.04\"\n":      "ubuntu:24.04",
		"NAME=x\nID=\"sles\"\nVERSION_ID=15.5\n": "registry.suse.com/bci/bci-base:15.5",
		"ID=nixos\nVERSION_ID=25.05\n":           "nixos:25.05",
	} {
		f := t.TempDir() + "/os-release"
		os.WriteFile(f, []byte(rel), 0o644)
		if got, err := dockerImage(f); err != nil || got != want {
			t.Errorf("got %q, %v want %q", got, err, want)
		}
	}
	if _, err := dockerImage("/nonexistent"); err == nil {
		t.Error("expected error for missing file")
	}
}

func TestHelp(t *testing.T) {
	for prog, tool := range tools {
		c, _ := tool(prog)
		var top strings.Builder
		c.help(&top)
		if !strings.Contains(top.String(), "show this help message") {
			t.Errorf("%s: no -h in help", prog)
		}
		if _, err := frontend(prog, nil, nil); err != errHelp {
			t.Errorf("%s: no args gave %v, want help", prog, err)
		}
		want := []string{"--environ", "--wrapper-paths"}
		if c.subs != nil {
			c = c.subs[0] // new
		}
		if prog != "wrap-container" {
			want = append(want, "--post-install", "--pre-install")
			var ue usageError
			if _, err := c.parse(nil); !errors.As(err, &ue) {
				t.Errorf("%s: no args gave %v, want usage error", c.prog, err)
			}
		}
		var h strings.Builder
		c.help(&h)
		for _, w := range want {
			if !strings.Contains(h.String(), w) {
				t.Errorf("%s: help lacks %s", c.prog, w)
			}
		}
	}
}

func TestConstruct(t *testing.T) {
	dir := t.TempDir()
	t.Chdir(dir)
	user := map[string]any{"update_installation": "no"}
	for env, want := range map[string]string{
		"/proc/not_a_dir": "Could not create build directory",
		"A/B/C":           "path is not absolute",
		dir + "/A/B/C":    "",
	} {
		t.Setenv("CW_BUILD_TMPDIR", env)
		c, err := construct("g.yaml", map[string]any{"force": map[string]any{"build_tmpdir_base": "/proc/not_a_dir"}}, user)
		if want == "" {
			if err != nil || !strings.HasPrefix(str(c["build_tmpdir"]), env+"/cw-") {
				t.Errorf("%s: got %v, %v", env, c["build_tmpdir"], err)
			}
		} else if err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("%s: got %v want %q", env, err, want)
		}
	}
	os.MkdirAll("fake/bin", 0o755)
	os.MkdirAll("fake/_bin", 0o755)
	t.Setenv("PATH", dir+"/fake/bin:"+os.Getenv("PATH"))
	if _, err := construct("g.yaml", nil, user); err == nil || !strings.Contains(err.Error(), "Remove") {
		t.Errorf("active installation: got %v", err)
	}
}

func TestConfYAML(t *testing.T) {
	y, err := confYAML(map[string]any{"isolate": "yes", "mamba": false, "num_cpus": "4", "mode": "conda",
		"extra_envs": []any{map[string]any{"file": "e.sh"}}, "pyver": "3"})
	if err != nil {
		t.Fatal(err)
	}
	for _, w := range []string{"isolate: true\n", "mamba: false\n", "num_cpus: 4\n", `mode: "conda"`, `file: "e.sh"`, `pyver: "3"`} {
		if !strings.Contains(string(y), w) {
			t.Errorf("missing %q in\n%s", w, y)
		}
	}
	var back map[string]any
	if err := yaml.Unmarshal(y, &back); err != nil || str(back["isolate"]) != "yes" || str(back["pyver"]) != "3" {
		t.Errorf("round trip: %v %v", back, err)
	}
}
