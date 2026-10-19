package main

import (
	"cmp"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"gopkg.in/yaml.v3"
)

type build struct {
	c          conf
	dir        string // build directory
	deploy     string // becomes the installation directory
	sing       string
	prefix     string // absolute installation prefix
	globalPath string
	env        []string
}

func run(globalPath string, global, user map[string]any) int {
	start := time.Now()
	b := &build{globalPath: globalPath}
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
	go func() { <-sig; b.cleanup(); os.Exit(1) }()

	info(1, "Constructing configuration")
	info(2, "Parsing user and default configs ")
	c, err := construct(globalPath, global, user)
	if err != nil {
		errorf("%v", err)
		errorf("Configuration construction failed")
		b.cleanup()
		return 1
	}
	b.c, b.dir = c, c.get("build_tmpdir")
	info(1, "Using %s as temporary directory", b.dir)
	if err := b.all(); err != nil {
		errorf("%v", err)
		b.cleanup()
		return 1
	}
	info(1, "Done, duration: %ds", int(time.Since(start).Seconds()))
	if os.Getenv("BASH_FUNC_tykky%%") != "" { // tykky shell function is exported
		name := c.get("installation_prefix")
		for _, p := range filepath.SplitList(cmp.Or(os.Getenv("TYKKY_PATH"), os.Getenv("HOME")+"/.tykky")) {
			if realpath(filepath.Dir(b.prefix)) == realpath(p) {
				name = filepath.Base(name)
				break
			}
		}
		info(1, "Environment has been installed to %s\n\tTo use, activate with:\n\ttykky activate %s\n\tAlternatively, add the bin folder to your path e.g:\n\texport PATH=\"%s/bin:$PATH\"", c.get("installation_prefix"), name, b.prefix)
	} else {
		info(1, "Program has been installed to %s\n\tTo use add the bin folder to your path e.g:\n\texport PATH=\"%s/bin:$PATH\"", c.get("installation_prefix"), b.prefix)
	}
	return 0
}

func (b *build) cleanup() {
	if os.Getenv("CW_DEBUG_KEEP_FILES") != "" {
		if b.dir != "" {
			errorf("Build files can be found at %s", b.dir)
		} else {
			errorf("Program failed before any build files were created")
		}
		return
	}
	if b.dir != "" {
		exec.Command("chmod", "-R", "u+w", b.dir).Run()
		os.RemoveAll(b.dir)
	}
	errorf("Set CW_DEBUG_KEEP_FILES env variable to keep build files or set CW_LOG_LEVEL to a higher value for more output, e.g. CW_LOG_LEVEL=3")
}

func (b *build) all() error {
	if err := b.prepare(); err != nil {
		return err
	}
	if err := b.fetch(); err != nil {
		return fmt.Errorf("Failed getting container image: %w", err)
	}
	if b.c.get("mode") != modeWrapCont { // nothing to install when just wrapping a container
		if err := b.install(); err != nil {
			return fmt.Errorf("Installation failed: %w", err)
		}
	}
	if b.c.yes("create_wrappers") {
		if err := b.wrappers(); err != nil {
			return fmt.Errorf("Wrapper generation failed: %w", err)
		}
	}
	if err := b.post(); err != nil {
		return fmt.Errorf("Failed to move to install dir: %w", err)
	}
	return nil
}

// cmd runs name with the build environment plus extra, output to the terminal.
func (b *build) cmd(extra []string, name string, args ...string) *exec.Cmd {
	cmd := exec.Command(name, args...)
	cmd.Env = append(append([]string{}, b.env...), extra...)
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	return cmd
}

func (b *build) prepare() error {
	c := b.c
	prefix := c.get("installation_prefix")
	if !isDir(prefix) {
		info(1, "Installation dir %s does not exist, creating it for you", prefix)
		if err := os.MkdirAll(prefix, 0o777); err != nil {
			return err
		}
	}
	if syscall.Access(prefix, 2|1) != nil {
		return fmt.Errorf("Installation dir %s is not writable", prefix)
	}

	umask := syscall.Umask(0)
	syscall.Umask(umask)
	st, err := os.Stat(b.dir)
	if err != nil {
		return err
	}
	mode := uint32(st.Mode().Perm())
	switch umask {
	case 0o007:
		mode = (mode | 0o070) &^ 0o007
	case 0o002:
		mode |= 0o075
	case 0o022:
		mode |= 0o055
	default:
		warn("Umask set to %04o, check permissions of finished installation", umask)
	}
	info(2, "Umask is %04o", umask)
	if err := syscall.Chmod(b.dir, mode); err != nil {
		return err
	}
	pst, _ := os.Stat(prefix)
	gid := pst.Sys().(*syscall.Stat_t).Gid
	group := strconv.Itoa(int(gid))
	if g, err := user.LookupGroupId(group); err == nil {
		group = g.Name
	}
	info(2, "Setting group ownership of build directory to %s", group)
	if os.Lchown(b.dir, -1, int(gid)) != nil {
		warn("Failed to match group ownership of installation directory, attempted group was %s", group)
	}
	if syscall.Chmod(b.dir, mode|syscall.S_ISGID) != nil {
		warn("Failed to set group stickybit for build directory, installation permissions might be incorrect. Please check once the installation is done.")
	}
	b.prefix, _ = filepath.Abs(prefix)

	b.sing = c.get("singularity_executable_path")
	if _, err := exec.LookPath(b.sing); err != nil {
		return fmt.Errorf("The command %s does not exists\n\tVerify that the value for 'singularity_executable_path' in %s is correct", b.sing, b.globalPath)
	}
	info(2, "Validating the set singularity command %s", b.sing)
	out, _ := exec.Command(b.sing, "--help").Output()
	n := 0
	for _, l := range strings.Split(string(out), "\n") {
		if strings.Contains(l, "build") || strings.Contains(l, "exec") || strings.Contains(l, "shell") {
			n++
		}
	}
	if n < 3 {
		return fmt.Errorf("%s does not seem to be a valid apptainer/singularity executable", b.sing)
	}

	// Scalar settings are visible to the scripts run inside the container as CW_<KEY>.
	b.env = os.Environ()
	for k, v := range c {
		switch v.(type) {
		case []any, map[string]any:
		default:
			b.env = append(b.env, "CW_"+strings.ToUpper(k)+"="+c.get(k))
		}
	}
	b.env = append(b.env, "SINGULARITY_TMPDIR="+b.dir, "SINGULARITY_CACHEDIR="+c.get("build_tmpdir_base"))
	b.deploy = b.dir + "/_deploy"
	return os.MkdirAll(b.deploy, 0o777)
}

func (b *build) fetch() error {
	c := b.c
	src, img := c.get("container_src"), b.img()
	switch {
	case !exists(src):
		info(1, "Fetching container %s", src)
		if err := b.cmd(nil, b.sing, "--silent", "pull", img, src).Run(); err != nil {
			return fmt.Errorf("Failed fetching container")
		}
		if !exists(img) {
			return fmt.Errorf("%s pull returned success, but no container was fetched", b.sing)
		}
	case c.yes("share_container"):
		info(1, "Using container %s", src)
		abs, _ := filepath.Abs(src)
		if err := os.Symlink(abs, img); err != nil {
			return err
		}
	default:
		info(1, "Copying container %s", src)
		if err := b.cmd(nil, "cp", src, img).Run(); err != nil {
			return err
		}
	}
	if c.has("sqfs_src") {
		sq := c.get("sqfs_src")
		if st, err := os.Stat(sq); err != nil || st.IsDir() {
			return fmt.Errorf("SQFS image %s does not exist", sq)
		}
		info(1, "Copying image %s", sq)
		return b.cmd(nil, "cp", sq, b.sqfs()).Run()
	}
	return nil
}

// userScript concatenates a pre_install/post_install list of commands and {file: path} entries.
func userScript(entries any) (string, error) {
	s := "#!/bin/bash\n"
	for _, e := range list(entries) {
		if m, ok := e.(map[string]any); ok {
			b, err := os.ReadFile(str(m["file"]))
			if err != nil {
				return "", err
			}
			s += string(b)
		} else {
			s += str(e) + "\n"
		}
	}
	return s, nil
}

// envRoot is where the install script creates the environment; empty if none.
func (b *build) envRoot() string {
	switch b.c.get("mode") {
	case modeConda:
		return b.c.get("installation_path") + "/miniforge/envs/" + b.c.get("env_name") + "/"
	case modeVenv:
		return b.c.get("installation_path") + "/" + b.c.get("env_name") + "/"
	}
	return ""
}

func (b *build) install() error {
	c := b.c
	ipath, inst := c.get("installation_path"), b.dir+"/_inst_dir"
	if err := os.Mkdir(inst, 0o777); err != nil {
		return err
	}
	inputs := c.list("installation_file_paths")
	if len(inputs) > 0 {
		if err := b.cmd(nil, "cp", append(append([]string{"-a"}, inputs...), inst)...).Run(); err != nil {
			return err
		}
	}
	for name, k := range map[string]string{"_pre_install.sh": "pre_install", "_post_install.sh": "post_install"} {
		s, err := userScript(c[k])
		if err != nil {
			return err
		}
		if err := os.WriteFile(inst+"/"+name, []byte(s), 0o755); err != nil {
			return err
		}
	}

	var dirs, env []string
	if c.yes("isolate") {
		dirs = c.list("mount_points")
	} else {
		env = append(env, "SINGULARITYENV_PATH="+os.Getenv("PATH"))
		if v, ok := os.LookupEnv("LD_LIBRARY_PATH"); ok {
			env = append(env, "SINGULARITYENV_LD_LIBRARY_PATH="+v)
		}
		dirs = rootDirs()
	}
	var binds []string
	for _, d := range dirs {
		if isDir(d) {
			binds = append(binds, d)
		}
	}
	binds = append(binds, "/tmp")
	// by default ignore the user condarc, it may interfere with the installation
	if _, ok := os.LookupEnv("CW_ENABLE_CONDARC"); !ok {
		env = append(env, "CONDA_PKGS_DIRS="+ipath+"/miniforge/pkgs")
	}
	if err := os.Mkdir(b.dir+"/.conda_override", 0o777); err != nil {
		return err
	}
	binds = append(binds, b.dir+"/.conda_override:"+realpath(os.Getenv("HOME")+"/.conda"))
	env = append(env, "install_root="+ipath)
	if r := b.envRoot(); r != "" {
		env = append(env, "env_root="+r)
	}

	img := b.img()
	execArgs := []string{"--silent", "exec", img}
	binds = append(binds, inst+":"+ipath)
	switch {
	case c.yes("update_installation"):
		smp := c.get("source_mount_point")
		execArgs = []string{"--silent", "exec", "-B", imageBind(b.sqfs(), smp), img}
		binds = append(binds, b.prefix+"/_bin:"+b.prefix+"/bin")
	case c.get("mode") == modeWrapDisk:
		binds = append(binds, c.get("wrap_src")+":"+c.get("source_mount_point"))
	}
	env = append(env, "SINGULARITY_BIND="+strings.Join(binds, ","))
	if c.yes("update_installation") {
		smp := c.get("source_mount_point")
		info(1, "Copying installation to writable area, might take a while")
		info(1, "%s", realpath(c.get("installation_prefix")))
		if err := b.cmd(env, b.sing, append(execArgs, "cp", "-a", smp+"/.", ipath)...).Run(); err != nil {
			return fmt.Errorf("Failed to copy some files, most likely incorrect file permissions inside the squashfs image")
		}
	}
	sh, extra, err := b.installScript(inst)
	if err != nil {
		return err
	}
	info(1, "Running installation script")
	log, err := os.OpenFile(b.dir+"/build.log", os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer log.Close()
	cmd := b.cmd(append(env, extra...), b.sing, append(execArgs, "bash", "-c", sh)...)
	cmd.Stdout = &console{out: os.Stdout, log: log, tty: tty}
	// don't hang on background processes left holding the output by the user's scripts
	cmd.WaitDelay = time.Second
	if err := cmd.Run(); err != nil && !errors.Is(err, exec.ErrWaitDelay) {
		return err
	}

	for _, name := range []string{"_pre_install.sh", "_post_install.sh", "Miniforge_inst.sh", "uv_install.sh"} {
		os.Remove(inst + "/" + name)
	}
	// keep inputs of every build in a separate folder so they are not overwritten
	prev := ""
	for n := 0; ; n++ {
		if prev = fmt.Sprintf("%s/previous_input/%d", inst, n); !exists(prev) {
			break
		}
	}
	if err := os.MkdirAll(prev, 0o777); err != nil {
		return err
	}
	for _, p := range inputs {
		if err := os.Rename(inst+"/"+filepath.Base(p), prev+"/"+filepath.Base(p)); err != nil {
			return err
		}
	}
	// files in the image are world readable so others can update the installation;
	// limit access with the permissions of the image file itself
	if _, ok := os.LookupEnv("CW_NO_FIX_PERM"); !ok {
		info(2, "Fixing permissions within squashfs image")
		if err := b.cmd(nil, "chmod", "-R", "ugo+rwX", inst).Run(); err != nil {
			return err
		}
	} else if err := b.cmd(nil, "chmod", "-R", "o+r", inst).Run(); err != nil {
		return err
	}

	info(1, "Creating sqfs image")
	cpus, _ := strconv.Atoi(c.get("num_cpus"))
	if m, _ := strconv.Atoi(c.get("max_num_cpus")); m > 0 && cpus > m {
		cpus = m
	}
	sqfs := b.sqfs()
	args := append([]string{inst + "/", sqfs, "-processors", strconv.Itoa(max(cpus, 1))}, strings.Fields(c.get("sqfs_options"))...)
	if err := b.cmd(nil, "mksquashfs", args...).Run(); err != nil {
		return err
	}
	if st, err := os.Stat(b.dir); err == nil && st.Mode().Perm()&0o020 != 0 {
		return os.Chmod(sqfs, 0o020|statPerm(sqfs))
	}
	return nil
}

func (b *build) img() string  { return b.deploy + "/" + b.c.get("container_image") }
func (b *build) sqfs() string { return b.deploy + "/" + b.c.get("sqfs_image") }

// imageBind is the bind mount of squashfs image src at dst.
func imageBind(src, dst string) string { return src + ":" + dst + ":image-src=/" }

func statPerm(p string) os.FileMode { st, _ := os.Stat(p); return st.Mode().Perm() }

// rootDirs lists the top level host directories, except device ones.
// common.sh in wrappers.go does the same with ls and awk when a launcher starts.
func rootDirs() []string {
	ents, _ := os.ReadDir("/")
	var r []string
	for _, e := range ents {
		if !strings.Contains(e.Name(), "dev") {
			r = append(r, "/"+e.Name())
		}
	}
	return r
}

func (b *build) post() error {
	c, p := b.c, b.c.get("installation_prefix")
	info(1, "Installing to %s", p)
	if c.yes("update_installation") {
		// bin can be busy on Lustre if the installation is in use elsewhere
		if err := os.RemoveAll(p + "/bin"); err != nil {
			warn("Failed to remove %s/bin due to it being in use\n\tContinuing anyway", p)
		}
		os.RemoveAll(p + "/_bin")
		os.RemoveAll(p + "/share")
	}
	ents, _ := os.ReadDir(b.deploy)
	args := []string{"-rd"}
	for _, e := range ents {
		args = append(args, b.deploy+"/"+e.Name())
	}
	if err := b.cmd(nil, "cp", append(args, p+"/")...).Run(); err != nil {
		return err
	}
	if err := os.MkdirAll(p+"/share", 0o777); err != nil {
		return err
	}
	if c.has("installation_file_paths") {
		if err := b.cmd(nil, "cp", "-r", b.dir+"/_inst_dir/previous_input", p+"/share").Run(); err != nil {
			return err
		}
	}
	v := fmt.Sprintf("tag: %s\ncommit: %s\nbuild-time: %s\n", version, commit, time.Now().Format(time.UnixDate))
	if err := os.WriteFile(p+"/share/VERSION.yml", []byte(v), 0o666); err != nil {
		return err
	}
	y, err := yaml.Marshal(map[string]any(c))
	if err != nil {
		return err
	}
	if err := os.WriteFile(p+"/share/conf.yaml", y, 0o666); err != nil {
		return err
	}
	exec.Command("chmod", "-R", "u+w", b.dir).Run()
	if os.RemoveAll(b.dir) != nil {
		warn("Failed to remove %s\n\tContinuing anyway", b.dir)
	}
	return nil
}
