package main

import (
	"bufio"
	"fmt"
	"math/rand/v2"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
)

// conf is the merged configuration. Values stay as YAML gave them so that
// share/conf.yaml round-trips; get/list expand environment variables on read.
type conf map[string]any

// Installation modes, the "mode" setting.
const (
	modeConda    = "conda"
	modeVenv     = "venv"
	modeWrapDisk = "wrapdisk" // wrap-install
	modeWrapCont = "wrapcont" // wrap-container
)

func str(v any) string {
	switch v := v.(type) {
	case nil:
		return ""
	case bool:
		return yesno(v)
	}
	return fmt.Sprint(v)
}

func yesno(b bool) string {
	if b {
		return "yes"
	}
	return "no"
}

func yes(v any) bool { return str(v) == "yes" }

func list(v any) []any {
	switch v := v.(type) {
	case nil:
		return nil
	case []any:
		return v
	}
	return []any{v}
}

func (c conf) get(k string) string { return os.ExpandEnv(str(c[k])) }
func (c conf) yes(k string) bool   { return c.get(k) == "yes" }

// no is true only for an explicit "no"; unset is neither yes nor no.
func (c conf) no(k string) bool  { return c.get(k) == "no" }
func (c conf) has(k string) bool { _, ok := c[k]; return ok }

func (c conf) list(k string) []string {
	var r []string
	for _, v := range list(c[k]) {
		r = append(r, os.ExpandEnv(str(v)))
	}
	return r
}

// realpath resolves symlinks where possible, like `readlink -m`.
func realpath(p string) string {
	p, _ = filepath.Abs(p)
	if r, err := filepath.EvalSymlinks(p); err == nil {
		return r
	}
	return p
}

func exists(p string) bool { _, err := os.Stat(p); return err == nil }

func isDir(p string) bool { st, err := os.Stat(p); return err == nil && st.IsDir() }

func hasApptainer() bool { _, err := exec.LookPath("apptainer"); return err == nil }

func randName(n int, chars string) string {
	b := make([]byte, n)
	for i := range b {
		b[i] = chars[rand.IntN(len(chars))]
	}
	return string(b)
}

const (
	upperDigits = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	alnum       = "abcdefghijklmnopqrstuvwxyz" + upperDigits
)

func concat(a, b any) any {
	if as, ok := a.(string); ok {
		return as + str(b)
	}
	return append(append([]any{}, list(a)...), list(b)...)
}

// merge applies defaults < prepends+user < appends < force.
func merge(shared, user map[string]any) conf {
	sec := func(k string) map[string]any { m, _ := shared[k].(map[string]any); return m }
	full := conf{}
	for k, v := range sec("defaults") {
		full[k] = v
	}
	for k, v := range sec("prepends") {
		full[k] = v
	}
	for k, v := range user {
		if _, ok := sec("prepends")[k]; ok {
			full[k] = concat(full[k], v)
		} else {
			full[k] = v
		}
	}
	for k, v := range sec("appends") {
		if full.has(k) {
			full[k] = concat(full[k], v)
		} else {
			full[k] = v
		}
	}
	for k, v := range sec("force") {
		full[k] = v
	}
	return full
}

// settings lists every known key with the kind of value it takes, "" for any.
var settings = map[string]string{
	"add_ld": "bool", "composable": "bool", "create_wrappers": "bool", "enable_site_packages": "bool",
	"isolate": "bool", "mamba": "bool", "mask_wrap_install": "bool", "pipcache": "bool",
	"share_container": "bool", "update_installation": "bool", "use_uv": "bool", "wrap_all": "bool",
	"log_level": "int", "max_num_cpus": "int", "num_cpus": "int",
	"build_tmpdir": "", "build_tmpdir_base": "", "conda_arch": "", "conda_version": "",
	"container_image": "", "container_src": "", "env_file": "", "env_name": "",
	"excluded_mount_points": "", "extra_envs": "", "installation_file_paths": "",
	"installation_path": "", "installation_prefix": "", "mode": "", "mount_points": "",
	"post_install": "", "pre_install": "", "pyver": "", "requirements_file": "",
	"singularity_executable_path": "", "source_mount_point": "", "sqfs_image": "",
	"sqfs_options": "", "sqfs_src": "", "workdir": "", "wrap_src": "",
	"wrapper_ld_library_paths": "", "wrapper_paths": "",
}

// check warns about unknown keys and rejects values of the wrong kind;
// empty values count as unset.
func (c conf) check() error {
	for k := range c {
		kind, known := settings[k]
		v := c.get(k)
		switch {
		case !known:
			warn("Unknown setting '%s' is ignored", k)
		case v == "":
		case kind == "bool" && v != "yes" && v != "no":
			return fmt.Errorf("Setting '%s' must be yes or no, got '%s'", k, v)
		case kind == "int":
			if _, err := strconv.Atoi(v); err != nil {
				return fmt.Errorf("Setting '%s' must be an integer, got '%s'", k, v)
			}
		}
	}
	return nil
}

// construct merges the configs and creates the build directory.
func construct(globalPath string, global, user map[string]any) (conf, error) {
	c := merge(global, user)
	if err := c.check(); err != nil {
		return nil, err
	}
	if c.yes("composable") && c.no("update_installation") && !c.yes("mask_wrap_install") {
		c["installation_path"] = str(c["installation_path"]) + "_" + randName(7, alnum)
	}
	if c.has("wrapper_paths") {
		var w []any
		for _, p := range list(c["wrapper_paths"]) {
			if p := str(p); strings.HasPrefix(p, "/") {
				w = append(w, p)
			} else {
				w = append(w, str(c["installation_path"])+"/"+p)
			}
		}
		c["wrapper_paths"] = w
	}
	if l := os.Getenv("CW_LOG_LEVEL"); l != "" {
		c["log_level"] = l
	}
	if c.get("container_src") == "auto" {
		img, err := dockerImage("/etc/os-release")
		if err != nil {
			return nil, fmt.Errorf("Unable to automatically determine base container to use: %v", err)
		}
		info(2, "Automatically determined base container to: %s", img)
		c["container_src"] = "docker://" + img
	}
	if c.get("conda_arch") == "auto" {
		m, err := exec.Command("uname", "-m").Output()
		if err != nil {
			return nil, fmt.Errorf("Unable to determine conda_arch: %v", err)
		}
		c["conda_arch"] = "Linux-" + strings.TrimSpace(string(m))
	}
	if d := os.Getenv("CW_BUILD_TMPDIR"); d != "" {
		c["build_tmpdir_base"] = d
	}
	if active := installationsInPath(); len(active) > 0 {
		if c.no("update_installation") {
			return nil, fmt.Errorf("Remove %v from PATH before running the tool, otherwise the tool might not work correctly", active)
		}
		warn("Found existing installation(s) %v in PATH. It's recommended to remove these from PATH when running the tool", active)
	}
	base := c.get("build_tmpdir_base")
	if err := os.MkdirAll(base, 0o777); err != nil {
		return nil, fmt.Errorf("Could not create build directory %s='%s': %v  \n\tEither correct build_tmpdir_base in %s\n\tor set CW_BUILD_TMPDIR to a valid path", c["build_tmpdir_base"], base, err, globalPath)
	}
	if syscall.Access(base, 2) != nil {
		return nil, fmt.Errorf("Build directory %s is not writable", base)
	}
	dir := base + "/cw-" + randName(6, upperDigits)
	if !filepath.IsAbs(dir) {
		return nil, fmt.Errorf("Build directory path is not absolute")
	}
	if err := os.MkdirAll(dir, 0o777); err != nil {
		return nil, err
	}
	c["build_tmpdir"] = dir
	if l, err := fmt.Sscan(c.get("log_level"), &logLevel); l != 1 || err != nil {
		logLevel = 2
	}
	return c, nil
}

func installationsInPath() []string {
	var r []string
	for _, p := range filepath.SplitList(os.Getenv("PATH")) {
		if exists(p+"/../bin") && exists(p+"/../_bin") && exists(p+"/../common.sh") {
			r = append(r, p)
		}
	}
	return r
}

// dockerImage guesses a container matching the host OS.
func dockerImage(osRelease string) (string, error) {
	f, err := os.Open(osRelease)
	if err != nil {
		return "", err
	}
	defer f.Close()
	kv := map[string]string{}
	for s := bufio.NewScanner(f); s.Scan(); {
		if k, v, ok := strings.Cut(strings.TrimSpace(s.Text()), "="); ok {
			kv[k] = strings.Trim(v, `"`)
		}
	}
	id, ver := strings.ToLower(kv["ID"]), strings.ToLower(kv["VERSION_ID"])
	img, known := map[string]string{
		"sles":      "registry.suse.com/bci/bci-base",
		"rhel":      "redhat/ubi",
		"almalinux": "almalinux",
		"rocky":     "rockylinux/rockylinux",
		"ubuntu":    "ubuntu",
	}[id]
	if !known {
		img = id // a guess, fails for most small distros
	}
	if id == "rhel" { // UBI images carry the major version in the name
		img += strings.Split(ver, ".")[0]
	}
	return img + ":" + ver, nil
}
