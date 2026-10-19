package main

import (
	"fmt"
	"io"
	"os"
	"strings"
)

// A small argparse look-alike: the old Python frontends accepted abbreviated
// long options (--post), options after positionals and --opt=value.

type opt struct {
	long, short string
	flag        bool // store_true
	file        bool // value must be an existing path
	help        string
}

func (o opt) key() string     { return strings.ReplaceAll(strings.TrimLeft(o.long, "-"), "-", "_") }
func (o opt) metavar() string { return strings.ToUpper(o.key()) }

type cmd struct {
	prog, desc string
	opts       []opt
	pos        [][2]string // name, help
	subs       []*cmd      // subcommands; prog is the subcommand name
}

type args map[string]string

func (c *cmd) name() string { return c.prog[strings.LastIndex(c.prog, " ")+1:] }

func (c *cmd) usageLine() string {
	s := "usage: " + c.prog + " [-h]"
	for _, o := range c.opts {
		n := o.long
		if o.short != "" {
			n = o.short
		}
		if !o.flag {
			n += " " + o.metavar()
		}
		s += " [" + n + "]"
	}
	if len(c.subs) > 0 {
		s += " {" + c.subNames() + "} ..."
	}
	for _, p := range c.pos {
		s += " " + p[0]
	}
	return s
}

func (c *cmd) subNames() string {
	var n []string
	for _, s := range c.subs {
		n = append(n, s.name())
	}
	return strings.Join(n, ",")
}

func row(w io.Writer, left, help string) {
	if len(left) < 22 {
		fmt.Fprintf(w, "  %-22s%s\n", left, help)
	} else {
		fmt.Fprintf(w, "  %s\n  %22s%s\n", left, "", help)
	}
}

func (c *cmd) help(w io.Writer) {
	fmt.Fprintln(w, c.usageLine())
	if c.desc != "" {
		fmt.Fprintf(w, "\n%s\n", c.desc)
	}
	if len(c.pos) > 0 || len(c.subs) > 0 {
		fmt.Fprintln(w, "\npositional arguments:")
	}
	if len(c.subs) > 0 {
		row(w, "{"+c.subNames()+"}", "subcommands")
		for _, s := range c.subs {
			row(w, "  "+s.name(), s.desc)
		}
	}
	for _, p := range c.pos {
		row(w, p[0], p[1])
	}
	fmt.Fprintln(w, "\noptions:")
	row(w, "-h, --help", "show this help message and exit")
	for _, o := range c.opts {
		n := o.long
		if o.short != "" {
			n = o.short + ", " + n
		}
		if !o.flag {
			n += " " + o.metavar()
		}
		row(w, n, o.help)
	}
}

func (c *cmd) fail(msg string) {
	fmt.Fprintln(os.Stderr, c.usageLine())
	fmt.Fprintf(os.Stderr, "%s: error: %s\n", c.prog, msg)
	os.Exit(2)
}

func (c *cmd) lookup(name string) *opt {
	var hits []*opt
	for i := range c.opts {
		o := &c.opts[i]
		if name == o.long || (o.short != "" && name == o.short) {
			return o
		}
		if strings.HasPrefix(name, "--") && strings.HasPrefix(o.long, name) {
			hits = append(hits, o)
		}
	}
	switch len(hits) {
	case 0:
		c.fail("unrecognized arguments: " + name)
	case 1:
		return hits[0]
	}
	c.fail("ambiguous option: " + name)
	return nil
}

func (c *cmd) parse(argv []string) args {
	r := args{}
	var pos []string
	for i := 0; i < len(argv); i++ {
		a := argv[i]
		if a == "-h" || (len(a) > 2 && strings.HasPrefix("--help", a)) {
			c.help(os.Stdout)
			os.Exit(0)
		}
		if !strings.HasPrefix(a, "-") || a == "-" {
			if len(c.subs) > 0 {
				for _, s := range c.subs {
					if s.name() == a {
						r = s.parse(argv[i+1:])
						r["command"] = a
						return r
					}
				}
				c.fail(fmt.Sprintf("argument command: invalid choice: '%s' (choose from %s)", a, c.subNames()))
			}
			pos = append(pos, a)
			continue
		}
		name, val, hasVal := strings.Cut(a, "=")
		if !hasVal && !strings.HasPrefix(a, "--") && len(a) > 2 { // -rFILE
			name, val, hasVal = a[:2], a[2:], true
		}
		o := c.lookup(name)
		if o.flag {
			if hasVal {
				c.fail(fmt.Sprintf("argument %s: ignored explicit argument '%s'", o.long, val))
			}
			r[o.key()] = "true"
			continue
		}
		if !hasVal {
			if i++; i >= len(argv) {
				c.fail(fmt.Sprintf("argument %s: expected one argument", o.long))
			}
			val = argv[i]
		}
		if o.file {
			if _, err := os.Stat(val); err != nil {
				errorf("The file %s does not exist!", val)
				os.Exit(1)
			}
		}
		r[o.key()] = val
	}
	if len(pos) < len(c.pos) {
		var missing []string
		for _, p := range c.pos[len(pos):] {
			missing = append(missing, p[0])
		}
		c.fail("the following arguments are required: " + strings.Join(missing, ", "))
	}
	if len(pos) > len(c.pos) {
		c.fail("unrecognized arguments: " + strings.Join(pos[len(c.pos):], " "))
	}
	for i, p := range c.pos {
		r[p[0]] = pos[i]
	}
	return r
}
