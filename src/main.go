// Tykky: wrap installations inside an Apptainer/Singularity container.
// One binary; the frontend is picked by its first argument.
package main

import (
	"errors"
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

// set with -ldflags by the Makefile
var version, commit, config string

var (
	logLevel = 2
	tty      = func() bool { st, err := os.Stdout.Stat(); return err == nil && st.Mode()&os.ModeCharDevice != 0 }()
	color    = tty && os.Getenv("USE_COLOR") != "no"
)

func logmsg(c, tag, f string, a ...any) {
	ts := ""
	if logLevel > 2 {
		ts = " " + time.Now().Format("15:04:05")
	}
	if color {
		tag = c + tag + "\033[0m"
	}
	msg := strings.ReplaceAll(fmt.Sprintf(f, a...), "\n", "\n         ")
	fmt.Printf("[ %s%s ] %s \n", tag, ts, msg)
}

// info prints when CW_LOG_LEVEL > lvl; 1 is INFO, higher is DEBUG.
func info(lvl int, f string, a ...any) {
	if logLevel <= lvl {
		return
	}
	if lvl == 1 {
		logmsg("\033[1;34m", "INFO", f, a...)
	} else {
		logmsg("\033[0;35m", "DEBUG", f, a...)
	}
}

func warn(f string, a ...any) {
	if logLevel > 0 {
		logmsg("\033[1;33m", "WARNING", f, a...)
	}
}

func errorf(f string, a ...any) { logmsg("\033[0;31m", "ERROR", f, a...) }

func fatal(f string, a ...any) {
	errorf(f, a...)
	os.Exit(1)
}

func loadYAML(path string) (map[string]any, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	m := map[string]any{}
	if err := yaml.Unmarshal(b, &m); err != nil {
		return nil, fmt.Errorf("Failed to parse %s: %v", path, err)
	}
	return m, nil
}

var (
	prefixOpt  = opt{long: "--prefix", help: "Installation location"}
	postOpt    = opt{long: "--post-install", file: true, help: "Script to run after initial setup"}
	preOpt     = opt{long: "--pre-install", file: true, help: "Script to run before initial setup"}
	environOpt = opt{long: "--environ", file: true, help: "Script to run before each program launch"}
	wrapOpt    = opt{long: "--wrapper-paths", short: "-w", help: "Comma separated list of paths"}
	yamlOpt    = opt{long: "--yaml", short: "-y", help: "Tool yaml conf file"}
	nocacheOpt = opt{long: "--nocache", flag: true, help: "Do not use pip/uv cache"}
	baseOpts   = []opt{postOpt, preOpt, environOpt, wrapOpt}
)

func subcommands(prog, desc string, newCmd, updCmd *cmd) *cmd {
	newCmd.prog, newCmd.desc = prog+" new", "Create new installation"
	updCmd.prog, updCmd.desc = prog+" update", "update an existing installation"
	updCmd.pos = [][2]string{{"dir", "Installation to update"}}
	adv := &cmd{prog: prog + " advanced", pos: [][2]string{{"yaml", "yaml file with tool config"}}}
	return &cmd{prog: prog, desc: desc, subs: []*cmd{newCmd, updCmd, adv}}
}

// toConf sets the tool specific user configuration from the parsed arguments.
type toConf func(a args, conf map[string]any) error

// tools maps each frontend name to its command line and its toConf.
var tools = map[string]func(prog string) (*cmd, toConf){
	"conda":          condaTool,
	"pip":            pipTool,
	"wrap-container": wrapContainerTool,
	"wrap-install":   wrapInstallTool,
}

func condaTool(prog string) (*cmd, toConf) {
	req := opt{long: "--requirement", short: "-r", file: true, help: "requirements file for pip"}
	c := subcommands(prog, "Create or modify a Conda installation inside a container",
		&cmd{pos: [][2]string{{"env_file", "conda env file"}}, opts: append([]opt{prefixOpt,
			{long: "--mamba", flag: true, help: "use mamba for installation"},
			{long: "--uv", flag: true, help: "use uv for pip dependencies (only with mamba)"},
			nocacheOpt, req}, baseOpts...)},
		&cmd{opts: append([]opt{nocacheOpt, req}, baseOpts...)})
	return c, func(a args, conf map[string]any) error {
		conf["add_ld"], conf["use_uv"], conf["mode"] = "no", "no", modeConda
		if a["command"] == "new" {
			if st, err := os.Stat(a["env_file"]); err != nil || st.IsDir() {
				return fmt.Errorf("Env file %s does not exist", a["env_file"])
			}
			conf["env_file"] = a["env_file"]
			conf["update_installation"] = "no"
			conf["installation_file_paths"] = []any{a["env_file"]}
			conf["mamba"] = yesno(a["mamba"] != "")
			if a["uv"] != "" && a["mamba"] != "" {
				conf["use_uv"] = "yes"
			} else if a["uv"] != "" {
				warn("Using --uv without --mamba does not have an effect")
			}
		}
		if a["requirement"] != "" {
			conf["requirements_file"] = a["requirement"]
			conf["installation_file_paths"] = append(list(conf["installation_file_paths"]), a["requirement"])
		}
		return nil
	}
}

func pipTool(prog string) (*cmd, toConf) {
	c := subcommands(prog, "Create or modify a python installation inside a container",
		&cmd{pos: [][2]string{{"requirements_file", "requirements file for pip"}}, opts: append([]opt{prefixOpt,
			{long: "--uv", flag: true, help: "Use uv"},
			{long: "--slim", flag: true, help: "Use minimal base python container"},
			{long: "--pyver", help: "Python version to use for slim or uv modes"},
			{long: "--system-site-packages", flag: true, help: "Enable system and user site packages for the created installation"},
			nocacheOpt}, baseOpts...)},
		&cmd{opts: append([]opt{{long: "--requirements-file", short: "-r", file: true, help: "requirements file for pip"}, nocacheOpt}, baseOpts...)})
	return c, func(a args, conf map[string]any) error {
		if a["uv"] != "" && a["slim"] != "" {
			return c.fail("argument --slim: not allowed with argument --uv")
		}
		if a["requirements_file"] != "" {
			if !exists(a["requirements_file"]) {
				return fmt.Errorf("The file %s does not exist!", a["requirements_file"])
			}
			conf["requirements_file"] = a["requirements_file"]
			conf["installation_file_paths"] = []any{a["requirements_file"]}
		}
		if a["command"] != "new" {
			return nil
		}
		conf["use_uv"], conf["update_installation"] = "no", "no"
		if a["system_site_packages"] != "" {
			conf["enable_site_packages"] = "yes"
		}
		switch pv := a["pyver"]; {
		case a["slim"] != "":
			conf["pyver"] = "slim"
			if pv != "" {
				if strings.Contains(pv, "-slim") || pv == "slim" {
					conf["pyver"] = pv
				} else {
					conf["pyver"] = pv + "-slim"
				}
			}
			conf["container_src"] = fmt.Sprintf("docker://python:%s", conf["pyver"])
			conf["isolate"] = "yes"
		case a["uv"] != "":
			conf["use_uv"] = "yes"
			conf["pyver"] = "3"
			if pv != "" {
				conf["pyver"] = pv
			}
		case pv != "":
			warn("Using --pyver without --slim or --uv does not have an effect")
		}
		return nil
	}
}

func wrapContainerTool(prog string) (*cmd, toConf) {
	c := &cmd{prog: prog, desc: "Create wrappers for executables inside a container",
		pos:  [][2]string{{"container", "Container to wrap, can be docker/singularity url"}},
		opts: []opt{yamlOpt, environOpt, wrapOpt, prefixOpt}}
	return c, func(a args, conf map[string]any) error {
		conf["container_src"], conf["isolate"], conf["mode"] = a["container"], "yes", modeWrapCont
		return requireWrapperPaths(prog, a)
	}
}

func wrapInstallTool(prog string) (*cmd, toConf) {
	c := &cmd{prog: prog, desc: "Wrap an existing installation into a container",
		pos: [][2]string{{"dir", "Installation to wrap"}},
		opts: append(append([]opt{}, baseOpts...), prefixOpt, yamlOpt,
			opt{long: "--mask", flag: true, help: "Mask installation on disk"})}
	return c, func(a args, conf map[string]any) error {
		src := realpath(a["dir"])
		conf["isolate"], conf["mode"], conf["wrap_src"] = "no", modeWrapDisk, src
		conf["update_installation"] = "no"
		if a["mask"] != "" {
			conf["installation_path"] = src
			if !hasApptainer() {
				conf["excluded_mount_points"] = "/" + strings.Split(src, "/")[1]
			}
			conf["mask_wrap_install"] = "yes"
		}
		return requireWrapperPaths(prog, a)
	}
}

func requireWrapperPaths(prog string, a args) error {
	if a["wrapper_paths"] == "" {
		return fmt.Errorf("Tool %s requires -w/--wrapper-paths to be used", prog)
	}
	return nil
}

// frontend parses argv into the user configuration, like frontends/*.py did.
func frontend(prog string, argv []string, global map[string]any) (map[string]any, error) {
	tool, ok := tools[prog]
	if !ok {
		names := slices.Sorted(maps.Keys(tools))
		usage := fmt.Sprintf("usage: containerize {%s} ...", strings.Join(names, ","))
		if prog == "" || prog == "-h" || prog == "--help" {
			fmt.Println(usage)
			return nil, errHelp
		}
		return nil, fmt.Errorf("%s\nUnknown subcommand %s", usage, prog)
	}
	c, toolConf := tool("containerize " + prog)
	if len(argv) == 0 {
		c.help(os.Stdout)
		return nil, errHelp
	}
	a, err := c.parse(argv)
	if err != nil {
		return nil, err
	}
	if c.subs != nil && a["command"] == "" {
		return nil, c.fail("a subcommand is required")
	}

	conf := map[string]any{}
	if err := toolConf(a, conf); err != nil {
		return nil, err
	}
	if a["prefix"] != "" {
		conf["installation_prefix"] = a["prefix"]
	}
	if a["command"] == "update" {
		conf["update_installation"] = "yes"
		if err := oldConf(a["dir"], conf); err != nil {
			return nil, err
		}
	}
	if a["yaml"] != "" { // advanced subcommand or -y
		y, err := loadYAML(a["yaml"])
		if err != nil {
			return nil, err
		}
		maps.Copy(conf, y)
	}
	if a["command"] != "advanced" {
		if a["environ"] != "" {
			conf["extra_envs"] = []any{map[string]any{"file": a["environ"]}}
		}
		if a["post_install"] != "" {
			conf["post_install"] = []any{map[string]any{"file": a["post_install"]}}
		}
		if a["pre_install"] != "" {
			conf["pre_install"] = []any{map[string]any{"file": a["pre_install"]}}
		}
	}
	if err := addWrapperPaths(conf, global, a["wrapper_paths"], prog == "wrap-container"); err != nil {
		return nil, err
	}
	if prog == "pip" { // also over an updated installation's mode or the advanced yaml
		conf["mode"] = modeVenv
	}
	if (prog == "pip" || prog == "conda") && a["command"] != "advanced" {
		conf["pipcache"] = yesno(a["nocache"] == "")
	}
	return conf, nil
}

// addWrapperPaths appends -w paths; relative ones are resolved against
// installation_path later.
func addWrapperPaths(conf, global map[string]any, w string, reqAbs bool) error {
	if w == "" {
		return nil
	}
	_, hasIP := conf["installation_path"]
	for _, sec := range []string{"force", "defaults"} {
		if m, ok := global[sec].(map[string]any); ok && m["installation_path"] != nil {
			hasIP = true
		}
	}
	if !hasIP && !reqAbs {
		return fmt.Errorf("Failed to parse wrapper paths, missing installation path")
	}
	paths := list(conf["wrapper_paths"])
	for _, p := range strings.Split(w, ",") {
		if reqAbs && !strings.HasPrefix(p, "/") {
			return fmt.Errorf("Only absolute paths are accepted for --wrapper-paths/-w")
		}
		paths = append(paths, p)
	}
	conf["wrapper_paths"] = paths
	return nil
}

// oldConf loads the settings of an existing installation for "update".
func oldConf(d string, conf map[string]any) error {
	if _, err := os.Stat(d + "/share/conf.yaml"); err != nil {
		return fmt.Errorf("Directory %s does not exist or is not a valid installation ( missing share/conf.yaml )", d)
	}
	old, err := loadYAML(d + "/share/conf.yaml")
	if err != nil {
		return err
	}
	// an installation using a shared container keeps doing so
	if yes(old["share_container"]) {
		conf["container_src"] = old["container_src"]
	} else {
		conf["container_src"] = d + "/" + str(old["container_image"])
	}
	conf["sqfs_src"] = d + "/" + str(old["sqfs_image"])
	conf["installation_prefix"] = d
	for _, k := range []string{"installation_path", "sqfs_image", "container_image", "isolate", "mode"} {
		conf[k] = old[k]
	}
	for _, k := range []string{"mamba", "use_uv", "pipcache", "wrapper_paths"} {
		if v, ok := old[k]; ok {
			conf[k] = v
		}
	}
	return nil
}

func main() {
	if l, err := strconv.Atoi(os.Getenv("CW_LOG_LEVEL")); err == nil {
		logLevel = l
	}
	prog, argv := "", []string{}
	if len(os.Args) > 1 {
		prog, argv = os.Args[1], os.Args[2:]
	}
	globalPath := os.Getenv("CW_GLOBAL_YAML")
	if globalPath == "" {
		exe, _ := os.Executable()
		globalPath = filepath.Join(filepath.Dir(realpath(exe)), "../configs", config+".yaml")
	}
	global, err := loadYAML(globalPath)
	if err != nil {
		fatal("%v", err)
	}
	user, err := frontend(prog, argv, global)
	var ue usageError
	switch {
	case errors.Is(err, errHelp):
		os.Exit(0)
	case errors.As(err, &ue):
		fmt.Fprintln(os.Stderr, ue.c.usageLine())
		fmt.Fprintln(os.Stderr, ue)
		os.Exit(2)
	case err != nil:
		fatal("%v", err)
	}
	info(2, "Calling parsers script %s", prog)
	info(2, "Using %s as default config", realpath(globalPath))
	os.Exit(run(globalPath, global, user))
}
