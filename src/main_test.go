package main

import (
	"errors"
	"os"
	"reflect"
	"testing"
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
		{"conda-containerize", []string{"new", "--mamba", "--uv", "-r", "req.txt", "env.yml"},
			map[string]any{"mode": modeConda, "mamba": "yes", "use_uv": "yes", "update_installation": "no",
				"installation_file_paths": []any{"env.yml", "req.txt"}, "pipcache": "yes"}},
		{"pip-containerize", []string{"new", "--slim", "--pyver", "3.12", "--nocache", "req.txt"},
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
		{"pip-containerize", []string{"new", "--slim", "--uv", "req.txt"}, true},
		{"conda-containerize", []string{"--prefix", "P"}, true},
		{"conda-containerize", []string{"new", "missing.yml"}, false},
		{"conda-containerize", []string{"update", "nodir"}, false},
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
