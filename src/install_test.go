package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"strings"
	"testing"
)

func TestInstallScript(t *testing.T) {
	logLevel = 2
	for _, tc := range []struct {
		name string
		c    conf
		dirs []string // existing under inst
		want []string
		not  []string
	}{
		{"conda mamba yml uv", conf{"mode": "conda", "env_file": "e.yml", "mamba": "yes", "use_uv": "yes", "requirements_file": "r.txt"},
			[]string{"miniforge"},
			[]string{`_cw_step mamba env create -y --use-uv --name "$CW_ENV_NAME" -f`, "_cw_step uv pip install -r", "list-packages", "PIP_NO_CACHE_DIR=1", "UV_LINK_MODE=copy"},
			[]string{"Miniforge_inst"}},
		{"conda txt", conf{"mode": "conda", "env_file": "e.txt", "pipcache": "yes"},
			[]string{"miniforge"},
			[]string{`_cw_step conda create -y --name "$CW_ENV_NAME" --file`},
			[]string{"pip install", "PIP_NO_CACHE_DIR"}},
		{"conda existing env", conf{"mode": "conda", "env_file": "e.yml"},
			[]string{"miniforge/envs/env1"}, []string{"conda activate"}, []string{"create -y"}},
		{"venv uv", conf{"mode": "venv", "use_uv": "yes", "requirements_file": "r.txt"},
			[]string{"uv/bin/uv"},
			[]string{`uv venv -p "$CW_PYVER" --managed-python`, "_cw_step uv pip install --link-mode=copy", "UV_PYTHON_INSTALL_DIR=/I/uv/python"},
			[]string{"uv_install.sh"}},
		{"venv site packages", conf{"mode": "venv", "enable_site_packages": "yes", "requirements_file": "r.txt"}, nil,
			[]string{`python3 -m venv --system-site-packages "$CW_ENV_NAME"`, "_cw_step pip install --disable-pip-version-check -r"}, nil},
		{"wrapdisk", conf{"mode": "wrapdisk"}, nil, []string{`cp -a "$CW_SOURCE_MOUNT_POINT/."`, "_post_install.sh"}, nil},
	} {
		t.Run(tc.name, func(t *testing.T) {
			inst := t.TempDir()
			for _, d := range tc.dirs {
				os.MkdirAll(inst+"/"+d, 0o755)
			}
			tc.c["installation_path"], tc.c["env_name"] = "/I", "env1"
			s, env, err := (&build{c: tc.c}).installScript(inst)
			if err != nil {
				t.Fatal(err)
			}
			if out, err := exec.Command("bash", "-n", "-c", s).CombinedOutput(); err != nil {
				t.Errorf("syntax: %s\n%s", out, s)
			}
			all := s + strings.Join(env, "\n")
			for _, w := range tc.want {
				if !strings.Contains(all, w) {
					t.Errorf("missing %q in\n%s", w, all)
				}
			}
			for _, w := range tc.not {
				if strings.Contains(all, w) {
					t.Errorf("unexpected %q in\n%s", w, all)
				}
			}
		})
	}
}

func TestMiniforgeVersion(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "/latest") {
			http.Redirect(w, r, "/releases/tag/25.3.0-1", http.StatusFound)
		}
	}))
	defer srv.Close()
	miniforgeURL = srv.URL + "/releases"
	if v, err := miniforgeVersion("latest"); err != nil || v != "25.3.0-1" {
		t.Errorf("got %q, %v", v, err)
	}
	if _, err := miniforgeVersion("bad"); err == nil {
		t.Error("expected error for invalid version")
	}
}

func TestConsole(t *testing.T) {
	var out, log strings.Builder
	c := &console{out: &out, log: &log}
	for _, p := range []string{"a\x1eb\n", "c\n\x1fd\n"} {
		c.Write([]byte(p))
	}
	if out.String() != "ab\nc\nd\n" || log.String() != "b\nc\n" {
		t.Errorf("out %q log %q", out.String(), log.String())
	}
	out.Reset()
	c = &console{out: &out, log: &log, tty: true}
	c.Write([]byte("\x1e1\n2\n"))
	c.Write([]byte("3\n\x1f"))
	if !strings.HasSuffix(out.String(), "\033[F\033[K\033[F\033[K1\n2\n3\n") {
		t.Errorf("redraw %q", out.String())
	}
}

func TestPrepare(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(dir+"/sing", []byte(stubSing), 0o755)
	os.WriteFile(dir+"/broken", []byte("#!/bin/sh\nexit 0\n"), 0o755)
	os.Mkdir(dir+"/nowrite", 0o555)
	os.Mkdir(dir+"/noexe", 0o666)
	for _, tc := range []struct{ prefix, sing, want string }{
		{dir + "/new/inst", dir + "/sing", ""},
		{dir + "/nowrite", dir + "/sing", "not writable"},
		{dir + "/noexe", dir + "/sing", "not writable"},
		{dir + "/ok", "ThisIsNotACommand", "does not exists"},
		{dir + "/ok", dir + "/broken", "not seem to be a valid"},
	} {
		if tc.want == "not writable" && os.Geteuid() == 0 {
			continue // root ignores permissions
		}
		b := &build{c: conf{"installation_prefix": tc.prefix, "singularity_executable_path": tc.sing}, dir: t.TempDir()}
		err := b.prepare()
		if tc.want == "" {
			if err != nil || !isDir(tc.prefix) {
				t.Errorf("%s: %v", tc.prefix, err)
			}
		} else if err == nil || !strings.Contains(err.Error(), tc.want) {
			t.Errorf("%s %s: got %v want %q", tc.prefix, tc.sing, err, tc.want)
		}
	}
}

func TestCleanup(t *testing.T) {
	dir := t.TempDir() + "/cw-X"
	os.Mkdir(dir, 0o755)
	t.Setenv("CW_DEBUG_KEEP_FILES", "1")
	(&build{dir: dir}).cleanup()
	if !isDir(dir) {
		t.Error("removed despite CW_DEBUG_KEEP_FILES")
	}
	os.Unsetenv("CW_DEBUG_KEEP_FILES")
	(&build{dir: dir}).cleanup()
	if exists(dir) {
		t.Error("build dir not removed")
	}
}

func TestFetchShared(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(dir+"/src.sif", nil, 0o644)
	t.Chdir(dir)
	b := &build{c: conf{"container_src": "src.sif", "share_container": "yes", "container_image": "c.sif"}, deploy: dir}
	if err := b.fetch(); err != nil {
		t.Fatal(err)
	}
	if l, _ := os.Readlink(dir + "/c.sif"); l != dir+"/src.sif" {
		t.Errorf("link %q", l)
	}
}
