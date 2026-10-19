package main

import (
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
	got := c.parse([]string{"env.yml", "--pref", "P", "--mamba", "-w", "bin", "--post-install=post.sh"})
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %v want %v", got, want)
	}
}

func TestMerge(t *testing.T) {
	shared := map[string]any{
		"defaults": map[string]any{"a": "d", "b": "d", "l": []any{"x"}},
		"prepends": map[string]any{"l": []any{"p"}},
		"appends":  map[string]any{"l": []any{"z"}, "n": "new"},
		"force":    map[string]any{"b": "f"},
	}
	got := merge(shared, map[string]any{"a": "u", "b": "u", "l": []any{"u"}})
	want := conf{"a": "u", "b": "f", "l": []any{"p", "u", "z"}, "n": "new"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %v want %v", got, want)
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
