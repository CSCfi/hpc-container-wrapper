package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestTykkyShellFunctions(t *testing.T) {
	script, _ := filepath.Abs("../etc/profile.d/tykky.sh")
	dir := t.TempDir()
	for _, env := range []string{"tp/e", "cwd/e", "cwd/x y"} {
		os.MkdirAll(filepath.Join(dir, env, "bin"), 0o755)
		os.MkdirAll(filepath.Join(dir, env, "_bin"), 0o755)
	}
	for _, tc := range []struct{ name, cmds, want string }{
		{"by path with a space, later PATH changes kept",
			`o=$PATH; tykky activate "./x y"; [ "$PATH" = "$TYKKY_PREFIX/bin:$o" ] && echo on; PATH=/a:$PATH; tykky deactivate; [ "$PATH" = "/a:$o" ] && echo off`,
			"on\noff\n"},
		{"by name from TYKKY_PATH",
			`TYKKY_PATH=/nope:` + dir + `/tp; cd /; tykky activate e; echo "$TYKKY_PREFIX"`,
			dir + "/tp/e\n"},
		{"current directory wins over TYKKY_PATH",
			`TYKKY_PATH=` + dir + `/tp; tykky activate e 2>/dev/null; echo "$TYKKY_PREFIX"`,
			dir + "/cwd/e\n"},
		{"PS1 restored, reactivation replaces",
			`PS1='$ '; tykky activate e; tykky activate "./x y"; echo "$PS1"; tykky deactivate; echo "$PS1|$TYKKY_PREFIX"`,
			"(x y) $ \n$ |\n"},
		{"invalid env fails",
			`tykky activate missing 2>/dev/null || echo failed`,
			"failed\n"},
	} {
		c := exec.Command("bash", "--norc", "-c", ". '"+script+"'\n"+tc.cmds)
		c.Dir = filepath.Join(dir, "cwd")
		out, err := c.CombinedOutput()
		if err != nil || string(out) != tc.want {
			t.Errorf("%s: got %q, %v want %q", tc.name, out, err, strings.TrimSpace(tc.want))
		}
	}
}
