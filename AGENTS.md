# AGENTS.md

Tykky (`containerize`) is a single Go binary that wraps conda/pip/existing
installations into an Apptainer/Singularity container and squashfs image, and
generates bash launcher scripts for them. Read `README.md` for the user-facing
behaviour.

## Layout

- `src/` is one `package main`, with no subpackages:
  - `main.go`: logging, the frontends (`conda`, `pip`, `wrap-container`,
    `wrap-install`) and how they turn arguments into config.
  - `args.go`: the hand-written argument parser and help output.
  - `config.go`: config helpers and the merge logic.
  - `build.go`: the build pipeline (prepare, fetch, install, squashfs).
  - `install.go`: the generated install script, Miniforge download, and
    console output.
  - `wrappers.go`: the generated launcher scripts.
- `configs/*.yaml`: per-site configs. `make` embeds the name of the chosen one
  in the binary and copies the file to `$PREFIX/configs`, where it is read at
  runtime. `configs/template.yaml` is the documented starting point for new
  sites. All configs carry the same keys, so a new key goes in every one.
- `etc/`: the `tykky` shell function and bash completion. `modulefiles/`: the
  Lmod template.
- `tests/*.sh`: end-to-end tests that need apptainer/singularity.

## Build and test

```
make CONFIG=local                    # builds ./build/bin/containerize
go vet ./src && go test ./src        # unit tests, no container runtime needed
gofmt -l src                         # must print nothing
shellcheck tests/*.sh etc/profile.d/tykky.sh
```

The end-to-end tests run against `build/bin`, so run `make` first. Run them
from `tests/`, where they create `TEST_DIR_*` directories and `test.log`:

```
cd tests && CONFIG=local bash pip.sh
```

They need apptainer or singularity and network access, and take minutes. If
neither is available, say so instead of claiming they pass.

## Conventions

- Generated shell code (install script, wrappers) is built as Go strings.
  Quote values with `shq`/`dq` in `wrappers.go`; the unit tests check the
  output with `bash -n`, so keep that passing.
- Format shell scripts you edit with `shfmt -i 4 -ci -w <file>`, and keep
  them passing `shellcheck`.
- Environment variables are split into build (`containerize`) and runtime
  (launchers) in `README.md`; update the right table when adding or removing
  one.
- Keep `README.md` and the configs' comments in step with behaviour changes.
- Commit messages: imperative subject, body says why.
