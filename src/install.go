package main

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"os"
	"path"
	"regexp"
	"strings"
	"time"
)

// The installation runs as one bash shell inside the container, because conda/venv
// activation and the user's pre/post install snippets have to share it. Everything
// that can be decided on the host is decided here, so the script stays linear.

// Output of heavy steps is framed by these bytes, see console.
const stepStart, stepEnd = '\x1e', '\x1f'

const scriptHeader = `set -e
_cw_step(){ printf '\036'; local s=0; "$@" 2>&1 || s=$?; printf '\037'; return $s; }
`
const preInstall = `cd "$CW_WORKDIR"
source "$CW_INSTALLATION_PATH/_pre_install.sh"
`

var miniforgeURL = "https://github.com/conda-forge/miniforge/releases"

// installScript returns the script run in the container and extra environment for it.
// inst is the host directory mounted at installation_path.
func (b *build) installScript(inst string) (string, []string, error) {
	c := b.c
	ipath := c.get("installation_path")
	envRoot := inst + strings.TrimPrefix(b.envRoot(), ipath)
	s := scriptHeader
	var env []string
	if !c.yes("pipcache") {
		env = append(env, "PIP_NO_CACHE_DIR=1", "UV_NO_CACHE=1")
	}
	uv := c.yes("use_uv")
	post := `cd "$CW_WORKDIR"` + "\n" + say(1, "Running user supplied commands") + `source "$CW_INSTALLATION_PATH/_post_install.sh"` + "\n"
	pip := "_cw_step pip install"
	reqs := func() string {
		if !c.has("requirements_file") {
			return ""
		}
		return say(1, "Installing requirements file") + pip + ` -r "$(basename "$CW_REQUIREMENTS_FILE")"` + "\n"
	}
	switch c.get("mode") {
	case modeConda:
		if !exists(inst + "/miniforge") {
			if exists(inst + "/miniconda") {
				info(1, "Updating older installation which is using miniconda and not miniforge\nCreating symlink miniforge -> miniconda")
				if err := os.Symlink(ipath+"/miniconda", inst+"/miniforge"); err != nil {
					return "", nil, err
				}
			} else {
				v, err := miniforgeVersion(c.get("conda_version"))
				if err != nil {
					return "", nil, err
				}
				arch := c.get("conda_arch")
				info(1, "Using miniforge version Miniforge3-%s-%s", v, arch)
				info(2, "Downloading miniforge ")
				if err := download(fmt.Sprintf("%s/download/%s/Miniforge3-%s-%s.sh", miniforgeURL, v, v, arch), inst+"/Miniforge_inst.sh"); err != nil {
					return "", nil, err
				}
				s += say(1, "Installing miniforge ") + `_cw_step bash "$CW_INSTALLATION_PATH/Miniforge_inst.sh" -b -p "$CW_INSTALLATION_PATH/miniforge"` + "\n"
			}
		}
		s += `eval "$("$CW_INSTALLATION_PATH/miniforge/bin/conda" shell.bash hook)"` + "\n" + preInstall + `cd "$CW_INSTALLATION_PATH"` + "\n"
		if uv {
			env = append(env, "UV_LINK_MODE=copy")
		}
		if !exists(envRoot) {
			tool, create, ff := "conda", " create -y", "--file"
			if regexp.MustCompile(`\.ya?ml`).MatchString(c.get("env_file")) {
				tool, ff = "conda env", "-f"
			}
			if c.yes("mamba") {
				info(1, "Using mamba to install packages")
				tool = strings.Replace(tool, "conda", "mamba", 1)
				if uv {
					create += " --use-uv"
				}
			}
			s += say(1, "Creating env, full log in "+b.dir+"/build.log")
			s += "_cw_step " + tool + create + ` --name "$CW_ENV_NAME" ` + ff + ` "$(basename "$CW_ENV_FILE")"` + "\n"
		}
		s += `conda activate "$CW_ENV_NAME"` + "\n"
		if uv {
			pip = "_cw_step uv pip install"
		}
		s += reqs() + post + `_cw_bin="$CW_INSTALLATION_PATH/miniforge/envs/$CW_ENV_NAME/bin"
if [[ -d $_cw_bin ]]; then
    { echo 'echo "'; conda list; echo '"'; } > "$_cw_bin/list-packages"
    chmod +x "$_cw_bin/list-packages"
else :
` + say(0, "Created env is empty") + "fi\n"
	case modeVenv:
		s += preInstall + `cd "$CW_INSTALLATION_PATH"` + "\n"
		if uv {
			if !exists(inst + "/uv/bin/uv") {
				info(1, "Installing uv package manager")
				if err := download("https://astral.sh/uv/install.sh", inst+"/uv_install.sh"); err != nil {
					return "", nil, err
				}
				s += `UV_UNMANAGED_INSTALL="$CW_INSTALLATION_PATH/uv/bin/" UV_PRINT_QUIET=1 sh "$CW_INSTALLATION_PATH/uv_install.sh"` + "\n"
			}
			s += `export PATH="$CW_INSTALLATION_PATH/uv/bin/:$PATH"` + "\n"
			env = append(env, "UV_PYTHON_INSTALL_DIR="+ipath+"/uv/python")
		}
		if !exists(envRoot + "bin/activate") {
			sp := ""
			if c.yes("enable_site_packages") {
				info(1, "Enabling system and user site packages")
				sp = " --system-site-packages"
			} else {
				info(1, "Not enabling system and user site packages")
			}
			s += say(1, "Creating virtual environment")
			if uv {
				s += `uv venv -p "$CW_PYVER"` + sp + ` --managed-python --no-config --link-mode=copy "$env_root"` + "\n"
			} else {
				s += "python3 -m venv" + sp + ` "$CW_ENV_NAME"` + "\n"
			}
		}
		s += `source "$env_root/bin/activate"` + "\n"
		pip += " --disable-pip-version-check"
		if uv {
			pip = "_cw_step uv pip install --link-mode=copy --compile-bytecode"
		}
		s += reqs() + post
	case modeWrapDisk:
		s += `cp -a "$CW_SOURCE_MOUNT_POINT/." "$CW_INSTALLATION_PATH"` + "\n" + preInstall + post
	}
	return s, env, nil
}

// say returns a script line printing msg like info (lvl 1) or warn (lvl 0) would.
func say(lvl int, msg string) string {
	if logLevel <= lvl {
		return ""
	}
	c, tag := "\033[1;34m", "INFO"
	if lvl == 0 {
		c, tag = "\033[1;33m", "WARNING"
	}
	if color {
		tag = c + tag + "\033[0m"
	}
	ts := ""
	if logLevel > 2 {
		ts = " $(date +%H:%M:%S)"
	}
	return fmt.Sprintf("echo \"[ %s%s ] \"%s\n", tag, ts, shq(msg+" "))
}

// miniforgeVersion resolves "latest" to the newest release tag.
func miniforgeVersion(v string) (string, error) {
	if v == "latest" {
		resp, err := http.Head(miniforgeURL + "/latest")
		if err != nil {
			return "", err
		}
		resp.Body.Close()
		v = path.Base(resp.Request.URL.Path)
	}
	if !regexp.MustCompile(`^[0-9.-]+$`).MatchString(v) {
		return "", fmt.Errorf("Failed to resolve what version of miniforge to download")
	}
	info(2, "Resolved newest miniforge release to %s", v)
	return v, nil
}

func download(url, dst string) error {
	resp, err := http.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("Downloading %s failed: %s", url, resp.Status)
	}
	f, err := os.Create(dst)
	if err != nil {
		return err
	}
	if _, err := io.Copy(f, resp.Body); err != nil {
		f.Close()
		return err
	}
	return f.Close()
}

// console passes the installation output through, except for heavy steps: their
// output goes to the build log and, on a terminal, only its last lines are shown,
// redrawn in place.
type console struct {
	out, log io.Writer
	tty      bool
	step     bool
	tail     string
	drawn    int
	last     time.Time
}

const followLines = 20

func (c *console) Write(p []byte) (int, error) {
	n := len(p)
	for len(p) > 0 {
		mark := byte(stepStart)
		if c.step {
			mark = stepEnd
		}
		i := bytes.IndexByte(p, mark)
		chunk := p
		if i >= 0 {
			chunk = p[:i]
		}
		if c.step {
			c.log.Write(chunk)
			c.show(chunk, i >= 0)
		} else {
			c.out.Write(chunk)
		}
		if i < 0 {
			break
		}
		c.step, c.tail, c.drawn, p = !c.step, "", 0, p[i+1:]
	}
	return n, nil
}

func (c *console) show(p []byte, final bool) {
	if !c.tty {
		c.out.Write(p)
		return
	}
	c.tail += string(p)
	if len(c.tail) > 1<<16 { // keep enough for the last lines
		c.tail = c.tail[len(c.tail)-1<<15:]
	}
	ls := strings.Split(strings.TrimSuffix(c.tail, "\n"), "\n")
	if len(ls) > followLines {
		ls = ls[len(ls)-followLines:]
	}
	if c.tail == "" || !final && time.Since(c.last) < 200*time.Millisecond {
		return
	}
	c.last = time.Now()
	// shortcut: lines wider than the terminal wrap and are not fully erased, fine for typical output
	io.WriteString(c.out, strings.Repeat("\033[F\033[K", c.drawn)+strings.Join(ls, "\n")+"\n")
	c.drawn = len(ls)
}
